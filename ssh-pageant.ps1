
# MIT License
#
# Copyright (c) 2021 Maxime Biette
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    public class Win32 {
        [DllImport("user32.dll", CharSet=CharSet.Auto, SetLastError=true)]
        public static extern IntPtr FindWindow(StringBuilder lpClassName, StringBuilder lpWindowName);

        [DllImport("user32.dll")]
        public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    }
"@

$Domain = [System.AppDomain]::CurrentDomain
$AssemblyName = [System.Reflection.AssemblyName]::new('Messages')
$Assembly = $Domain.DefineDynamicAssembly($AssemblyName, 'Run')
$ModuleBuilder = $Assembly.DefineDynamicModule('Messages')
$StructureAttributes = 'AutoLayout, AnsiClass, Class, Public, SequentialLayout, BeforeFieldInit'
$COPYDATASTRUCT = $ModuleBuilder.DefineType('COPYDATASTRUCT', $StructureAttributes)
$COPYDATASTRUCT.DefineField('dwData', [System.IntPtr], 'Public')
$COPYDATASTRUCT.DefineField('cbData', [Int64], 'Public')
$COPYDATASTRUCT.DefineField('lpData', [System.IntPtr], 'Public')
$COPYDATASTRUCT.CreateType()

$agentMaxMessageLength = 8192
$agentCopyDataID = 0x804E50BA
$WM_COPYDATA = 0x004A
[byte[]] $failureMessage = 0, 0, 0, 1, 5

while ($true) {
    try {
        $npipeServer = [System.IO.Pipes.NamedPipeServerStream]::new(
            'ssh-pageant',
            [System.IO.Pipes.PipeDirection]::InOut,
            -1,
            [System.IO.Pipes.PipeTransmissionMode]::Byte,
            [System.IO.Pipes.PipeOptions]::Asynchronous -bor [System.IO.Pipes.PipeOptions]::CurrentUserOnly
        )

        try{
            while ($true) {
                Write-Output "Waiting for connection..."
                $npipeServer.WaitForConnection()
                try{
                    :connectedloop while ($true) {
                        Start-Sleep -Milliseconds 10
                        if (!$npipeServer.CanRead) {
                            Write-Output "Not connected anymore (1)"
                            break
                        }
                        Write-Output "Get request length"
                        $buf_len = [byte[]]::new(4)

                        $asyncResult = $npipeServer.BeginRead($buf_len, 0, 4, $null, $null)
                        $max_wait = 10
                        while (!$asyncResult.IsCompleted) {
                            Start-Sleep -Milliseconds 100
                            $max_wait--
                            if ($max_wait -le 0) {
                                Write-Output "Client is hanging"
                                break connectedloop
                            }
                        }
                        $npipeServer.EndRead($asyncResult)
                        
                        [Array]::Reverse($buf_len)
                        $len = [System.BitConverter]::ToUInt32($buf_len, 0)
                        Write-Output "Request length: $len"
                        if ($len -eq 0 -or !$npipeServer.IsConnected) {
                            Write-Output "Not connected anymore (2)"
                            break
                        }
                        Write-Output "Getting request."
                        $request = [byte[]]::new($len)
                        $npipeServer.Read($request, 0, $len)
                        [Array]::Reverse($buf_len) # Will need it again later to send to Pageant

                        try {
                            Write-Output "Looking for Pageant."
                            $pageant_ptr = [Win32]::FindWindow("Pageant", "Pageant")
                            if ($pageant_ptr -eq [System.IntPtr]::Zero) {
                                throw "Pageant is not running"
                            }

                            $current_tid = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                            $map_name = "PageantRequest$current_tid"
                            Write-Output "Map name: $map_name"
                            $map = [System.IO.MemoryMappedFiles.MemoryMappedFile]::CreateNew($map_name, $agentMaxMessageLength)
                            try{
                                $stream = $map.CreateViewStream()
                                try{
                                    # Pageant request and notification
                                    Write-Output "Writing request in SHM"
                                    $stream.Write($buf_len + $request, 0, 4 + $request.Length)

                                    $copyData = [COPYDATASTRUCT]::new()
                                    $copyData.dwData = $agentCopyDataID
                                    $copyData.cbData = $map_name.Length + 1  # 1 char more for terminating \0
                                    $copyData.lpData = [System.Runtime.InteropServices.Marshal]::StringToCoTaskMemAnsi($map_name)

                                    $copyDataPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(
                                        [System.Runtime.InteropServices.Marshal]::SizeOf($copyData)
                                    )
                                    [System.Runtime.InteropServices.Marshal]::StructureToPtr($copyData, $copyDataPtr, $true)
                                    try {
                                        Write-Output "Sending notification to Pageant"
                                        $resultPtr = [Win32]::SendMessage($pageant_ptr, $WM_COPYDATA, [System.IntPtr]::Zero, $copyDataPtr)
                                        if ($resultPtr -eq [System.IntPtr]::Zero) {
                                            throw "WM_COPYDATA failed"
                                        }
                                    }
                                    finally {
                                        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($copyData.lpData)
                                        [System.Runtime.InteropServices.Marshal]::FreeHGlobal($copyDataPtr)
                                    }

                                    # Pageant reply
                                    Write-Output "Getting reply length from SHM."
                                    $buf_len = [byte[]]::new(4)
                                    $stream.Position = 0
                                    $stream.Read($buf_len, 0, 4)
                                    [Array]::Reverse($buf_len)
                                    $len = [System.BitConverter]::ToUInt32($buf_len, 0) + 4
                                    if ($len -gt $agentMaxMessageLength) {
                                        throw "Return message too long"
                                    }
                                    if ($len -eq 0) {
                                        Write-Output "No message in SHM?!"
                                        $npipeServer.Write([byte[]](0, 0, 0, 0), 4)
                                        break
                                    }
                                    Write-Output "Getting reply message from SHM."
                                    $reply = [byte[]]::new($len)
                                    $stream.Position = 0
                                    $stream.Read($reply, 0, $reply.Length)
                                }
                                finally {
                                    $stream.Dispose()
                                }
                            }
                            finally {
                                $map.Dispose()
                            }
                            # Forward reply
                            Write-Output "Forwarding te reply."
                            $npipeServer.Write($reply, 0, $reply.Length)
                        }
                        catch {
                            Write-Output "An error occured" $_
                            if($npipeServer.CanWrite) {
                                $npipeServer.Write($failureMessage, 0, $failureMessage.Length)
                            }
                        }
                    }
                }
                finally {
                    Write-output "Closing named pipe."
                    $npipeServer.Disconnect()
                }
            }
        }
        finally {
            $npipeServer.Dispose()
        }
    }
    catch {
        Write-Output "An error occured" $_
        Write-Output "Recreating the named pipe"
    }
}