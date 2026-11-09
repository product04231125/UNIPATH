#requires -Version 5.1
$ErrorActionPreference = 'Stop'
try {
    $restart = $false
    foreach ($name in @('Microsoft-Windows-Subsystem-Linux','VirtualMachinePlatform')) {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $name
        if ($feature.State -ne 'Enabled') {
            $enabled = Enable-WindowsOptionalFeature -Online -FeatureName $name -All -NoRestart
            $restart = $restart -or $enabled.RestartNeeded
        }
    }
    if ($restart) { exit 3010 }
    & wsl.exe --update
    if ($LASTEXITCODE -eq 3010) { exit 3010 }
    if ($LASTEXITCODE -ne 0) {
        & wsl.exe --install --no-distribution
        if ($LASTEXITCODE -ne 0) { exit 1 }
        exit 3010
    }
    & wsl.exe --set-default-version 2
    if ($LASTEXITCODE -ne 0) { exit 1 }
    exit 0
} catch { exit 1 }
