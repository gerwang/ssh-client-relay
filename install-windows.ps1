param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $RelayHost,
    [Parameter(Mandatory = $true, Position = 1)] [string] $TargetAlias,
    [Parameter(Mandatory = $true, Position = 2)] [string] $TargetHost,
    [string] $InstallDirectory = "$env:USERPROFILE\bin",
    [string] $ConfigDirectory = "$env:USERPROFILE\.config\ssh-client-relay",
    [string] $RemoteHelper = ".local/bin/ssh-client-relay-helper"
)

$ErrorActionPreference = "Stop"
$RepoDirectory = $PSScriptRoot
$Ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$Scp = (Get-Command scp.exe -ErrorAction Stop).Source
$Executable = Join-Path $InstallDirectory "ssh-client-relay.exe"
$ConfigFile = Join-Path $ConfigDirectory "config.windows"
$RemoteTemporary = "$RemoteHelper.new.$PID.$([Guid]::NewGuid().ToString('N'))"

function Test-SafeRemotePath([string] $Path) {
    if ([string]::IsNullOrEmpty($Path) -or $Path.StartsWith("/") -or
        $Path.EndsWith("/") -or $Path.Contains("//") -or
        $Path -notmatch '^[A-Za-z0-9._/-]+$') {
        return $false
    }
    foreach ($Part in $Path.Split('/')) {
        if ($Part -eq "" -or $Part -eq "." -or $Part -eq "..") {
            return $false
        }
    }
    return $true
}

if (-not (Test-SafeRemotePath $RemoteHelper)) {
    throw "RemoteHelper must be a safe path relative to the relay home: $RemoteHelper"
}

$RemoteDirectory = Split-Path -Parent $RemoteHelper
if ([string]::IsNullOrEmpty($RemoteDirectory)) { $RemoteDirectory = "." }

New-Item -ItemType Directory -Force -Path $InstallDirectory, $ConfigDirectory |
    Out-Null

if (Test-Path -LiteralPath $Executable) {
    Remove-Item -LiteralPath $Executable -Force
}

Add-Type -Path (Join-Path $RepoDirectory "windows\SshClientRelay.cs") `
    -OutputAssembly $Executable -OutputType ConsoleApplication

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Configuration = @(
    "RELAY_HOST=$RelayHost"
    "TARGET_ALIAS=$TargetAlias"
    "TARGET_HOST=$TargetHost"
    "REMOTE_HELPER=~/$RemoteHelper"
    "SSH=$Ssh"
) -join "`n"
[IO.File]::WriteAllText($ConfigFile, "$Configuration`n", $Utf8NoBom)

& $Ssh -x -T $RelayHost `
    "mkdir -p ~/$RemoteDirectory && chmod 700 ~/$RemoteDirectory"
if ($LASTEXITCODE -ne 0) { throw "Could not prepare the relay directory" }

& $Scp -q (Join-Path $RepoDirectory "libexec\ssh-client-relay-helper") `
    "${RelayHost}:$RemoteTemporary"
if ($LASTEXITCODE -ne 0) { throw "Could not copy the relay helper" }

& $Ssh -x -T $RelayHost `
    "chmod 700 ~/$RemoteTemporary && mv -f ~/$RemoteTemporary ~/$RemoteHelper"
if ($LASTEXITCODE -ne 0) { throw "Could not install the relay helper" }

Write-Host "Installed Windows client: $Executable"
Write-Host "Installed relay helper: ${RelayHost}:~/$RemoteHelper"
Write-Host "Dispatch route: $TargetAlias -> $RelayHost -> $TargetHost"
