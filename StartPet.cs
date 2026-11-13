using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class StartPet
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string script = Path.Combine(directory, "pet.ps1");
            if (!File.Exists(script))
            {
                MessageBox.Show("\u627e\u4e0d\u5230 pet.ps1\uff0c\u8acb\u78ba\u8a8d\u6a94\u6848\u4f4d\u65bc\u540c\u4e00\u8cc7\u6599\u593e\u3002", "3WA Window Pet", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }

            var start = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.SystemDirectory, @"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments = "-NoProfile -STA -ExecutionPolicy Bypass -File \"" + script + "\"",
                WorkingDirectory = directory,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            if (Process.Start(start) == null)
            {
                throw new InvalidOperationException("Unable to start PowerShell.");
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show("\u963f\u8c5a\u7121\u6cd5\u555f\u52d5\uff1a\r\n" + ex.Message, "3WA Window Pet", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
