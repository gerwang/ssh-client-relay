$ErrorActionPreference = "Stop"
$Repo = Split-Path -Parent $PSScriptRoot
$Work = Join-Path ([IO.Path]::GetTempPath()) ("ssh-client-relay-test-" + [Guid]::NewGuid())
New-Item -ItemType Directory -Path $Work | Out-Null

try {
    $Relay = Join-Path $Work "ssh-client-relay.exe"
    $FakeSsh = Join-Path $Work "fake-ssh.exe"
    Add-Type -Path (Join-Path $Repo "windows\SshClientRelay.cs") `
        -OutputAssembly $Relay -OutputType ConsoleApplication
    Add-Type -Path (Join-Path $Repo "tests\FakeSsh.cs") `
        -OutputAssembly $FakeSsh -OutputType ConsoleApplication

    $Config = Join-Path $Work "config.windows"
    @"
RELAY_HOST=relay.example
TARGET_ALIAS=compute
TARGET_HOST=compute.example.org
REMOTE_HELPER=~/.local/bin/ssh-client-relay-helper
SSH=$FakeSsh
"@ | Set-Content -LiteralPath $Config -Encoding ASCII
    $env:SSH_CLIENT_RELAY_CONFIG = $Config
    $env:TEST_ARGS = Join-Path $Work "args.bin"
    $env:TEST_STDIN = Join-Path $Work "stdin.bin"

    $Version = & $Relay --version
    if ($Version -ne "ssh-client-relay 0.1.0") { throw "version mismatch: $Version" }

    $Direct = "payload" | & $Relay other "arg with space"
    if ($Direct -ne "fake-ssh-output") { throw "direct output mismatch" }
    $Args = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($env:TEST_ARGS)).TrimEnd("`0").Split("`0")
    if (($Args -join "|") -ne "other|arg with space") { throw "direct argv mismatch" }

    $RelayOutput = "payload" | & $Relay -T -D 1080 compute "printf hello"
    if ($RelayOutput -ne "fake-ssh-output") { throw "relay output mismatch" }
    $Args = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($env:TEST_ARGS)).TrimEnd("`0").Split("`0")
    $ExpectedOuter = "-x|-T|-L|1080:127.0.0.1:1080|relay.example|~/.local/bin/ssh-client-relay-helper"
    if (($Args -join "|") -ne $ExpectedOuter) { throw "outer argv mismatch: $($Args -join '|')" }

    [byte[]]$Data = [IO.File]::ReadAllBytes($env:TEST_STDIN)
    $Offset = 0
    if ($Data.Length -ge 3 -and $Data[0] -eq 0xEF -and $Data[1] -eq 0xBB -and $Data[2] -eq 0xBF) { $Offset = 3 }
    $Fields = New-Object Collections.Generic.List[string]
    for ($i = 0; $i -lt 7; $i++) {
        $End = [Array]::IndexOf($Data, [byte]0, $Offset)
        if ($End -lt 0) { throw "missing framed field $i" }
        $Fields.Add([Text.Encoding]::UTF8.GetString($Data, $Offset, $End - $Offset))
        $Offset = $End + 1
    }
    $ExpectedFields = @("SSH_CLIENT_RELAY_ARGS_V1", "5", "-T", "-D", "1080", "compute.example.org", "printf hello")
    if (($Fields -join "|") -ne ($ExpectedFields -join "|")) { throw "frame mismatch: $($Fields -join '|')" }
    $Payload = [Text.Encoding]::UTF8.GetString($Data, $Offset, $Data.Length - $Offset).TrimEnd("`r", "`n")
    if ($Payload -ne "payload") { throw "payload mismatch: $Payload" }

    "x" | & $Relay -D1081 compute true | Out-Null
    $Args = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($env:TEST_ARGS)).TrimEnd("`0").Split("`0")
    if ($Args -notcontains "1081:127.0.0.1:1081") { throw "attached -D was not bridged" }

    . (Join-Path $Repo "windows\InstallExecutable.ps1")
    $Installed = Join-Path $Work "installed.exe"
    $Staged = Join-Path $Work "staged.exe"
    [IO.File]::WriteAllText($Installed, "old")
    [IO.File]::WriteAllText($Staged, "new")
    $Lock = [IO.File]::Open($Installed, [IO.FileMode]::Open,
        [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $FailedForLock = $false
        try {
            Install-RelayExecutable -StagedPath $Staged `
                -DestinationPath $Installed -WaitForExitSeconds 0
        }
        catch [IO.IOException] {
            $FailedForLock = $true
        }
        if (-not $FailedForLock) { throw "locked replacement unexpectedly succeeded" }
        if ([IO.File]::ReadAllText($Staged) -ne "new") { throw "staged file was not preserved" }
    }
    finally {
        $Lock.Dispose()
    }
    Install-RelayExecutable -StagedPath $Staged `
        -DestinationPath $Installed -WaitForExitSeconds 0
    if ([IO.File]::ReadAllText($Installed) -ne "new") { throw "atomic replacement failed" }

    Write-Host "Windows tests passed"
}
finally {
    Remove-Item -LiteralPath $Work -Recurse -Force -ErrorAction SilentlyContinue
}
