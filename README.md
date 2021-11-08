# PowerShell-ssh-pageant

This a simple implementation in PowerShell that listen on a named pipe and forward all the requests to a Pageant-like agent. This allows the built-in OpenSSH commands on Windows to be used with Pageant or Gpg4Win.

The advantage of using a PowerShell script is that it can run on Windows using the built-in tools. No need to install additional binaries.

## Setup

You will need either Pagent or Gpg4Win. For the later you can follow the setup: <https://developers.yubico.com/PGP/SSH_authentication/Windows.html>.
In short, install Gpg4Win then put in %APPDATA%\gnupg\gpg-agent.conf

    enable-putty-support
    enable-ssh-support
    default-cache-ttl 600
    max-cache-ttl 7200

then restart your agent using the below commands:

    gpg-connect-agent.exe killagent /bye
    gpg-connect-agent.exe /bye

To allow the Windows OpenSSH apps to use Pageant you need to make then point to the name pipe defined in the script by setting then env var in your terminal ```$env:SSH_AUTH_SOCK = "\\.\pipe\ssh-pageant"``` or in the windows menu.

Then to connect it all together run the script ```ssh-pageant.ps1```.

## Similar projects and good source of information

<https://github.com/benpye/wsl-ssh-pageant/>
<https://gist.github.com/coldacid/6e4e8306bcdc0a8954961454bc2558ee>
<https://github.com/manojampalam/ssh-agent-adapter/>
<https://github.com/dlech/SshAgentLib/>
<https://github.com/PowerShell/Win32-OpenSSH/issues/827>
