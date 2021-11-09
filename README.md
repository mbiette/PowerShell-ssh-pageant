# PowerShell-ssh-pageant

This a simple implementation in PowerShell that listen on a named pipe and forward all the requests to a Pageant-like agent. This allows the built-in OpenSSH commands on Windows to be used with Pageant or Gpg4Win.

The advantage of using a PowerShell script is that it can run on Windows using the built-in tools. No need to install additional binaries.

## Setup

You will need either Pagent or Gpg4Win. For the later you can follow the setup: <https://developers.yubico.com/PGP/SSH_authentication/Windows.html>.
In short, install Gpg4Win then put in `%APPDATA%\gnupg\gpg-agent.conf`

```text
enable-putty-support
enable-ssh-support
default-cache-ttl 600
max-cache-ttl 7200
```

then restart your agent using the below commands:

```PowerShell
gpg-connect-agent.exe killagent /bye
gpg-connect-agent.exe /bye
```

To allow the Windows OpenSSH apps to use Pageant you need to make then point to the name pipe defined in the script by setting then env var in your terminal ```$env:SSH_AUTH_SOCK = "\\.\pipe\ssh-pageant"``` or in the windows menu.

Then to connect it all together run the script ```ssh-pageant.ps1```.

## Similar projects and good source of information

* <https://github.com/benpye/wsl-ssh-pageant/>
* <https://gist.github.com/coldacid/6e4e8306bcdc0a8954961454bc2558ee>
* <https://github.com/manojampalam/ssh-agent-adapter/>
* <https://github.com/dlech/SshAgentLib/>
* <https://github.com/PowerShell/Win32-OpenSSH/issues/827>

## Signing the script

If your Windows is configured to only run PowerShell scripts that have been signed you will need to sign the script yourself. If you don't already have a certificate the easiest is the create a self-signed one. For example by following these instructions: <https://adamtheautomator.com/how-to-sign-powershell-script/#Obtaining_a_Code_Signing_Certificate>

In short

```PowerShell
# Generate self signed cert in CurrentUser Personal store
$authenticode = New-SelfSignedCertificate -Subject "My Code Signing Cert" -CertStoreLocation Cert:\CurrentUser\My -Type CodeSigningCert

# Install it in Root and TrustedPublisher stores
$rootStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("Root","CurrentUser")
$rootStore.Open("ReadWrite")
$rootStore.Add($authenticode)
$rootStore.Close()
$publisherStore = [System.Security.Cryptography.X509Certificates.X509Store]::new("TrustedPublisher","CurrentUser")
$publisherStore.Add($authenticode)
$publisherStore.Close()

# Check that it was installed
Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.Subject -eq "CN=My Code Signing Cert"}
Get-ChildItem Cert:\CurrentUser\Root | Where-Object {$_.Subject -eq "CN=My Code Signing Cert"}
Get-ChildItem Cert:\CurrentUser\TrustedPublisher | Where-Object {$_.Subject -eq "CN=My Code Signing Cert"}

# Signed the script
$codeCertificate = Get-ChildItem Cert:\CurrentUser\My | Where-Object {$_.Subject -eq "CN=My Code Signing Cert"}
Set-AuthenticodeSignature -FilePath C:\src\ssh-pageant.ps1 -Certificate $codeCertificate -TimeStampServer http://timestamp.digicert.com
```
