using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class MenuLauncher
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            if (args.Length != 3)
                throw new ArgumentException("Неверное количество параметров конвертации (требуется: тип формат файл).");

            string folder = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(folder, "convert-menu.ps1");
            if (!File.Exists(script))
                throw new FileNotFoundException("Не найден файл convert-menu.ps1 в папке:\n" + folder);

            using (Process process = Process.Start(new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-Sta -NoProfile -ExecutionPolicy Bypass -File " + Quote(script) +
                    " -Kind " + Quote(args[0]) + " -Format " + Quote(args[1]) +
                    " -Source " + Quote(args[2]),
                WorkingDirectory = folder,
                UseShellExecute = false,
                CreateNoWindow = true
            })) { }
        }
        catch (Exception error)
        {
            MessageBox.Show(error.Message, "Конвертер файлов", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}

