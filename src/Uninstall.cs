using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Microsoft.Win32;

internal static class Uninstaller
{
    [DllImport("shell32.dll")]
    private static extern void SHChangeNotify(int eventId, uint flags, IntPtr item1, IntPtr item2);

    [STAThread]
    private static void Main(string[] args)
    {
        bool silent = Array.Exists(args, delegate(string a) {
            return a.Equals("/silent", StringComparison.OrdinalIgnoreCase) || a.Equals("/s", StringComparison.OrdinalIgnoreCase);
        });

        if (!silent)
        {
            DialogResult result = MessageBox.Show(
                "Вы действительно хотите удалить Конвертер файлов и все его компоненты из системы?",
                "Удаление — Конвертер файлов",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Question);

            if (result != DialogResult.Yes)
                return;
        }

        try
        {
            string appDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');

            string installScript = Path.Combine(appDir, "install-menu.ps1");
            if (File.Exists(installScript))
            {
                try
                {
                    ProcessStartInfo psi = new ProcessStartInfo
                    {
                        FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                        Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + installScript + "\" -Remove",
                        WorkingDirectory = appDir,
                        CreateNoWindow = true,
                        UseShellExecute = false
                    };
                    using (Process p = Process.Start(psi))
                    {
                        p.WaitForExit(10000);
                    }
                }
                catch { }
            }

            string[] extensions = new string[] {
                "png","jpg","jpeg","bmp","webp","tif","tiff","gif","avif","heic","ico","tga","pcx","ppm","pgm","pbm","psd",
                "mp3","wav","flac","m4a","ogg","opus","aac","wma","aiff","ac3",
                "mp4","mkv","mov","avi","webm","wmv","m4v","mpeg",
                "pdf",
                "doc","docx","rtf","odt","txt","html","htm",
                "xls","xlsx","ods","csv",
                "ppt","pptx","odp",
                "zip","7z","rar","tar","cab","iso","wim"
            };

            foreach (string ext in extensions)
            {
                try
                {
                    using (RegistryKey parent = Registry.CurrentUser.OpenSubKey(@"Software\Classes\SystemFileAssociations\." + ext + @"\shell", true))
                    {
                        if (parent != null)
                        {
                            foreach (string sub in parent.GetSubKeyNames())
                            {
                                if (sub.IndexOf("FileConverter", StringComparison.OrdinalIgnoreCase) >= 0 ||
                                    sub.IndexOf("ConvertFormats", StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    try { parent.DeleteSubKeyTree(sub, false); } catch { }
                                }
                            }
                        }
                    }
                }
                catch { }
            }

            string startMenuShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "Конвертер файлов.lnk");
            if (File.Exists(startMenuShortcut))
            {
                try { File.Delete(startMenuShortcut); } catch { }
            }

            string desktopShortcut = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory), "Конвертер файлов.lnk");
            if (File.Exists(desktopShortcut))
            {
                try { File.Delete(desktopShortcut); } catch { }
            }

            try
            {
                using (RegistryKey uninstallRoot = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall", true))
                {
                    if (uninstallRoot != null)
                    {
                        foreach (string sub in uninstallRoot.GetSubKeyNames())
                        {
                            if (sub.IndexOf("FileConverter", StringComparison.OrdinalIgnoreCase) >= 0)
                            {
                                try { uninstallRoot.DeleteSubKeyTree(sub, false); } catch { }
                            }
                        }
                    }
                }
            }
            catch { }

            try
            {
                SHChangeNotify(0x08000000, 0x1000, IntPtr.Zero, IntPtr.Zero);
            }
            catch { }

            try
            {
                string cmdArgs = string.Format("/c ping 127.0.0.1 -n 2 > nul & rmdir /s /q \"{0}\"", appDir);
                ProcessStartInfo deletePsi = new ProcessStartInfo
                {
                    FileName = "cmd.exe",
                    Arguments = cmdArgs,
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                Process.Start(deletePsi);
            }
            catch { }

            if (!silent)
            {
                MessageBox.Show("Конвертер файлов успешно удалён из системы.", "Удаление завершено", MessageBoxButtons.OK, MessageBoxIcon.Information);
            }
        }
        catch (Exception ex)
        {
            if (!silent)
            {
                MessageBox.Show("Произошла ошибка при удалении:\n" + ex.Message, "Ошибка удаления", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}

