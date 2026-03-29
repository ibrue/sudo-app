using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
using SudoWindows.Models;
using SudoWindows.Services;

namespace SudoWindows.Views;

/// <summary>
/// Virtual macro pad window for testing actions without the physical device.
/// Shows 4 buttons stacked vertically (1 column, 4 rows), each 2U width.
/// </summary>
public class TestPadForm : Form
{
    private static readonly Color BgColor = Color.FromArgb(0x0A, 0x0A, 0x0A);
    private static readonly Color KeyBodyColor = Color.FromArgb(0x2A, 0x2A, 0x2A);
    private static readonly Color KeyTopBorder = Color.FromArgb(0x44, 0x44, 0x44);
    private static readonly Color KeyBottomBorder = Color.FromArgb(0x11, 0x11, 0x11);
    private static readonly Color KeyHoverColor = Color.FromArgb(0x35, 0x35, 0x35);
    private static readonly Color KeyPressColor = Color.FromArgb(0x1E, 0x1E, 0x1E);
    private static readonly Color LabelColor = Color.White;
    private static readonly Color HotkeyColor = Color.FromArgb(0x66, 0x66, 0x66);

    private const int KeyWidth = 160;
    private const int KeyHeight = 56;
    private const int KeyGap = 3;
    private const int Padding = 16;

    private readonly SudoEngine _engine;

    public TestPadForm(SudoEngine engine)
    {
        _engine = engine;
        InitializeForm();
        BuildButtons();
    }

    private void InitializeForm()
    {
        Text = "[sudo] Test Mode";
        FormBorderStyle = FormBorderStyle.FixedSingle;
        MaximizeBox = false;
        MinimizeBox = false;
        TopMost = true;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = BgColor;

        int totalHeight = Padding + (KeyHeight + KeyGap) * PadAction.AllActions.Length - KeyGap + Padding;
        ClientSize = new Size(Padding + KeyWidth + Padding, totalHeight);

        ShowInTaskbar = true;
        Icon = CreateFormIcon();
    }

    private void BuildButtons()
    {
        var configStore = ButtonConfigStore.Shared;

        for (int i = 0; i < PadAction.AllActions.Length; i++)
        {
            var action = PadAction.AllActions[i];
            var hotkeyConfig = configStore.GetHotkeyConfig(action);

            string label = action.GetDisplayName();
            string hotkey = hotkeyConfig.DisplayString;

            var btn = new KeycapButton
            {
                ActionLabel = label,
                HotkeyLabel = hotkey,
                Location = new Point(Padding, Padding + i * (KeyHeight + KeyGap)),
                Size = new Size(KeyWidth, KeyHeight),
                TabIndex = i,
            };

            var capturedAction = action;
            btn.Click += (_, _) => _engine.SimulateAction(capturedAction);

            Controls.Add(btn);
        }
    }

    private static Icon CreateFormIcon()
    {
        var bmp = new Bitmap(16, 16);
        using (var g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Black);
            using var white = new SolidBrush(Color.White);
            g.FillRectangle(white, 3, 3, 2, 10);
            g.FillRectangle(white, 3, 3, 4, 2);
            g.FillRectangle(white, 3, 11, 4, 2);
            g.FillRectangle(white, 11, 3, 2, 10);
            g.FillRectangle(white, 9, 3, 4, 2);
            g.FillRectangle(white, 9, 11, 4, 2);
        }
        return Icon.FromHandle(bmp.GetHicon());
    }

    /// <summary>
    /// Owner-drawn button styled like a physical keycap.
    /// </summary>
    private class KeycapButton : Control
    {
        public string ActionLabel { get; set; } = "";
        public string HotkeyLabel { get; set; } = "";

        private bool _isHovered;
        private bool _isPressed;

        private static readonly Font ActionFont = new("Consolas", 10f, FontStyle.Bold);
        private static readonly Font HotkeyFont = new("Consolas", 7.5f, FontStyle.Regular);

        public KeycapButton()
        {
            SetStyle(
                ControlStyles.UserPaint |
                ControlStyles.AllPaintingInWmPaint |
                ControlStyles.OptimizedDoubleBuffer |
                ControlStyles.ResizeRedraw,
                true);
            Cursor = Cursors.Hand;
        }

        protected override void OnMouseEnter(EventArgs e)
        {
            _isHovered = true;
            Invalidate();
            base.OnMouseEnter(e);
        }

        protected override void OnMouseLeave(EventArgs e)
        {
            _isHovered = false;
            _isPressed = false;
            Invalidate();
            base.OnMouseLeave(e);
        }

        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                _isPressed = true;
                Invalidate();
            }
            base.OnMouseDown(e);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left)
            {
                _isPressed = false;
                Invalidate();
            }
            base.OnMouseUp(e);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;

            var rect = new Rectangle(0, 0, Width - 1, Height - 1);

            // Determine colors based on state
            Color bodyColor;
            Color topBorder;
            Color bottomBorder;

            if (_isPressed)
            {
                bodyColor = KeyPressColor;
                topBorder = KeyBottomBorder; // Swap borders for inset effect
                bottomBorder = KeyTopBorder;
            }
            else if (_isHovered)
            {
                bodyColor = KeyHoverColor;
                topBorder = KeyTopBorder;
                bottomBorder = KeyBottomBorder;
            }
            else
            {
                bodyColor = KeyBodyColor;
                topBorder = KeyTopBorder;
                bottomBorder = KeyBottomBorder;
            }

            // Draw keycap body with rounded corners
            using var path = CreateRoundedRect(rect, 4);
            using var bodyBrush = new SolidBrush(bodyColor);
            g.FillPath(bodyBrush, path);

            // Draw top border (lighter)
            using var topPen = new Pen(topBorder, 1.5f);
            g.DrawLine(topPen, 4, 0, Width - 5, 0);
            g.DrawLine(topPen, 0, 4, 0, Height / 2);
            g.DrawLine(topPen, Width - 1, 4, Width - 1, Height / 2);

            // Draw bottom border (darker)
            using var bottomPen = new Pen(bottomBorder, 1.5f);
            g.DrawLine(bottomPen, 4, Height - 1, Width - 5, Height - 1);
            g.DrawLine(bottomPen, 0, Height / 2, 0, Height - 5);
            g.DrawLine(bottomPen, Width - 1, Height / 2, Width - 1, Height - 5);

            // Draw outline
            using var outlinePen = new Pen(Color.FromArgb(0x1A, 0x1A, 0x1A), 1f);
            g.DrawPath(outlinePen, path);

            // Offset text slightly when pressed for inset feel
            int yOffset = _isPressed ? 1 : 0;

            // Draw action label
            using var labelBrush = new SolidBrush(LabelColor);
            var labelSize = g.MeasureString(ActionLabel, ActionFont);
            float labelX = (Width - labelSize.Width) / 2f;
            float labelY = (Height / 2f - labelSize.Height) / 2f + 4 + yOffset;
            g.DrawString(ActionLabel, ActionFont, labelBrush, labelX, labelY);

            // Draw hotkey label below
            using var hotkeyBrush = new SolidBrush(HotkeyColor);
            var hotkeySize = g.MeasureString(HotkeyLabel, HotkeyFont);
            float hotkeyX = (Width - hotkeySize.Width) / 2f;
            float hotkeyY = Height / 2f + 2 + yOffset;
            g.DrawString(HotkeyLabel, HotkeyFont, hotkeyBrush, hotkeyX, hotkeyY);
        }

        private static GraphicsPath CreateRoundedRect(Rectangle rect, int radius)
        {
            var path = new GraphicsPath();
            int d = radius * 2;
            path.AddArc(rect.X, rect.Y, d, d, 180, 90);
            path.AddArc(rect.Right - d, rect.Y, d, d, 270, 90);
            path.AddArc(rect.Right - d, rect.Bottom - d, d, d, 0, 90);
            path.AddArc(rect.X, rect.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
    }
}
