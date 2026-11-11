param(
    [string]$TargetDir = $PSScriptRoot,
    [switch]$Remove
)
$ErrorActionPreference = 'Stop'

function L([string]$s) { [regex]::Unescape($s) }

$launcher = Join-Path $TargetDir 'menu-launcher.exe'
$guiLauncher = Join-Path $TargetDir 'Converter.exe'

if (-not $Remove) {
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw (L '\u041D\u0435 \u043D\u0430\u0439\u0434\u0435\u043D menu-launcher.exe \u0432: ') + $TargetDir
    }
}

$categories = @(
    @{kind='image'; extensions=@('png','jpg','jpeg','bmp','webp','tif','tiff','gif','avif','heic','ico','tga','pcx','ppm','pgm','pbm','psd'); formats=@('png','jpg','webp','bmp','tiff','gif','avif','ico','tga','pcx','ppm')},
    @{kind='audio'; extensions=@('mp3','wav','flac','m4a','ogg','opus','aac','wma','aiff','ac3'); formats=@('mp3','wav','flac','m4a','ogg','opus','aac','wma','aiff','ac3')},
    @{kind='video'; extensions=@('mp4','mkv','mov','avi','webm','wmv','m4v','mpeg'); formats=@('mp4','mkv','webm','mov','avi','wmv')},
    @{kind='pdf'; extensions=@('pdf'); formats=@('docx','txt','zip')},
    @{kind='word'; extensions=@('doc','docx','rtf','odt','txt','html','htm'); formats=@('pdf','docx','odt','rtf','txt','html','epub')},
    @{kind='excel'; extensions=@('xls','xlsx','ods','csv'); formats=@('pdf','xlsx','ods','csv')},
    @{kind='powerpoint'; extensions=@('ppt','pptx','odp'); formats=@('pdf','pptx','odp')},
    @{kind='archive'; extensions=@('zip','7z','rar','tar','cab','iso','wim'); formats=@('zip','7z','tar')}
)

$hasGui = Test-Path -LiteralPath $guiLauncher -PathType Leaf

foreach ($category in $categories) {
    foreach ($extension in $category.extensions) {
        $parentPath = "Software\Classes\SystemFileAssociations\.$extension\shell"
        $parent = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($parentPath)
        try {
            foreach ($sub in $parent.GetSubKeyNames()) {
                if ($sub -like '*FileConverter*' -or $sub -like '*ConvertFormats*') {
                    $parent.DeleteSubKeyTree($sub, $false)
                }
            }
            if ($Remove) { continue }

            # 1. Cascading submenu: "Конвертировать в"
            $top = $parent.CreateSubKey('FileConvertFormats')
            try {
                $top.SetValue('MUIVerb', (L '\u041A\u043E\u043D\u0432\u0435\u0440\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u0432'))
                $top.SetValue('Icon', 'imageres.dll,-102')
                $top.SetValue('MultiSelectModel', 'Single')
                $top.SetValue('SubCommands', '')
                $shell = $top.CreateSubKey('shell')
                try {
                    $index = 0
                    foreach ($format in $category.formats) {
                        if ($format -eq $extension) { continue }
                        $index++
                        $verb = $shell.CreateSubKey(('{0:D2}' -f $index))
                        try {
                            $label = (L '\u0412 ') + $format.ToUpperInvariant()
                            if ($category.kind -eq 'pdf') {
                                if ($format -eq 'docx') { $label += (L ' (\u0442\u0435\u043A\u0441\u0442)') }
                                if ($format -eq 'zip') { $label += (L ' (\u0441\u0442\u0440\u0430\u043D\u0438\u0446\u044B PNG)') }
                            }
                            $verb.SetValue('MUIVerb', $label)
                            $command = $verb.CreateSubKey('command')
                            try {
                                $value = '"' + $launcher + '" ' + $category.kind + ' ' + $format + ' "%1"'
                                $command.SetValue('', $value)
                            } finally { $command.Dispose() }
                        } finally { $verb.Dispose() }
                    }
                    if ($hasGui) {
                        $verbGui = $shell.CreateSubKey('99_gui')
                        try {
                            $verbGui.SetValue('MUIVerb', (L '\u0414\u0440\u0443\u0433\u043E\u0439 \u0444\u043E\u0440\u043C\u0430\u0442 \u0438 \u043D\u0430\u0441\u0442\u0440\u043E\u0439\u043A\u0438\u2026'))
                            $verbGui.SetValue('Icon', 'imageres.dll,-102')
                            $commandGui = $verbGui.CreateSubKey('command')
                            try {
                                $commandGui.SetValue('', ('"' + $guiLauncher + '" "%1"'))
                            } finally { $commandGui.Dispose() }
                        } finally { $verbGui.Dispose() }
                    }
                } finally { $shell.Dispose() }
            } finally { $top.Dispose() }

            # 2. Main GUI entry: "Конвертировать..." (multi-select supported)
            if ($hasGui) {
                $mainVerb = $parent.CreateSubKey('FileConverter')
                try {
                    $mainVerb.SetValue('MUIVerb', (L '\u041A\u043E\u043D\u0432\u0435\u0440\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C\u2026'))
                    $mainVerb.SetValue('Icon', 'imageres.dll,-102')
                    $mainVerb.SetValue('MultiSelectModel', 'Player')
                    $mainCmd = $mainVerb.CreateSubKey('command')
                    try {
                        $mainCmd.SetValue('', ('"' + $guiLauncher + '" "%1"'))
                    } finally { $mainCmd.Dispose() }
                } finally { $mainVerb.Dispose() }
            }

        } finally { $parent.Dispose() }
    }
}

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ConverterShellNotify {
    [DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);
}
"@
[ConverterShellNotify]::SHChangeNotify(0x08000000, 0x1000, [IntPtr]::Zero, [IntPtr]::Zero)

if ($Remove) {
    L '\u041A\u043E\u043C\u0430\u043D\u0434\u044B \u0443\u0434\u0430\u043B\u0435\u043D\u044B \u0438\u0437 \u043A\u043E\u043D\u0442\u0435\u043A\u0441\u0442\u043D\u043E\u0433\u043E \u043C\u0435\u043D\u044E.'
} else {
    L '\u041A\u043E\u043D\u0442\u0435\u043A\u0441\u0442\u043D\u043E\u0435 \u043C\u0435\u043D\u044E \u0443\u0441\u043F\u0435\u0448\u043D\u043E \u043D\u0430\u0441\u0442\u0440\u043E\u0435\u043D\u043E.'
}
