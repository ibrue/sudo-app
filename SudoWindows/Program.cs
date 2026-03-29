using System;
using System.Threading;
using System.Windows.Forms;
using SudoWindows.Views;

namespace SudoWindows;

static class Program
{
    private const string MutexName = "Global\\SudoWindows_SingleInstance";

    [STAThread]
    static void Main()
    {
        using var mutex = new Mutex(true, MutexName, out bool createdNew);

        if (!createdNew)
        {
            MessageBox.Show(
                "[sudo] is already running.\nCheck your system tray.",
                "[sudo]",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
            return;
        }

        Application.EnableVisualStyles();
        Application.SetCompatibleTextRenderingDefault(false);
        Application.SetHighDpiMode(HighDpiMode.PerMonitorV2);
        Application.Run(new TrayApp());
    }
}
