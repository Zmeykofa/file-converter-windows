Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function L([string]$s) { [regex]::Unescape($s) }

Add-Type -Name Win32Window -Namespace FileConverterApp -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
'@

$consoleHwnd = [FileConverterApp.Win32Window]::GetConsoleWindow()
if ($consoleHwnd -ne [IntPtr]::Zero) {
    [void][FileConverterApp.Win32Window]::ShowWindow($consoleHwnd, 0)
}

$inboxDir = Join-Path ([IO.Path]::GetTempPath()) 'FileConverter\inbox'
[void][IO.Directory]::CreateDirectory($inboxDir)
$createdNew = $false
$script:instanceMutex = New-Object System.Threading.Mutex($true, 'Local\FileConverter_SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    $payload = if ($args.Count -gt 0) { ($args -join [Environment]::NewLine) } else { '__ACTIVATE__' }
    $msgFile = Join-Path $inboxDir ([guid]::NewGuid().ToString('N') + '.txt')
    [IO.File]::WriteAllText($msgFile, $payload, (New-Object System.Text.UTF8Encoding($true)))
    $script:instanceMutex.Dispose()
    exit 0
}

Get-ChildItem -LiteralPath $inboxDir -Filter '*.txt' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.CreationTimeUtc -lt [DateTime]::UtcNow.AddSeconds(-10) } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }

$groups = @{
    '.png'='image'; '.jpg'='image'; '.jpeg'='image'; '.bmp'='image'; '.webp'='image'; '.tif'='image'; '.tiff'='image'; '.gif'='image'; '.avif'='image'; '.heic'='image'; '.ico'='image'; '.tga'='image'; '.pcx'='image'; '.ppm'='image'; '.pgm'='image'; '.pbm'='image'; '.psd'='image'
    '.mp3'='audio'; '.wav'='audio'; '.flac'='audio'; '.m4a'='audio'; '.ogg'='audio'; '.opus'='audio'; '.aac'='audio'; '.wma'='audio'; '.aiff'='audio'; '.ac3'='audio'
    '.mp4'='video'; '.mkv'='video'; '.mov'='video'; '.avi'='video'; '.webm'='video'; '.wmv'='video'; '.m4v'='video'; '.mpeg'='video'
    '.pdf'='pdf'
    '.doc'='word'; '.docx'='word'; '.rtf'='word'; '.odt'='word'; '.txt'='word'; '.html'='word'; '.htm'='word'
    '.xls'='excel'; '.xlsx'='excel'; '.ods'='excel'; '.csv'='excel'
    '.ppt'='powerpoint'; '.pptx'='powerpoint'; '.odp'='powerpoint'
    '.zip'='archive'; '.7z'='archive'; '.rar'='archive'; '.tar'='archive'; '.cab'='archive'; '.iso'='archive'; '.wim'='archive'
}
$formats = @{
    image=@('png','jpg','webp','bmp','tiff','gif','avif','ico','tga','pcx','ppm')
    audio=@('mp3','wav','flac','m4a','ogg','opus','aac','wma','aiff','ac3')
    video=@('mp4','mkv','webm','mov','avi','wmv')
    pdf=@('docx','txt','zip')
    word=@('pdf','docx','odt','rtf','txt','html','epub')
    excel=@('pdf','xlsx','ods','csv')
    powerpoint=@('pdf','pptx','odp')
    archive=@('zip','7z','tar')
}
$script:files = New-Object 'System.Collections.Generic.List[string]'
$script:queue = @()
$script:errors = New-Object 'System.Collections.Generic.List[string]'
$script:index = 0
$script:job = $null
$script:completed = 0
$script:chosenFormat = ''
$script:chosenQuality = 'standard'
$script:outputDirectory = ''
$script:shownOnce = $false
$worker = Join-Path $PSScriptRoot 'worker.ps1'

$form = New-Object Windows.Forms.Form
$form.Text = L '\u041A\u043E\u043D\u0432\u0435\u0440\u0442\u0435\u0440 \u0444\u0430\u0439\u043B\u043E\u0432'
$form.ClientSize = New-Object Drawing.Size(700,440)
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object Drawing.Size(716,479)
$form.AllowDrop = $true

$info = New-Object Windows.Forms.Label
$info.Text = L '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0444\u0430\u0439\u043B\u044B \u043E\u0434\u043D\u043E\u0433\u043E \u0442\u0438\u043F\u0430 \u0438\u043B\u0438 \u043F\u0435\u0440\u0435\u0442\u0430\u0449\u0438\u0442\u0435 \u0438\u0445 \u0441\u044E\u0434\u0430'
$info.SetBounds(16,12,470,24)
$form.Controls.Add($info)

$charity = New-Object Windows.Forms.LinkLabel
$charity.Text = L '\u2764 \u0424\u043E\u043D\u0434 \u00AB\u041F\u043E\u0434\u0430\u0440\u0438 \u0436\u0438\u0437\u043D\u044C\u00BB'
$charity.LinkColor = [Drawing.Color]::FromArgb(210, 50, 50)
$charity.ActiveLinkColor = [Drawing.Color]::FromArgb(170, 30, 30)
$charity.VisitedLinkColor = [Drawing.Color]::FromArgb(210, 50, 50)
$charity.SetBounds(490,12,190,24)
$charity.TextAlign = 'TopRight'
$charity.Anchor = 'Top,Right'
$charityTip = New-Object Windows.Forms.ToolTip
$charityTip.SetToolTip($charity, (L '\u041F\u0440\u043E\u0433\u0440\u0430\u043C\u043C\u0430 \u0431\u0435\u0441\u043F\u043B\u0430\u0442\u043D\u0430\u044F. \u0415\u0441\u043B\u0438 \u0445\u043E\u0442\u0438\u0442\u0435 \u043F\u043E\u0434\u0434\u0435\u0440\u0436\u0430\u0442\u044C \u2014 \u043F\u043E\u043C\u043E\u0433\u0438\u0442\u0435 \u0434\u0435\u0442\u044F\u043C \u0432 \u0444\u043E\u043D\u0434\u0435 \u00AB\u041F\u043E\u0434\u0430\u0440\u0438 \u0436\u0438\u0437\u043D\u044C\u00BB'))
$charity.Add_Click({
    try { [Diagnostics.Process]::Start('https://podari-zhizn.ru') } catch {}
})
$form.Controls.Add($charity)
$list = New-Object Windows.Forms.ListBox
$list.SetBounds(16,40,665,140)
$list.Anchor = 'Top,Bottom,Left,Right'
$list.HorizontalScrollbar = $true
$form.Controls.Add($list)
$browse = New-Object Windows.Forms.Button
$browse.Text = L '\u0412\u044B\u0431\u0440\u0430\u0442\u044C \u0444\u0430\u0439\u043B\u044B'
$browse.SetBounds(16,190,150,30)
$browse.Anchor = 'Bottom,Left'
$form.Controls.Add($browse)
$clear = New-Object Windows.Forms.Button
$clear.Text = L '\u041E\u0447\u0438\u0441\u0442\u0438\u0442\u044C'
$clear.SetBounds(176,190,100,30)
$clear.Anchor = 'Bottom,Left'
$form.Controls.Add($clear)
$formatLabel = New-Object Windows.Forms.Label
$formatLabel.Text = L '\u0424\u043E\u0440\u043C\u0430\u0442 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430'
$formatLabel.SetBounds(16,236,180,22)
$formatLabel.Anchor = 'Bottom,Left'
$form.Controls.Add($formatLabel)
$formatBox = New-Object Windows.Forms.ComboBox
$formatBox.DropDownStyle = 'DropDownList'
$formatBox.SetBounds(16,258,150,25)
$formatBox.Anchor = 'Bottom,Left'
$form.Controls.Add($formatBox)
$folderLabel = New-Object Windows.Forms.Label
$folderLabel.Text = L '\u041F\u0430\u043F\u043A\u0430 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0430'
$folderLabel.SetBounds(190,236,180,22)
$folderLabel.Anchor = 'Bottom,Left'
$form.Controls.Add($folderLabel)
$folderBox = New-Object Windows.Forms.TextBox
$folderBox.SetBounds(190,258,390,25)
$folderBox.ReadOnly = $true
$folderBox.Text = L '\u0420\u044F\u0434\u043E\u043C \u0441 \u0438\u0441\u0445\u043E\u0434\u043D\u044B\u043C\u0438 \u0444\u0430\u0439\u043B\u0430\u043C\u0438'
$folderBox.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($folderBox)
$folderButton = New-Object Windows.Forms.Button
$folderButton.Text = L '\u0412\u044B\u0431\u0440\u0430\u0442\u044C'
$folderButton.SetBounds(590,255,91,30)
$folderButton.Anchor = 'Bottom,Right'
$form.Controls.Add($folderButton)
$resetFolder = New-Object Windows.Forms.Button
$resetFolder.Text = L '\u0420\u044F\u0434\u043E\u043C \u0441 \u0438\u0441\u0445\u043E\u0434\u043D\u044B\u043C\u0438'
$resetFolder.SetBounds(470,292,170,27)
$resetFolder.Anchor = 'Bottom,Right'
$form.Controls.Add($resetFolder)
$qualityLabel = New-Object Windows.Forms.Label
$qualityLabel.Text = L '\u041A\u0430\u0447\u0435\u0441\u0442\u0432\u043E \u043C\u0435\u0434\u0438\u0430'
$qualityLabel.SetBounds(190,296,120,22)
$qualityLabel.Anchor = 'Bottom,Left'
$form.Controls.Add($qualityLabel)
$qualityBox = New-Object Windows.Forms.ComboBox
$qualityBox.DropDownStyle = 'DropDownList'
[void]$qualityBox.Items.AddRange(@((L '\u0412\u044B\u0441\u043E\u043A\u043E\u0435'),(L '\u041E\u0431\u044B\u0447\u043D\u043E\u0435'),(L '\u041C\u0435\u043D\u044C\u0448\u0438\u0439 \u0440\u0430\u0437\u043C\u0435\u0440')))
$qualityBox.SelectedIndex = 1
$qualityBox.SetBounds(310,293,150,25)
$qualityBox.Anchor = 'Bottom,Left'
$form.Controls.Add($qualityBox)
$start = New-Object Windows.Forms.Button
$start.Text = L '\u041A\u043E\u043D\u0432\u0435\u0440\u0442\u0438\u0440\u043E\u0432\u0430\u0442\u044C'
$start.SetBounds(16,300,160,35)
$start.Anchor = 'Bottom,Left'
$form.Controls.Add($start)
$progress = New-Object Windows.Forms.ProgressBar
$progress.SetBounds(16,350,665,18)
$progress.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($progress)
$status = New-Object Windows.Forms.Label
$status.SetBounds(16,378,665,48)
$status.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($status)

function Update-Formats {
    $previousFormat = [string]$formatBox.SelectedItem
    $formatBox.Items.Clear()
    if ($script:files.Count -eq 0) { $status.Text = L '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0444\u0430\u0439\u043B\u044B.'; return }
    $kinds = @($script:files | ForEach-Object { $groups[[IO.Path]::GetExtension($_).ToLowerInvariant()] } | Select-Object -Unique)
    if ($kinds.Count -ne 1 -or -not $kinds[0]) {
        $status.Text = L '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0444\u0430\u0439\u043B\u044B \u043E\u0434\u043D\u043E\u0439 \u043A\u0430\u0442\u0435\u0433\u043E\u0440\u0438\u0438: \u0438\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u044F, \u0430\u0443\u0434\u0438\u043E, \u0432\u0438\u0434\u0435\u043E, \u0434\u043E\u043A\u0443\u043C\u0435\u043D\u0442\u044B \u043E\u0434\u043D\u043E\u0433\u043E \u0442\u0438\u043F\u0430 \u0438\u043B\u0438 \u0430\u0440\u0445\u0438\u0432\u044B.'
        return
    }
    $primaryFormats = @()
    $secondaryFormats = @()
    foreach ($format in $formats[$kinds[0]]) {
        $same = @($script:files | Where-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() -eq ".$format" }).Count
        if ($same -eq 0) {
            $primaryFormats += $format
        } elseif ($same -lt $script:files.Count) {
            $secondaryFormats += $format
        }
    }
    foreach ($format in ($primaryFormats + $secondaryFormats)) {
        [void]$formatBox.Items.Add($format)
    }
    if ($formatBox.Items.Count -gt 0) {
        if ($previousFormat -and $formatBox.Items.Contains($previousFormat)) {
            $formatBox.SelectedItem = $previousFormat
        } else {
            $formatBox.SelectedIndex = 0
        }
    }
    $status.Text = (L '\u0412\u044B\u0431\u0440\u0430\u043D\u043E \u0444\u0430\u0439\u043B\u043E\u0432: ') + $script:files.Count
}
function Add-Files([string[]]$paths) {
    foreach ($path in $paths) {
        if (-not $path) { continue }
        $fullPath = try { [IO.Path]::GetFullPath($path) } catch { $path }
        $exists = [IO.File]::Exists($fullPath)
        $alreadyAdded = $false
        foreach ($existing in $script:files) {
            if ([string]::Equals($existing, $fullPath, [StringComparison]::OrdinalIgnoreCase)) {
                $alreadyAdded = $true
                break
            }
        }
        if ($exists -and -not $alreadyAdded) {
            $script:files.Add($fullPath)
            [void]$list.Items.Add($fullPath)
        }
    }
    Update-Formats
}
$list.Add_KeyDown({
    if ($_.KeyCode -eq 'Delete' -and $list.SelectedIndex -ge 0 -and -not $script:job) {
        $idx = $list.SelectedIndex
        $script:files.RemoveAt($idx)
        $list.Items.RemoveAt($idx)
        if ($list.Items.Count -gt 0) {
            $list.SelectedIndex = [Math]::Min($idx, $list.Items.Count - 1)
        }
        Update-Formats
    }
})
$browse.Add_Click({
    $dialog = New-Object Windows.Forms.OpenFileDialog
    $dialog.Multiselect = $true
    $dialog.Filter = L '\u0412\u0441\u0435 \u043F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0435\u043C\u044B\u0435 \u0444\u0430\u0439\u043B\u044B|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff;*.gif;*.avif;*.heic;*.ico;*.tga;*.pcx;*.ppm;*.pgm;*.pbm;*.psd;*.mp3;*.wav;*.flac;*.m4a;*.ogg;*.opus;*.aac;*.wma;*.aiff;*.ac3;*.mp4;*.mkv;*.mov;*.avi;*.webm;*.wmv;*.m4v;*.mpeg;*.pdf;*.doc;*.docx;*.rtf;*.odt;*.txt;*.html;*.htm;*.xls;*.xlsx;*.ods;*.csv;*.ppt;*.pptx;*.odp;*.zip;*.7z;*.rar;*.tar;*.cab;*.iso;*.wim|\u0418\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u044F|*.png;*.jpg;*.jpeg;*.bmp;*.webp;*.tif;*.tiff;*.gif;*.avif;*.heic;*.ico;*.tga;*.pcx;*.ppm;*.pgm;*.pbm;*.psd|\u0410\u0443\u0434\u0438\u043E|*.mp3;*.wav;*.flac;*.m4a;*.ogg;*.opus;*.aac;*.wma;*.aiff;*.ac3|\u0412\u0438\u0434\u0435\u043E|*.mp4;*.mkv;*.mov;*.avi;*.webm;*.wmv;*.m4v;*.mpeg|PDF (*.pdf)|*.pdf|\u0414\u043E\u043A\u0443\u043C\u0435\u043D\u0442\u044B|*.doc;*.docx;*.rtf;*.odt;*.txt;*.html;*.htm|\u0422\u0430\u0431\u043B\u0438\u0446\u044B|*.xls;*.xlsx;*.ods;*.csv|\u041F\u0440\u0435\u0437\u0435\u043D\u0442\u0430\u0446\u0438\u0438|*.ppt;*.pptx;*.odp|\u0410\u0440\u0445\u0438\u0432\u044B|*.zip;*.7z;*.rar;*.tar;*.cab;*.iso;*.wim|\u0412\u0441\u0435 \u0444\u0430\u0439\u043B\u044B (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { Add-Files $dialog.FileNames }
    $dialog.Dispose()
})
$clear.Add_Click({ $script:files.Clear(); $list.Items.Clear(); Update-Formats })
$form.Add_DragEnter({ if ($_.Data.GetDataPresent([Windows.Forms.DataFormats]::FileDrop)) { $_.Effect = 'Copy' } })
$form.Add_DragDrop({ Add-Files ([string[]]$_.Data.GetData([Windows.Forms.DataFormats]::FileDrop)) })
$folderButton.Add_Click({
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    if ($dialog.ShowDialog() -eq 'OK') { $script:outputDirectory = $dialog.SelectedPath; $folderBox.Text = $dialog.SelectedPath }
    $dialog.Dispose()
})
$resetFolder.Add_Click({ $script:outputDirectory = ''; $folderBox.Text = L '\u0420\u044F\u0434\u043E\u043C \u0441 \u0438\u0441\u0445\u043E\u0434\u043D\u044B\u043C\u0438 \u0444\u0430\u0439\u043B\u0430\u043C\u0438' })

function Start-NextFile {
    while ($script:index -lt $script:queue.Count) {
        $source = $script:queue[$script:index]
        $ext = [IO.Path]::GetExtension($source).ToLowerInvariant()
        $kind = $groups[$ext]
        $directory = if ($script:outputDirectory) { $script:outputDirectory } else { [IO.Path]::GetDirectoryName($source) }
        $destination = Join-Path $directory ([IO.Path]::GetFileNameWithoutExtension($source) + '.' + $script:chosenFormat)
        if ([string]::Equals([IO.Path]::GetFullPath($source), [IO.Path]::GetFullPath($destination), [StringComparison]::OrdinalIgnoreCase)) {
            $script:completed++
            $script:index++
            $progress.Value = $script:index
            continue
        }
        $status.Text = (L '\u041E\u0431\u0440\u0430\u0431\u0430\u0442\u044B\u0432\u0430\u0435\u0442\u0441\u044F ') + ($script:index + 1) + (L ' \u0438\u0437 ') + $script:queue.Count + ': ' + [IO.Path]::GetFileName($source)
        $script:job = Start-Job -ArgumentList $worker,$source,$destination,$kind,$script:chosenFormat,$script:chosenQuality -ScriptBlock {
            param($workerPath,$sourcePath,$destinationPath,$fileKind,$format,$quality)
            & $workerPath -Source $sourcePath -Destination $destinationPath -Kind $fileKind -Format $format -Quality $quality
        }
        return
    }
    $timer.Stop()
    $start.Enabled = $true
    $browse.Enabled = $true
    $clear.Enabled = $true
    $formatBox.Enabled = $true
    $qualityBox.Enabled = $true
    $folderButton.Enabled = $true
    $resetFolder.Enabled = $true
    $form.AllowDrop = $true
    $status.Text = (L '\u0413\u043E\u0442\u043E\u0432\u043E: ') + $script:completed + (L ' \u0438\u0437 ') + $script:queue.Count + (L '. \u041E\u0448\u0438\u0431\u043E\u043A: ') + $script:errors.Count + '.'
    if ($script:errors.Count) {
        [Windows.Forms.MessageBox]::Show(($script:errors -join "`r`n`r`n"), (L '\u041E\u0448\u0438\u0431\u043A\u0438 \u043A\u043E\u043D\u0432\u0435\u0440\u0442\u0430\u0446\u0438\u0438')) | Out-Null
    } else {
        [Windows.Forms.MessageBox]::Show($status.Text, (L '\u041A\u043E\u043D\u0432\u0435\u0440\u0442\u0430\u0446\u0438\u044F \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0430')) | Out-Null
    }
}
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 300
$timer.Add_Tick({
    if (-not $script:job -or $script:job.State -eq 'Running' -or $script:job.State -eq 'NotStarted') { return }
    $jobErrors = @()
    $result = Receive-Job -Job $script:job -ErrorAction SilentlyContinue -ErrorVariable jobErrors
    if ($script:job.State -ne 'Completed' -or $jobErrors.Count -gt 0) {
        $message = if ($jobErrors.Count) { ($jobErrors | ForEach-Object { $_.ToString() }) -join ' ' } else { L '\u041D\u0435\u0438\u0437\u0432\u0435\u0441\u0442\u043D\u0430\u044F \u043E\u0448\u0438\u0431\u043A\u0430.' }
        $script:errors.Add("$([IO.Path]::GetFileName($script:queue[$script:index])): $message")
    } else { $script:completed++ }
    Remove-Job -Job $script:job -Force
    $script:job = $null
    $script:index++
    $progress.Value = $script:index
    Start-NextFile
})
$start.Add_Click({
    if ($script:files.Count -eq 0 -or -not $formatBox.SelectedItem) {
        [Windows.Forms.MessageBox]::Show((L '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043F\u043E\u0434\u0445\u043E\u0434\u044F\u0449\u0438\u0435 \u0444\u0430\u0439\u043B\u044B \u0438 \u0444\u043E\u0440\u043C\u0430\u0442.')) | Out-Null
        return
    }
    $notices = New-Object 'System.Collections.Generic.List[string]'
    if (@($script:files | Where-Object { [IO.Path]::GetExtension($_) -eq '.pdf' }).Count) {
        if ($formatBox.SelectedItem -eq 'zip') { $notices.Add((L '\u041A\u0430\u0436\u0434\u0430\u044F \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u0430 PDF \u0431\u0443\u0434\u0435\u0442 \u0441\u043E\u0445\u0440\u0430\u043D\u0435\u043D\u0430 \u043E\u0442\u0434\u0435\u043B\u044C\u043D\u044B\u043C PNG \u0432 ZIP.')) }
        else { $notices.Add((L '\u0411\u0443\u0434\u0435\u0442 \u0438\u0437\u0432\u043B\u0435\u0447\u0451\u043D \u0442\u0435\u043A\u0441\u0442 PDF. \u0412\u0451\u0440\u0441\u0442\u043A\u0430, \u0438\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u044F \u0438 \u0441\u0442\u0440\u0430\u043D\u0438\u0446\u044B \u0431\u0435\u0437 \u0442\u0435\u043A\u0441\u0442\u043E\u0432\u043E\u0433\u043E \u0441\u043B\u043E\u044F \u043D\u0435 \u0441\u043E\u0445\u0440\u0430\u043D\u044F\u0442\u0441\u044F.')) }
    }
    $extensions = @($script:files | ForEach-Object { [IO.Path]::GetExtension($_).ToLowerInvariant() })
    if ($extensions -contains '.gif') { $notices.Add((L '\u0418\u0437 GIF \u0431\u0443\u0434\u0435\u0442 \u0441\u043E\u0445\u0440\u0430\u043D\u0451\u043D \u0442\u043E\u043B\u044C\u043A\u043E \u043F\u0435\u0440\u0432\u044B\u0439 \u043A\u0430\u0434\u0440.')) }
    if ($extensions -contains '.psd') { $notices.Add((L '\u0418\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u0435 PSD \u0431\u0443\u0434\u0435\u0442 \u0441\u0432\u0435\u0434\u0435\u043D\u043E \u0432 \u043E\u0434\u0438\u043D \u0441\u043B\u043E\u0439.')) }
    if ($formatBox.SelectedItem -eq 'csv') { $notices.Add((L 'CSV \u0441\u043E\u0445\u0440\u0430\u043D\u0438\u0442 \u0442\u043E\u043B\u044C\u043A\u043E \u043E\u0434\u0438\u043D \u043B\u0438\u0441\u0442 \u0442\u0430\u0431\u043B\u0438\u0446\u044B.')) }
    if ($formatBox.SelectedItem -in @('jpg','bmp') -and @($extensions | Where-Object { $groups[$_] -eq 'image' }).Count) {
        $notices.Add((L '\u041F\u0440\u043E\u0437\u0440\u0430\u0447\u043D\u044B\u0439 \u0444\u043E\u043D \u0438\u0437\u043E\u0431\u0440\u0430\u0436\u0435\u043D\u0438\u044F \u0441\u0442\u0430\u043D\u0435\u0442 \u0431\u0435\u043B\u044B\u043C.'))
    }
    if ($notices.Count -gt 0) {
        $answer = [Windows.Forms.MessageBox]::Show(($notices -join [Environment]::NewLine), (L '\u041E\u0441\u043E\u0431\u0435\u043D\u043D\u043E\u0441\u0442\u0438 \u043F\u0440\u0435\u043E\u0431\u0440\u0430\u0437\u043E\u0432\u0430\u043D\u0438\u044F'), 'YesNo', 'Information')
        if ($answer -ne 'Yes') { return }
    }
    $script:queue = @($script:files.ToArray())
    $script:index = 0
    $script:completed = 0
    $script:errors.Clear()
    $script:chosenFormat = [string]$formatBox.SelectedItem
    $script:chosenQuality = @('high','standard','small')[$qualityBox.SelectedIndex]
    $progress.Maximum = $script:queue.Count
    $progress.Value = 0
    $start.Enabled = $false
    $browse.Enabled = $false
    $clear.Enabled = $false
    $formatBox.Enabled = $false
    $qualityBox.Enabled = $false
    $folderButton.Enabled = $false
    $resetFolder.Enabled = $false
    $form.AllowDrop = $false
    Start-NextFile
    if ($script:job) { $timer.Start() }
})

function Ensure-WindowVisible {
    if (-not [FileConverterApp.Win32Window]::IsWindowVisible($form.Handle)) {
        [void][FileConverterApp.Win32Window]::ShowWindow($form.Handle, 5)
    }
    if (-not $script:shownOnce) {
        $script:shownOnce = $true
        [void][FileConverterApp.Win32Window]::ShowWindow($form.Handle, 5)
        [void][FileConverterApp.Win32Window]::SetForegroundWindow($form.Handle)
        $form.TopMost = $true
        $form.Activate()
        $form.TopMost = $false
    }
}

function Receive-InboxFiles {
    Ensure-WindowVisible
    if ($script:job) { return }
    $msgFiles = @(Get-ChildItem -LiteralPath $inboxDir -Filter '*.txt' -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc)
    if ($msgFiles.Count -eq 0) { return }
    $incoming = New-Object 'System.Collections.Generic.List[string]'
    foreach ($mf in $msgFiles) {
        try {
            $lines = [IO.File]::ReadAllLines($mf.FullName, [Text.Encoding]::UTF8)
            Remove-Item -LiteralPath $mf.FullName -Force -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                if ($line -and $line -ne '__ACTIVATE__') { $incoming.Add($line) }
            }
        } catch {}
    }
    if ($incoming.Count -gt 0) { Add-Files $incoming.ToArray() }
    if ($form.WindowState -eq 'Minimized') { $form.WindowState = 'Normal' }
    [void][FileConverterApp.Win32Window]::ShowWindow($form.Handle, 5)
    [void][FileConverterApp.Win32Window]::SetForegroundWindow($form.Handle)
    $form.Activate()
}

$inboxTimer = New-Object Windows.Forms.Timer
$inboxTimer.Interval = 150
$inboxTimer.Add_Tick({ Receive-InboxFiles })

$form.Add_Shown({
    Ensure-WindowVisible
    Receive-InboxFiles
})
$form.Add_FormClosing({
    if ($script:job -and $script:job.State -in @('Running','NotStarted')) {
        [Windows.Forms.MessageBox]::Show((L '\u0414\u043E\u0436\u0434\u0438\u0442\u0435\u0441\u044C \u0437\u0430\u0432\u0435\u0440\u0448\u0435\u043D\u0438\u044F \u043A\u043E\u043D\u0432\u0435\u0440\u0442\u0430\u0446\u0438\u0438.')) | Out-Null
        $_.Cancel = $true
    }
})
$form.Add_FormClosed({
    $inboxTimer.Stop()
    $inboxTimer.Dispose()
    $timer.Stop()
    $timer.Dispose()
    try { $script:instanceMutex.ReleaseMutex() } catch {}
    $script:instanceMutex.Dispose()
})

if ($args.Count) { Add-Files ([string[]]$args) } else { Update-Formats }
$inboxTimer.Start()
[void]$form.ShowDialog()
