param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string]$Kind,
    [Parameter(Mandatory=$true)][string]$Format,
    [string]$Quality = 'standard'
)
$ErrorActionPreference = 'Stop'
function L([string]$s) { [regex]::Unescape($s) }
$sourcePath = (Resolve-Path -LiteralPath $Source).ProviderPath
$targetPath = [IO.Path]::GetFullPath($Destination)
if ([string]::Equals($sourcePath, $targetPath, [StringComparison]::OrdinalIgnoreCase)) { throw (L '\u0418\u0441\u0445\u043E\u0434\u043D\u044B\u0439 \u0444\u0430\u0439\u043B \u0441\u043E\u0432\u043F\u0430\u0434\u0430\u0435\u0442 \u0441 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u043E\u043C.') }
if ([IO.File]::Exists($targetPath)) { throw (L '\u0424\u0430\u0439\u043B \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430 \u0443\u0436\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442.') }
$folder = [IO.Path]::GetDirectoryName($targetPath)
if (-not [IO.Directory]::Exists($folder)) { throw (L '\u041F\u0430\u043F\u043A\u0430 \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0438\u044F \u043D\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442.') }
$tempOutput = Join-Path $folder ('.convert-' + [guid]::NewGuid().ToString('N') + '.' + $Format)
$tempFolder = $null
try {
    if ($Kind -eq 'pdf') {
        if ($Format -notin @('txt','docx','zip')) { throw (L '\u042D\u0442\u043E\u0442 \u0444\u043E\u0440\u043C\u0430\u0442 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430 \u0434\u043B\u044F PDF \u043D\u0435 \u043F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u0442\u0441\u044F.') }
        $pdfium = Join-Path $PSScriptRoot 'components\libreoffice\program\pdfiumlo.dll'
        if (-not ('ConverterPdf' -as [type])) {
            Add-Type -Path (Join-Path $PSScriptRoot 'pdf-support.cs') -ReferencedAssemblies 'System.Drawing','System.IO.Compression'
        }
        if ($Format -eq 'docx') {
            $tempFolder = Join-Path ([IO.Path]::GetTempPath()) ('converter-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($tempFolder)
            $textPath = Join-Path $tempFolder 'document.txt'
            [ConverterPdf]::Convert($pdfium, $sourcePath, $textPath, $false)
            & $PSCommandPath -Source $textPath -Destination $tempOutput -Kind word -Format docx | Out-Null
        } else {
            [ConverterPdf]::Convert($pdfium, $sourcePath, $tempOutput, ($Format -eq 'zip'))
        }
    } elseif ($Kind -eq 'image') {
        $magick = Join-Path $PSScriptRoot 'components\imagemagick\magick.exe'
        if (-not (Test-Path -LiteralPath $magick)) { throw (L '\u041A\u043E\u043C\u043F\u043E\u043D\u0435\u043D\u0442 ImageMagick \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D \u0432 \u043F\u0430\u043F\u043A\u0435 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F.') }
        $imageQuality = @{high='95'; standard='80'; small='55'}[$Quality]
        if (-not $imageQuality) { $imageQuality = '80' }
        $sourceExt = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        $frameSelector = if ($sourceExt -eq '.ico') { '[-1]' } else { '[0]' }
        $nativeArgs = @(($sourcePath + $frameSelector),'-auto-orient','-quality',$imageQuality)
        if ($Format -in @('jpg','jpeg','bmp','pcx','ppm')) { $nativeArgs += @('-background','white','-alpha','remove','-alpha','off') }
        if ($Format -eq 'ico') { $nativeArgs += @('-resize','256x256>') }
        $nativeArgs += $tempOutput
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $log = (& $magick @nativeArgs 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        if ($exitCode -ne 0) { throw ((L 'ImageMagick \u043D\u0435 \u0441\u043C\u043E\u0433 \u043E\u0431\u0440\u0430\u0431\u043E\u0442\u0430\u0442\u044C \u0444\u0430\u0439\u043B. ') + $log) }
    } elseif ($Kind -in @('audio','video')) {
        $ffmpeg = Join-Path $PSScriptRoot 'components\ffmpeg\ffmpeg.exe'
        if (-not (Test-Path -LiteralPath $ffmpeg)) { throw (L '\u041A\u043E\u043C\u043F\u043E\u043D\u0435\u043D\u0442 FFmpeg \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D \u0432 \u043F\u0430\u043F\u043A\u0435 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F.') }
        $nativeArgs = @('-nostdin','-y','-hide_banner','-loglevel','error','-i',$sourcePath)
        if ($Kind -eq 'audio') {
            $nativeArgs += '-vn'
            if ($Format -in @('mp3','m4a','ogg','opus','aac','wma','ac3')) {
                $bitrate = @{high='256k'; standard='160k'; small='96k'}[$Quality]
                if (-not $bitrate) { $bitrate = '160k' }
                $nativeArgs += @('-b:a',$bitrate)
            }
        }
        if ($Kind -eq 'video') {
            $videoQuality = @{high='20'; standard='26'; small='32'}[$Quality]
            if (-not $videoQuality) { $videoQuality = '26' }
            if ($Format -eq 'webm') {
                $nativeArgs += @('-c:v','libvpx-vp9','-crf',$videoQuality,'-b:v','0','-c:a','libopus')
            } elseif ($Format -in @('mp4','mkv','mov')) {
                $nativeArgs += @('-vf','scale=trunc(iw/2)*2:trunc(ih/2)*2','-c:v','libx264','-pix_fmt','yuv420p','-crf',$videoQuality,'-c:a','aac')
            } elseif ($Format -in @('avi','wmv')) {
                $qscale = @{high='3'; standard='6'; small='10'}[$Quality]
                if (-not $qscale) { $qscale = '6' }
                $nativeArgs += @('-q:v',$qscale)
            }
        }
        $nativeArgs += $tempOutput
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $log = (& $ffmpeg @nativeArgs 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        if ($exitCode -ne 0) { throw ((L 'FFmpeg \u043D\u0435 \u0441\u043C\u043E\u0433 \u043E\u0431\u0440\u0430\u0431\u043E\u0442\u0430\u0442\u044C \u0444\u0430\u0439\u043B. ') + $log) }
    } elseif ($Kind -eq 'archive') {
        $sevenZip = Join-Path $PSScriptRoot 'components\7zip\7z.exe'
        if (-not (Test-Path -LiteralPath $sevenZip)) { throw (L '\u0414\u043B\u044F \u0430\u0440\u0445\u0438\u0432\u043E\u0432 \u043D\u0435\u043E\u0431\u0445\u043E\u0434\u0438\u043C \u0443\u0441\u0442\u0430\u043D\u043E\u0432\u043B\u0435\u043D\u043D\u044B\u0439 7-Zip.') }
        $tempFolder = Join-Path ([IO.Path]::GetTempPath()) ('converter-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($tempFolder)
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $log = (& $sevenZip x '-y' '-p' "-o$tempFolder" '--' $sourcePath 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        if ($exitCode -ne 0) { throw ((L '\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u0438\u0437\u0432\u043B\u0435\u0447\u044C \u0430\u0440\u0445\u0438\u0432. \u0412\u043E\u0437\u043C\u043E\u0436\u043D\u043E, \u043E\u043D \u043F\u043E\u0432\u0440\u0435\u0436\u0434\u0451\u043D \u0438\u043B\u0438 \u0437\u0430\u0449\u0438\u0449\u0451\u043D \u043F\u0430\u0440\u043E\u043B\u0435\u043C. ') + $log) }
        $oldLocation = Get-Location
        try {
            Set-Location -LiteralPath $tempFolder
            $archiveArgs = @('a', "-t$Format", '-y')
            if ($Format -eq 'zip') { $archiveArgs += '-mcu=on' }
            $archiveArgs += @('--', $tempOutput, '*')
            $oldPreference = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $log = (& $sevenZip @archiveArgs 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $oldPreference
        } finally { Set-Location -LiteralPath $oldLocation }
        if ($exitCode -ne 0) { throw ((L '\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u0441\u043E\u0437\u0434\u0430\u0442\u044C \u0430\u0440\u0445\u0438\u0432. ') + $log) }
    } elseif ($Kind -in @('word','excel','powerpoint')) {
        $office = Join-Path $PSScriptRoot 'components\libreoffice\program\soffice.com'
        if (-not (Test-Path -LiteralPath $office)) { throw (L '\u041A\u043E\u043C\u043F\u043E\u043D\u0435\u043D\u0442 LibreOffice \u043D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D \u0432 \u043F\u0430\u043F\u043A\u0435 \u043F\u0440\u0438\u043B\u043E\u0436\u0435\u043D\u0438\u044F.') }
        $tempFolder = Join-Path ([IO.Path]::GetTempPath()) ('converter-' + [guid]::NewGuid().ToString('N'))
        $profile = Join-Path $tempFolder 'profile'
        $converted = Join-Path $tempFolder 'converted'
        $staged = Join-Path $tempFolder 'staged'
        [void][IO.Directory]::CreateDirectory($profile)
        [void][IO.Directory]::CreateDirectory($converted)
        [void][IO.Directory]::CreateDirectory($staged)
        $inputPath = $sourcePath
        $sourceExt = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        if ($sourceExt -in @('.txt','.csv')) {
            $rawBytes = [IO.File]::ReadAllBytes($sourcePath)
            $hasUtf16Bom = ($rawBytes.Length -ge 2) -and (($rawBytes[0] -eq 0xFF -and $rawBytes[1] -eq 0xFE) -or ($rawBytes[0] -eq 0xFE -and $rawBytes[1] -eq 0xFF))
            if (-not $hasUtf16Bom) {
                $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
                try {
                    [void]$strictUtf8.GetString($rawBytes)
                } catch {
                    $cp1251Text = [Text.Encoding]::GetEncoding(1251).GetString($rawBytes)
                    $inputPath = Join-Path $staged ([IO.Path]::GetFileName($sourcePath))
                    [IO.File]::WriteAllText($inputPath, $cp1251Text, (New-Object System.Text.UTF8Encoding($true)))
                }
            }
        }
        $profileUri = ([Uri]$profile).AbsoluteUri
        $officeArgs = @("-env:UserInstallation=$profileUri", '--headless')
        if ($Kind -eq 'word' -and $sourceExt -in @('.html','.htm')) {
            $officeArgs += '--infilter=HTML (StarWriter)'
        } elseif ($Kind -eq 'excel' -and $sourceExt -eq '.csv') {
            $officeArgs += '--infilter=Text - txt - csv (StarCalc):44/59/9,34,76,1'
        }
        $officeArgs += @('--convert-to', $Format, '--outdir', $converted, $inputPath)
        $oldPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $log = (& $office @officeArgs 2>&1 | ForEach-Object { "$_" }) -join [Environment]::NewLine
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $oldPreference
        $officeOutput = Join-Path $converted ([IO.Path]::GetFileNameWithoutExtension($inputPath) + '.' + $Format)
        if ($exitCode -ne 0 -or -not [IO.File]::Exists($officeOutput)) { throw ((L 'LibreOffice \u043D\u0435 \u0441\u043C\u043E\u0433 \u043F\u0440\u0435\u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u0442\u044C \u0444\u0430\u0439\u043B. ') + $log) }
        if ($Format -eq 'csv') {
            $outBytes = [IO.File]::ReadAllBytes($officeOutput)
            $hasUtf8Bom = ($outBytes.Length -ge 3) -and ($outBytes[0] -eq 0xEF -and $outBytes[1] -eq 0xBB -and $outBytes[2] -eq 0xBF)
            if (-not $hasUtf8Bom) {
                $withBom = New-Object byte[] ($outBytes.Length + 3)
                $withBom[0] = 0xEF; $withBom[1] = 0xBB; $withBom[2] = 0xBF
                [Array]::Copy($outBytes, 0, $withBom, 3, $outBytes.Length)
                [IO.File]::WriteAllBytes($officeOutput, $withBom)
            }
        }
        [IO.File]::Move($officeOutput,$tempOutput)
    } else { throw (L '\u0422\u0438\u043F \u0444\u0430\u0439\u043B\u0430 \u043D\u0435 \u043F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u0442\u0441\u044F.') }
    if (-not [IO.File]::Exists($tempOutput)) { throw (L '\u041F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0430 \u043D\u0435 \u0441\u043E\u0437\u0434\u0430\u043B\u0430 \u0444\u0430\u0439\u043B \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430.') }
    [IO.File]::Move($tempOutput,$targetPath)
    Write-Output $targetPath
} finally {
    if ([IO.File]::Exists($tempOutput)) {
        try {
            [IO.File]::SetAttributes($tempOutput, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($tempOutput)
        } catch {}
    }
    if ($tempFolder -and [IO.Directory]::Exists($tempFolder)) {
        try {
            Get-ChildItem -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { $_.Attributes = [IO.FileAttributes]::Normal } catch {}
            }
            [IO.Directory]::Delete($tempFolder,$true)
        } catch {
            Remove-Item -LiteralPath $tempFolder -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
