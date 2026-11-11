<#
.SYNOPSIS
    Проверка и загрузка необходимых компонентов для Конвертера файлов (7-Zip, FFmpeg, ImageMagick, LibreOffice).
#>
param(
    [string]$ComponentsDir = (Join-Path $PSScriptRoot "components")
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}
function Write-Ok([string]$msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}
function Write-Warn([string]$msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

[void][IO.Directory]::CreateDirectory($ComponentsDir)

# 1. 7-Zip
$7zDir = Join-Path $ComponentsDir "7zip"
$7zExe = Join-Path $7zDir "7z.exe"
if (Test-Path $7zExe) {
    Write-Ok "7-Zip обнаружен: $7zExe"
} else {
    Write-Step "Загрузка 7-Zip..."
    [void][IO.Directory]::CreateDirectory($7zDir)
    $tmp7z = Join-Path $env:TEMP "7z-installer.exe"
    Invoke-WebRequest -Uri "https://www.7-zip.org/a/7z2301-x64.exe" -OutFile $tmp7z
    Start-Process -FilePath $tmp7z -ArgumentList "/S /D=$7zDir" -Wait
    Remove-Item $tmp7z -Force -ErrorAction SilentlyContinue
    if (Test-Path $7zExe) { Write-Ok "7-Zip успешно установлен в $7zDir" }
}

# 2. FFmpeg
$ffmpegDir = Join-Path $ComponentsDir "ffmpeg"
$ffmpegExe = Join-Path $ffmpegDir "ffmpeg.exe"
if (Test-Path $ffmpegExe) {
    Write-Ok "FFmpeg обнаружен: $ffmpegExe"
} else {
    Write-Step "Загрузка FFmpeg (essentials)..."
    [void][IO.Directory]::CreateDirectory($ffmpegDir)
    $tmpZip = Join-Path $env:TEMP "ffmpeg.zip"
    $ffmpegUrl = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip"
    Invoke-WebRequest -Uri $ffmpegUrl -OutFile $tmpZip
    Expand-Archive -Path $tmpZip -DestinationPath (Join-Path $env:TEMP "ffmpeg_extract") -Force
    $binDir = (Get-ChildItem -Path (Join-Path $env:TEMP "ffmpeg_extract") -Recurse -Filter "ffmpeg.exe").DirectoryName
    Copy-Item (Join-Path $binDir "ffmpeg.exe") $ffmpegDir -Force
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $env:TEMP "ffmpeg_extract") -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $ffmpegExe) { Write-Ok "FFmpeg успешно установлен в $ffmpegDir" }
}

# 3. ImageMagick
$imDir = Join-Path $ComponentsDir "imagemagick"
$imExe = Join-Path $imDir "magick.exe"
if (Test-Path $imExe) {
    Write-Ok "ImageMagick обнаружен: $imExe"
} else {
    Write-Step "Загрузка ImageMagick (portable)..."
    [void][IO.Directory]::CreateDirectory($imDir)
    $tmpZip = Join-Path $env:TEMP "magick.zip"
    $imUrl = "https://imagemagick.org/archive/binaries/ImageMagick-7.1.1-43-portable-Q16-x64.zip"
    Invoke-WebRequest -Uri $imUrl -OutFile $tmpZip
    Expand-Archive -Path $tmpZip -DestinationPath $imDir -Force
    Remove-Item $tmpZip -Force -ErrorAction SilentlyContinue
    if (Test-Path $imExe) { Write-Ok "ImageMagick успешно установлен в $imDir" }
}

# 4. LibreOffice
$loDir = Join-Path $ComponentsDir "libreoffice"
$loExe = Join-Path $loDir "program\soffice.com"
if (Test-Path $loExe) {
    Write-Ok "LibreOffice обнаружен: $loExe"
} else {
    Write-Warn "LibreOffice не обнаружен по пути: $loExe"
    Write-Host "Для офисных документов и PDF скопируйте установленный LibreOffice в папку components\libreoffice." -ForegroundColor Gray
}

Write-Host ""
Write-Ok "Проверка компонентов завершена!"

