param([Parameter(Mandatory=$true)][string]$Source, [Parameter(Mandatory=$true)][string]$Kind, [Parameter(Mandatory=$true)][string]$Format, [switch]$Silent)
$ErrorActionPreference = 'Stop'
if (-not $Silent) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class ConverterDpi
{
    [DllImport("user32.dll")]
    private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

    public static void Enable()
    {
        // Render text at the DPI of the monitor that owns the window.
        SetThreadDpiAwarenessContext(new IntPtr(-4));
    }
}
"@
    [ConverterDpi]::Enable()
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.Application]::EnableVisualStyles()
}

function Show-ConversionProgress {
    param([string]$Worker, [string]$InputPath, [string]$OutputPath, [string]$FileKind, [string]$TargetFormat)

    $window = New-Object Windows.Forms.Form
    $window.Text = 'Конвертер файлов'
    $window.StartPosition = 'CenterScreen'
    $window.SuspendLayout()
    $window.FormBorderStyle = 'FixedDialog'
    $window.MaximizeBox = $false
    $window.ClientSize = [Drawing.Size]::new(440, 176)
    $window.Font = [Drawing.Font]::new('Segoe UI', 10)

    $heading = New-Object Windows.Forms.Label
    $heading.SetBounds(20, 16, 400, 30)
    $heading.Font = [Drawing.Font]::new('Segoe UI Semibold', 14)
    $heading.Text = 'Конвертация в ' + $TargetFormat.ToUpperInvariant()

    $name = New-Object Windows.Forms.Label
    $name.SetBounds(20, 50, 400, 24)
    $name.AutoEllipsis = $true
    $name.UseMnemonic = $false
    $name.Text = [IO.Path]::GetFileName($InputPath)

    $progress = New-Object Windows.Forms.ProgressBar
    $progress.SetBounds(20, 83, 400, 9)
    $progress.Style = 'Marquee'
    $progress.MarqueeAnimationSpeed = 28

    $status = New-Object Windows.Forms.Label
    $status.SetBounds(20, 103, 400, 24)
    $status.Text = 'Обрабатываем файл…'
    $status.AutoEllipsis = $true
    $status.UseMnemonic = $false

    $folder = New-Object Windows.Forms.Button
    $folder.SetBounds(171, 135, 149, 30)
    $folder.Text = 'Открыть папку'
    $folder.Visible = $false
    $folder.Add_Click({
        try {
            Start-Process -FilePath ([IO.Path]::GetDirectoryName($OutputPath))
        } catch {
            [void][Windows.Forms.MessageBox]::Show($window, $_.Exception.Message, 'Не удалось открыть папку')
        }
    })

    $close = New-Object Windows.Forms.Button
    $close.SetBounds(330, 135, 90, 30)
    $close.Text = 'Закрыть'
    $close.Enabled = $false
    $close.Add_Click({ $window.Close() })
    $window.AcceptButton = $close
    $window.Controls.AddRange(@($heading, $name, $progress, $status, $folder, $close))
    $window.AutoScaleDimensions = [Drawing.SizeF]::new(96, 96)
    $window.AutoScaleMode = 'Dpi'
    $window.ResumeLayout($true)

    $conversion = [powershell]::Create()
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 100
    $state = @{ Task = $null; Done = $false; ErrorText = $null }
    $window.Add_FormClosing({ if (-not $state.Done) { $_.Cancel = $true } })
    $timer.Add_Tick({
        if ($state.Task -and -not $state.Task.IsCompleted) { return }
        $timer.Stop()
        try {
            if (-not $state.ErrorText) {
                [void]$conversion.EndInvoke($state.Task)
                if ($conversion.Streams.Error.Count) { throw $conversion.Streams.Error[0] }
                if (-not [IO.File]::Exists($OutputPath)) { throw 'Файл результата не создан.' }
            }
        } catch {
            $state.ErrorText = if ($conversion.Streams.Error.Count) {
                $conversion.Streams.Error[0].Exception.Message
            } else { $_.Exception.GetBaseException().Message }
        }

        $state.Done = $true
        $close.Enabled = $true
        if ($state.ErrorText) {
            $heading.Text = 'Не удалось конвертировать'
            $progress.Visible = $false
            $status.Text = 'Подробности в сообщении об ошибке.'
            [void][Windows.Forms.MessageBox]::Show($window, $state.ErrorText, 'Ошибка конвертации', 'OK', 'Error')
        } else {
            $heading.Text = 'Готово'
            $progress.Style = 'Blocks'
            $progress.Value = $progress.Maximum
            $status.Text = 'Сохранено: ' + [IO.Path]::GetFileName($OutputPath)
            $folder.Visible = $true
        }
    })
    try {
        [void]$conversion.AddCommand($Worker).AddParameter('Source', $InputPath).
            AddParameter('Destination', $OutputPath).AddParameter('Kind', $FileKind).
            AddParameter('Format', $TargetFormat)
        $window.Add_Shown({
            try { $state.Task = $conversion.BeginInvoke() }
            catch { $state.ErrorText = $_.Exception.GetBaseException().Message }
            $timer.Start()
        })
        [void]$window.ShowDialog()
        if ($state.ErrorText) { exit 1 }
    } finally {
        $timer.Dispose()
        $conversion.Dispose()
        $window.Dispose()
    }
}
try {
    $sourcePath = (Resolve-Path -LiteralPath $Source).ProviderPath
    $destination = [IO.Path]::ChangeExtension($sourcePath, $Format)
    if (-not $Silent) {
        $messages = New-Object 'System.Collections.Generic.List[string]'
        $extension = [IO.Path]::GetExtension($sourcePath).ToLowerInvariant()
        if ($Kind -eq 'image' -and $extension -eq '.gif') { $messages.Add('Будет сохранён только первый кадр GIF.') }
        if ($Kind -eq 'image' -and $extension -eq '.psd') { $messages.Add('Изображение PSD будет сведено в один слой.') }
        if ($Kind -eq 'image' -and $Format -in @('jpg','bmp')) { $messages.Add('Прозрачный фон станет белым.') }
        if ($Kind -eq 'excel' -and $Format -eq 'csv') { $messages.Add('CSV сохранит только один лист таблицы.') }
        if ($Kind -eq 'pdf' -and $Format -eq 'docx') { $messages.Add('В Word будет перенесён текст PDF. Вёрстка, изображения и страницы без текстового слоя не сохранятся.') }
        if ($messages.Count) {
            $choice = [Windows.Forms.MessageBox]::Show(($messages -join [Environment]::NewLine),'Конвертировать','YesNo','Information')
            if ($choice -ne 'Yes') { exit 0 }
        }
    }
    $worker = Join-Path $PSScriptRoot 'worker.ps1'
    if ($Silent) {
        & $worker -Source $sourcePath -Destination $destination -Kind $Kind -Format $Format | Out-Null
        Write-Output $destination
    } else {
        Show-ConversionProgress -Worker $worker -InputPath $sourcePath -OutputPath $destination -FileKind $Kind -TargetFormat $Format
    }
} catch {
    if ($Silent) { Write-Error $_; exit 1 }
    [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Ошибка конвертации','OK','Error') | Out-Null
    exit 1
}