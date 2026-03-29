using System;
using System.Drawing;
using System.Windows.Forms;
using SudoWindows.Models;
using SudoWindows.Services;

namespace SudoWindows.Views;

/// <summary>
/// System tray application with NotifyIcon context menu.
/// Equivalent to MenuBarView on macOS.
/// </summary>
public class TrayApp : ApplicationContext
{
    private readonly NotifyIcon _trayIcon;
    private readonly SudoEngine _engine;
    private readonly ContextMenuStrip _contextMenu;
    private ConfigForm? _configForm;

    // Menu items that get updated
    private ToolStripMenuItem _statusItem = null!;
    private ToolStripMenuItem _appItem = null!;
    private ToolStripMenuItem _lastActionItem = null!;
    private ToolStripMenuItem _lastMethodItem = null!;

    // Dark theme colors
    private static readonly Color BgColor = Color.FromArgb(0x0A, 0x0A, 0x0A);
    private static readonly Color GreenAccent = Color.FromArgb(0x00, 0xFF, 0x41);
    private static readonly Color DimText = Color.FromArgb(0x66, 0x66, 0x66);
    private static readonly Color WhiteText = Color.FromArgb(0xFF, 0xFF, 0xFF);
    private static readonly Color BlueAccent = Color.FromArgb(0x00, 0xBF, 0xFF);

    public TrayApp()
    {
        _engine = new SudoEngine();
        _contextMenu = BuildContextMenu();
        ApplyDarkTheme(_contextMenu);

        _trayIcon = new NotifyIcon
        {
            Icon = CreateTrayIcon(),
            Text = "[sudo]",
            Visible = true,
            ContextMenuStrip = _contextMenu
        };

        _trayIcon.DoubleClick += (_, _) => OpenConfig();

        _engine.StatusChanged += OnStatusChanged;
        _engine.Start();

        UpdateMenuItems();
    }

    private ContextMenuStrip BuildContextMenu()
    {
        var menu = new ContextMenuStrip();
        menu.ShowImageMargin = false;

        // Header
        var header = new ToolStripMenuItem("[sudo]")
        {
            Enabled = false,
            Font = new Font("Consolas", 10, FontStyle.Bold),
            ForeColor = GreenAccent,
        };
        menu.Items.Add(header);
        menu.Items.Add(new ToolStripSeparator());

        // Status section
        _statusItem = new ToolStripMenuItem("Status: Connected")
        {
            Enabled = false,
            Font = new Font("Consolas", 9),
            ForeColor = DimText,
        };
        menu.Items.Add(_statusItem);

        _appItem = new ToolStripMenuItem("app: No AI app detected")
        {
            Enabled = false,
            Font = new Font("Consolas", 9),
            ForeColor = WhiteText,
        };
        menu.Items.Add(_appItem);

        _lastActionItem = new ToolStripMenuItem("last: Waiting for input...")
        {
            Enabled = false,
            Font = new Font("Consolas", 9),
            ForeColor = WhiteText,
        };
        menu.Items.Add(_lastActionItem);

        _lastMethodItem = new ToolStripMenuItem("via: -")
        {
            Enabled = false,
            Font = new Font("Consolas", 9),
            ForeColor = WhiteText,
        };
        menu.Items.Add(_lastMethodItem);

        menu.Items.Add(new ToolStripSeparator());

        // Button map
        var buttonMapHeader = new ToolStripMenuItem("> button map")
        {
            Enabled = false,
            Font = new Font("Consolas", 8),
            ForeColor = DimText,
        };
        menu.Items.Add(buttonMapHeader);

        var configStore = ButtonConfigStore.Shared;
        foreach (var action in PadAction.AllActions)
        {
            string label = $"F{action.GetFKeyNumber()}  {action.GetDisplayName()}";
            if (configStore.IsCustomized(action))
                label += " *";

            var item = new ToolStripMenuItem(label)
            {
                Enabled = false,
                Font = new Font("Consolas", 9),
                ForeColor = GreenAccent,
            };
            menu.Items.Add(item);
        }

        menu.Items.Add(new ToolStripSeparator());

        // Configure Buttons
        var configItem = new ToolStripMenuItem("Configure Buttons...")
        {
            Font = new Font("Consolas", 9),
            ForeColor = GreenAccent,
        };
        configItem.Click += (_, _) => OpenConfig();
        menu.Items.Add(configItem);

        // Check for Updates
        var updateItem = new ToolStripMenuItem("Check for Updates")
        {
            Font = new Font("Consolas", 9),
            ForeColor = DimText,
        };
        updateItem.Click += (_, _) =>
        {
            MessageBox.Show("Update checking not yet implemented.", "[sudo]",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
        };
        menu.Items.Add(updateItem);

        menu.Items.Add(new ToolStripSeparator());

        // Quit
        var quitItem = new ToolStripMenuItem("Quit")
        {
            Font = new Font("Consolas", 9),
            ForeColor = DimText,
        };
        quitItem.Click += (_, _) =>
        {
            _engine.Dispose();
            _trayIcon.Visible = false;
            Application.Exit();
        };
        menu.Items.Add(quitItem);

        return menu;
    }

    private void ApplyDarkTheme(ContextMenuStrip menu)
    {
        menu.BackColor = BgColor;
        menu.ForeColor = WhiteText;
        menu.Renderer = new DarkMenuRenderer();
    }

    private void OnStatusChanged()
    {
        if (_contextMenu.InvokeRequired)
        {
            _contextMenu.BeginInvoke(new Action(UpdateMenuItems));
        }
        else
        {
            UpdateMenuItems();
        }
    }

    private void UpdateMenuItems()
    {
        _statusItem.Text = _engine.IsConnected ? "Status: Connected" : "Status: Disconnected";
        _statusItem.ForeColor = _engine.IsConnected ? GreenAccent : Color.FromArgb(0xFF, 0x33, 0x33);

        _appItem.Text = $"app: {_engine.DetectedApp}";
        _lastActionItem.Text = $"last: {_engine.LastAction}";
        _lastMethodItem.Text = string.IsNullOrEmpty(_engine.LastMethod) ? "via: -" : $"via: {_engine.LastMethod}";

        _trayIcon.Text = $"[sudo] {_engine.LastAction}";
        if (_trayIcon.Text.Length > 63)
            _trayIcon.Text = _trayIcon.Text[..63];
    }

    private void OpenConfig()
    {
        if (_configForm != null && !_configForm.IsDisposed)
        {
            _configForm.BringToFront();
            _configForm.Focus();
            return;
        }

        _configForm = new ConfigForm();
        _configForm.FormClosed += (_, _) => _configForm = null;
        _configForm.Show();
    }

    /// <summary>
    /// Creates a pixel-perfect [] brackets icon on a black background.
    /// </summary>
    private static Icon CreateTrayIcon()
    {
        var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            // Black square background filling the full 16x16
            g.Clear(Color.Black);

            // Draw white "[]" brackets as rectangles for crispness
            using var white = new SolidBrush(Color.White);

            // Left bracket "[" — vertical bar + top/bottom serifs
            g.FillRectangle(white, 3, 3, 2, 10);   // vertical stroke
            g.FillRectangle(white, 3, 3, 4, 2);     // top serif
            g.FillRectangle(white, 3, 11, 4, 2);    // bottom serif

            // Right bracket "]" — vertical bar + top/bottom serifs
            g.FillRectangle(white, 11, 3, 2, 10);   // vertical stroke
            g.FillRectangle(white, 9, 3, 4, 2);     // top serif
            g.FillRectangle(white, 9, 11, 4, 2);    // bottom serif
        }

        return Icon.FromHandle(bmp.GetHicon());
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _engine.Dispose();
            _trayIcon.Dispose();
        }
        base.Dispose(disposing);
    }

    /// <summary>
    /// Custom renderer for dark-themed context menu.
    /// </summary>
    private class DarkMenuRenderer : ToolStripProfessionalRenderer
    {
        public DarkMenuRenderer() : base(new DarkColorTable()) { }

        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e)
        {
            e.TextColor = e.Item.ForeColor;
            base.OnRenderItemText(e);
        }

        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e)
        {
            if (e.Item.Selected && e.Item.Enabled)
            {
                using var brush = new SolidBrush(Color.FromArgb(0x1E, 0x1E, 0x1E));
                e.Graphics.FillRectangle(brush, e.Item.ContentRectangle);
            }
            else
            {
                using var brush = new SolidBrush(BgColor);
                e.Graphics.FillRectangle(brush, e.Item.ContentRectangle);
            }
        }

        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e)
        {
            int y = e.Item.Height / 2;
            using var pen = new Pen(Color.FromArgb(0x1E, 0x1E, 0x1E));
            e.Graphics.DrawLine(pen, 0, y, e.Item.Width, y);
        }

        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e)
        {
            using var brush = new SolidBrush(BgColor);
            e.Graphics.FillRectangle(brush, e.AffectedBounds);
        }

        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e)
        {
            using var pen = new Pen(Color.FromArgb(0x1E, 0x1E, 0x1E));
            e.Graphics.DrawRectangle(pen, 0, 0, e.AffectedBounds.Width - 1, e.AffectedBounds.Height - 1);
        }
    }

    private class DarkColorTable : ProfessionalColorTable
    {
        public override Color MenuBorder => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color MenuItemBorder => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color MenuItemSelected => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color MenuStripGradientBegin => BgColor;
        public override Color MenuStripGradientEnd => BgColor;
        public override Color MenuItemSelectedGradientBegin => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color MenuItemSelectedGradientEnd => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color MenuItemPressedGradientBegin => Color.FromArgb(0x2A, 0x2A, 0x2A);
        public override Color MenuItemPressedGradientEnd => Color.FromArgb(0x2A, 0x2A, 0x2A);
        public override Color ImageMarginGradientBegin => BgColor;
        public override Color ImageMarginGradientMiddle => BgColor;
        public override Color ImageMarginGradientEnd => BgColor;
        public override Color SeparatorDark => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color SeparatorLight => Color.FromArgb(0x1E, 0x1E, 0x1E);
        public override Color ToolStripDropDownBackground => BgColor;
    }
}
