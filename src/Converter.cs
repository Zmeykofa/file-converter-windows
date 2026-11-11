using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class ConverterApp
{
    [STAThread]
    private static void Main(string[] args)
    {
        try
        {
            string appDirectory = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(appDirectory, "converter.ps1");
            if (!File.Exists(scriptPath))
            {
                MessageBox.Show("Не найден файл приложения converter.ps1 в папке:\n" + appDirectory, 
                    "Конвертер файлов", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            string arguments = "-Sta -NoProfile -ExecutionPolicy Bypass -File " + Quote(scriptPath);
            foreach (string arg in args)
            {
                if (!string.IsNullOrEmpty(arg))
                    arguments += " " + Quote(arg);
            }

            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = arguments,
                WorkingDirectory = appDirectory,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show("Ошибка запуска:\n" + ex.Message, "Конвертер файлов", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static string Quote(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}

