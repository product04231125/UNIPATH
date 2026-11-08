#requires -Version 5.1
param([switch]$Stop, [switch]$NoBrowser, [string]$StateDirectory)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$script:Docker = $null

function Invoke-Docker {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    & $script:Docker @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Docker failed (exit $LASTEXITCODE): $($Arguments[0])" }
}
function Find-Docker {
    $command = Get-Command docker.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe"
    )) { if (Test-Path -LiteralPath $candidate) { return $candidate } }
    return $null
}
function New-DemoPassword {
    $bytes = New-Object byte[] 24
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return ([BitConverter]::ToString($bytes)).Replace('-','').ToLowerInvariant()
}
function Test-DockerReady {
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & $script:Docker info --format '{{.OSType}}' 2>$null
        return $LASTEXITCODE -eq 0 -and $output -eq 'linux'
    } finally { $ErrorActionPreference = $previous }
}
function Test-Wsl {
    $output = (& wsl.exe --version 2>&1 | Out-String).Replace([string][char]0,'')
    if ($LASTEXITCODE -ne 0) { return $false }
    $match = [regex]::Match($output,'\d+\.\d+\.\d+')
    return $match.Success -and [version]$match.Value -ge [version]'2.1.5'
}
function Initialize-Docker {
    $script:Docker = Find-Docker
    if ($script:Docker -and (Test-DockerReady)) {
        Invoke-Docker compose version
        return
    }
    $os = Get-CimInstance Win32_OperatingSystem
    if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
        throw 'This demo package requires Windows x64. ARM64 needs a separate package.'
    }
    if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 19045) { throw 'Windows 10 22H2 / Windows 11 or newer is required.' }
    $computer = Get-CimInstance Win32_ComputerSystem
    if ($computer.TotalPhysicalMemory -lt 8GB) { throw 'Docker Desktop requires at least 8GB RAM.' }
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    if (-not $computer.HypervisorPresent -and -not $cpu.VirtualizationFirmwareEnabled) {
        throw 'Enable hardware virtualization in BIOS/UEFI before continuing.'
    }
    if (-not (Test-Wsl)) {
        Write-Output 'Preparing WSL2. Approve the Windows administrator prompt.'
        $helper = Join-Path $PSScriptRoot 'Enable-Wsl.ps1'
        $process = Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',('"' + $helper + '"')
        )
        if ($process.ExitCode -eq 3010) {
            Write-Output 'REBOOT_REQUIRED: Restart Windows, then run this installer again. No demo data was overwritten.'
            exit 3010
        }
        if ($process.ExitCode -ne 0 -or -not (Test-Wsl)) { throw 'WSL2 setup failed. Update Windows/WSL and run again.' }
    }
    $script:Docker = Find-Docker
    if (-not $script:Docker) {
        Write-Output 'Downloading Docker Desktop from docker.com. Internet access is required for first installation.'
        $installer = Join-Path $StateDirectory 'DockerDesktopInstaller.exe'
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe' -OutFile $installer -UseBasicParsing
        $signature = Get-AuthenticodeSignature -LiteralPath $installer
        if ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Docker') {
            throw 'Docker installer signature verification failed. Installation stopped.'
        }
        Write-Output 'Complete the Docker installation window. Docker terms must be accepted by you.'
        $installed = Start-Process -FilePath $installer -WindowStyle Normal -ArgumentList @('install','--user','--backend=wsl-2') -Wait -PassThru
        if ($installed.ExitCode -eq 3010) {
            Write-Output 'REBOOT_REQUIRED: Restart Windows, then run this installer again.'
            exit 3010
        }
        if ($installed.ExitCode -ne 0) { throw "Docker installation stopped (exit $($installed.ExitCode))." }
        $script:Docker = Find-Docker
        if (-not $script:Docker) { throw 'Docker installation is incomplete. Run Docker Desktop once, then retry.' }
    }
    if (-not (Test-DockerReady)) {
        $desktop = @("$env:LOCALAPPDATA\Programs\DockerDesktop\Docker Desktop.exe", "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe") |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($desktop) { Start-Process -FilePath $desktop -WindowStyle Normal }
        Write-Output 'Waiting for Docker Desktop Linux engine. Open Docker Desktop and accept its terms if prompted.'
        $deadline = (Get-Date).AddMinutes(3)
        while ((Get-Date) -lt $deadline -and -not (Test-DockerReady)) { Start-Sleep -Seconds 3 }
        if (-not (Test-DockerReady)) { throw 'Docker is not ready. Start Docker Desktop in Linux containers mode, then run again.' }
    }
    Invoke-Docker compose version
}

try {
    if (-not $StateDirectory) { $StateDirectory = Join-Path $env:LOCALAPPDATA 'UniversityPathDemo\state' }
    $StateDirectory = [IO.Path]::GetFullPath($StateDirectory)
    New-Item -ItemType Directory -Force -Path $StateDirectory | Out-Null
    $env:DEMO_STATE_DIR = $StateDirectory.Replace('\','/')
    $env:COMPOSE_PROJECT_NAME = 'unipath-demo'
    $envFile = Join-Path $StateDirectory 'demo.env'
    $composeFile = Join-Path $PSScriptRoot 'compose.yaml'
    if ($Stop) {
        $script:Docker = Find-Docker
        if (-not $script:Docker -or -not (Test-Path -LiteralPath $envFile)) { Write-Output 'Demo is not installed.'; exit 0 }
        Invoke-Docker compose --env-file $envFile -f $composeFile -p unipath-demo stop
        Write-Output 'Demo stopped. Saved records are preserved.'
        exit 0
    }
    Write-Output 'Checking package integrity...'
    $manifest = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') | ConvertFrom-Json
    if ($manifest.format -ne 1) { throw 'Unsupported demo package format.' }
    foreach ($file in $manifest.files.PSObject.Properties) {
        if ($file.Name -notmatch '^[a-zA-Z0-9_.-]+$') { throw 'Invalid package filename.' }
        $path = Join-Path $PSScriptRoot $file.Name
        if ((Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash.ToLowerInvariant() -ne $file.Value) { throw "Package damaged: $($file.Name)" }
    }
    Initialize-Docker
    if (-not (Test-Path -LiteralPath $envFile)) {
        $settings = @("POSTGRES_PASSWORD=$(New-DemoPassword)","API_IMAGE=$($manifest.api_image)","WEB_IMAGE=$($manifest.web_image)","DB_IMAGE=$($manifest.db_image)")
        [IO.File]::WriteAllLines($envFile,$settings,(New-Object Text.UTF8Encoding($false)))
    }
    $accountsFile = Join-Path $StateDirectory 'accounts.json'
    if (-not (Test-Path -LiteralPath $accountsFile)) {
        $accounts = @{student=(New-DemoPassword);admin=(New-DemoPassword)}
        [IO.File]::WriteAllText($accountsFile,($accounts | ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    }
    # Credentials stay in this machine's account directory, never in the distributable EXE.
    $accounts = Get-Content -Raw -LiteralPath $accountsFile | ConvertFrom-Json
    [IO.File]::WriteAllLines((Join-Path $StateDirectory 'Demo-Accounts.txt'),@(
        'UniversityPath Demo - http://localhost:38100',
        'Student: student@demo.example',"Password: $($accounts.student)",
        'Administrator: admin@demo.example',"Password: $($accounts.admin)"
    ),(New-Object Text.UTF8Encoding($false)))
    $loaded = Join-Path $StateDirectory 'loaded-images.txt'
    $fingerprint = $manifest.files.'images.tar'
    if (-not (Test-Path -LiteralPath $loaded) -or (Get-Content -Raw -LiteralPath $loaded).Trim() -ne $fingerprint) {
        Write-Output 'Loading bundled Docker images (no registry download)...'
        Invoke-Docker load --input (Join-Path $PSScriptRoot 'images.tar')
        Set-Content -LiteralPath $loaded -Value $fingerprint -Encoding ascii
    }
    $compose = @('compose','--env-file',$envFile,'-f',$composeFile,'-p','unipath-demo')
    Write-Output 'Starting the isolated demo database...'
    Invoke-Docker @compose up -d --wait db
    Write-Output 'Preparing schema and first-run data. Existing demo records are preserved.'
    Invoke-Docker @compose run --rm --no-deps prepare
    Invoke-Docker @compose up -d --wait api web
    $ready = Invoke-WebRequest 'http://localhost:38100/api/v1/health/ready' -UseBasicParsing -TimeoutSec 10
    if ($ready.StatusCode -ne 200) { throw 'Application health check failed.' }
    Write-Output 'READY: http://localhost:38100 - Use the launcher Accounts button to view demo logins.'
    if (-not $NoBrowser) { Start-Process 'http://localhost:38100' }
} catch {
    Write-Output "FAILED: $($_.Exception.Message)"
    exit 1
}
