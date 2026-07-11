param(
    [Parameter(Mandatory = $true, Position = 0)] [string] $RelayHost,
    [Parameter(Mandatory = $true, Position = 1)] [string] $TargetAlias,
    [Parameter(Mandatory = $true, Position = 2)] [string] $TargetHost,
    [string] $InstallDirectory = "$env:USERPROFILE\bin",
    [string] $ConfigDirectory = "$env:USERPROFILE\.config\ssh-client-relay",
    [string] $RemoteHelper = ".local/bin/ssh-client-relay-helper",
    [ValidateRange(0, 3600)] [int] $WaitForExitSeconds = 30
)

$ErrorActionPreference = "Stop"
$RepoDirectory = $PSScriptRoot
$Ssh = (Get-Command ssh.exe -ErrorAction Stop).Source
$Scp = (Get-Command scp.exe -ErrorAction Stop).Source
$Executable = Join-Path $InstallDirectory "ssh-client-relay.exe"
$StagedExecutable = Join-Path $InstallDirectory "ssh-client-relay.new.$PID.exe"
$ConfigFile = Join-Path $ConfigDirectory "config.windows"
$RemoteTemporary = "$RemoteHelper.new.$PID.$([Guid]::NewGuid().ToString('N'))"

New-Item -ItemType Directory -Force -Path $InstallDirectory, $ConfigDirectory |
    Out-Null

Add-Type -Path (Join-Path $RepoDirectory "windows\SshClientRelay.cs") `
    -OutputAssembly $StagedExecutable -OutputType ConsoleApplication

$VersionOutput = & $StagedExecutable --version
if ($LASTEXITCODE -ne 0 -or $VersionOutput -notmatch '^ssh-client-relay [0-9]+\.[0-9]+\.[0-9]+$') {
    throw "The staged Windows executable failed validation: $VersionOutput"
}

. (Join-Path $RepoDirectory "windows\InstallExecutable.ps1")
Install-RelayExecutable -StagedPath $StagedExecutable `
    -DestinationPath $Executable -WaitForExitSeconds $WaitForExitSeconds

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$Configuration = @(
    "RELAY_HOST=$RelayHost"
    "TARGET_ALIAS=$TargetAlias"
    "TARGET_HOST=$TargetHost"
    "REMOTE_HELPER=~/$RemoteHelper"
    "SSH=$Ssh"
) -join "`n"
[IO.File]::WriteAllText($ConfigFile, "$Configuration`n", $Utf8NoBom)

& $Ssh -x -T $RelayHost "mkdir -p ~/.local/bin && chmod 700 ~/.local/bin"
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
