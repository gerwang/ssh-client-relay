function Install-RelayExecutable {
    param(
        [Parameter(Mandatory = $true)] [string] $StagedPath,
        [Parameter(Mandatory = $true)] [string] $DestinationPath,
        [ValidateRange(0, 3600)] [int] $WaitForExitSeconds = 30
    )

    $StagedPath = [IO.Path]::GetFullPath($StagedPath)
    $DestinationPath = [IO.Path]::GetFullPath($DestinationPath)
    $BackupPath = "$DestinationPath.previous"
    $Deadline = [DateTime]::UtcNow.AddSeconds($WaitForExitSeconds)

    if (-not (Test-Path -LiteralPath $StagedPath -PathType Leaf)) {
        throw "Staged executable does not exist: $StagedPath"
    }

    while ($true) {
        try {
            if (Test-Path -LiteralPath $DestinationPath -PathType Leaf) {
                Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
                [IO.File]::Replace($StagedPath, $DestinationPath, $BackupPath, $true)
                Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
            }
            else {
                [IO.File]::Move($StagedPath, $DestinationPath)
            }
            return
        }
        catch [System.IO.IOException], [System.UnauthorizedAccessException] {
            if ([DateTime]::UtcNow -ge $Deadline) {
                $Users = @()
                foreach ($Process in Get-Process -ErrorAction SilentlyContinue) {
                    try {
                        if ($Process.Path -and
                            [IO.Path]::GetFullPath($Process.Path) -eq $DestinationPath) {
                            $Users += "$($Process.ProcessName) (PID $($Process.Id))"
                        }
                    }
                    catch { }
                }
                $ProcessText = if ($Users.Count) {
                    " Locking processes: $($Users -join ',')."
                }
                else {
                    " The locking process could not be identified."
                }
                throw [IO.IOException]::new(
                    "The installed relay is still in use after $WaitForExitSeconds seconds." +
                    "$ProcessText Close active VS Code/SSH sessions and rerun the installer." +
                    " The validated update remains at: $StagedPath",
                    $_.Exception)
            }
            Start-Sleep -Seconds 1
        }
    }
}
