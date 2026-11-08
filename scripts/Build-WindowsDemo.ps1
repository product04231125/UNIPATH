#requires -Version 5.1
param(
    [string]$Flutter = 'flutter',
    [string]$SourceApiContainer = 'unipath-api-1',
    [string]$OutputDirectory,
    [switch]$ReuseWeb
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$template = Join-Path $root 'deploy/windows-demo'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'output/windows-demo' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Use a new output directory. Existing packages are never overwritten.' }
$bundle = Join-Path $output 'bundle'
New-Item -ItemType Directory -Force -Path $bundle | Out-Null

function Invoke-Checked {
    param([string]$Program, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Arguments)
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $Program @Arguments 2>&1 | ForEach-Object { Write-Output $_.ToString() }
        $nativeExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previous }
    if ($nativeExit -ne 0) { throw "$Program failed (exit $nativeExit)" }
}
Push-Location $root
try {
    $commit = (& git rev-parse --short HEAD).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot identify package source commit.' }
    $suffix = (Get-Date -Format 'yyyyMMddHHmmss')
    $apiImage = "unipath-demo-api:${commit}-${suffix}"
    $webImage = "unipath-demo-web:${commit}-${suffix}"
    $dbImage = 'pgvector/pgvector:0.8.6-pg17-bookworm@sha256:cf134a767f474095eeba57e0117be8e568e011a63f33fbf252f14c9b760f8e6f'
    Write-Output 'Exporting only selected school criteria, courses and requirement checks. Source DB is read-only.'
    Invoke-Checked docker cp (Join-Path $root 'backend/app/operations/demo_bundle.py') "${SourceApiContainer}:/tmp/unipath-demo-export.py"
    Invoke-Checked docker exec -e PYTHONPATH=/app $SourceApiContainer python /tmp/unipath-demo-export.py export --file /tmp/unipath-demo-data.json
    Invoke-Checked docker cp "${SourceApiContainer}:/tmp/unipath-demo-data.json" (Join-Path $bundle 'demo-data.json')
    if (-not $ReuseWeb) {
        Push-Location (Join-Path $root 'frontend')
        try {
            Invoke-Checked $Flutter pub get --offline
            Invoke-Checked $Flutter build web --release --no-pub --dart-define=API_BASE_URL=http://localhost:38100
        } finally { Pop-Location }
    }
    $web = Join-Path $root 'frontend/build/web'
    if (-not (Test-Path -LiteralPath (Join-Path $web 'main.dart.js'))) { throw 'Missing frontend web build.' }
    $webContext = Join-Path $output 'web-context'
    New-Item -ItemType Directory -Force $webContext | Out-Null
    Copy-Item -LiteralPath $web -Destination (Join-Path $webContext 'web') -Recurse
    Copy-Item -LiteralPath (Join-Path $template 'nginx.conf') -Destination $webContext
    Copy-Item -LiteralPath (Join-Path $template 'web.Dockerfile') -Destination (Join-Path $webContext 'Dockerfile')
    Invoke-Checked docker build --pull=false --target runtime -t $apiImage -f backend/Dockerfile .
    Invoke-Checked docker build --pull=false -t $webImage $webContext
    Invoke-Checked docker image inspect $dbImage --format '{{.Id}}'
    Write-Output 'Saving images for offline application startup...'
    Invoke-Checked docker save --output (Join-Path $bundle 'images.tar') $apiImage $webImage $dbImage
    foreach ($name in @('Setup.ps1','Enable-Wsl.ps1','compose.yaml','README.txt')) {
        Copy-Item -LiteralPath (Join-Path $template $name) -Destination $bundle
    }
    $files = @{}
    foreach ($file in Get-ChildItem -LiteralPath $bundle -File) {
        $files[$file.Name] = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    }
    $manifest = @{format=1;source_commit=$commit;api_image=$apiImage;web_image=$webImage;db_image=$dbImage;files=$files}
    [IO.File]::WriteAllText((Join-Path $bundle 'manifest.json'),($manifest | ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $output 'demo-bundle.zip'
    [IO.Compression.ZipFile]::CreateFromDirectory($bundle,$zip,[IO.Compression.CompressionLevel]::Optimal,$false)
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is required to create the launcher EXE.' }
    $exe = Join-Path $output 'UniversityPath-Demo-Setup.exe'
    Invoke-Checked $compiler /nologo /target:winexe /platform:x64 "/out:$exe" "/resource:$zip,DemoBundle" /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll (Join-Path $template 'Launcher.cs')
    $checksum = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash.ToLowerInvariant()
    Set-Content -LiteralPath (Join-Path $output 'UniversityPath-Demo-Setup.sha256') -Value "$checksum  UniversityPath-Demo-Setup.exe" -Encoding ascii
    Write-Output "PACKAGE_READY: $exe"
    Write-Output 'The standalone EXE contains school data and the selected student records. Original credentials and sessions are excluded.'
} finally { Pop-Location }
