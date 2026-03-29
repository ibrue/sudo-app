using System;
using System.Drawing;
using System.Windows.Forms;
using SudoWindows.Models;
using SudoWindows.Services;

namespace SudoWindows.Views;

/// <summary>
/// WinForms settings window with dark Matrix-style theme.
/// Equivalent to ButtonConfigView on macOS.
/// </summary>
public class ConfigForm : Form
{
    // Dark theme colors
    private static readonly Color BgColor = Color.FromArgb(0x0A, 0x0A, 0x0A);
    private static readonly Color PanelBg = Color.FromArgb(0x1A, 0x1A, 0x1A);
    private static readonly Color BorderColor = Color.FromArgb(0x1E, 0x1E, 0x1E);
    private static readonly Color GreenAccent = Color.FromArgb(0x00, 0xFF, 0x41);
    private static readonly Color DimText = Color.FromArgb(0x66, 0x66, 0x66);
    private static readonly Color WhiteText = Color.FromArgb(0xFF, 0xFF, 0xFF);
    private static readonly Color RedAccent = Color.FromArgb(0xFF, 0x33, 0x33);
    private static readonly Color BlueAccent = Color.FromArgb(0x00, 0xBF, 0xFF);

    private readonly ButtonConfigStore _configStore = ButtonConfigStore.Shared;
    private readonly TabControl _tabControl;
    private readonly Dictionary<PadActionType, TabPage> _tabs = new();
    private readonly Dictionary<PadActionType, RadioButton> _simpleRadios = new();
    private readonly Dictionary<PadActionType, RadioButton> _complexRadios = new();
    private readonly Dictionary<PadActionType, ComboBox> _simpleActionCombos = new();
    private readonly Dictionary<PadActionType, TextBox> _searchTermBoxes = new();

    public ConfigForm()
    {
        Text = "[sudo] Key Bindings";
        Size = new Size(460, 520);
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;
        StartPosition = FormStartPosition.CenterScreen;
        BackColor = BgColor;
        ForeColor = WhiteText;
        Font = new Font("Consolas", 9);

        // Header label
        var headerLabel = new Label
        {
            Text = "> key bindings",
            Font = new Font("Consolas", 12, FontStyle.Bold),
            ForeColor = GreenAccent,
            Location = new Point(16, 12),
            AutoSize = true,
        };
        Controls.Add(headerLabel);

        // Tab control
        _tabControl = new TabControl
        {
            Location = new Point(12, 40),
            Size = new Size(420, 380),
            Font = new Font("Consolas", 9),
        };
        StyleTabControl(_tabControl);
        Controls.Add(_tabControl);

        // Create a tab for each button
        foreach (var action in PadAction.AllActions)
        {
            var tab = CreateActionTab(action);
            _tabs[action] = tab;
            _tabControl.TabPages.Add(tab);
        }

        // Bottom buttons
        var resetAllBtn = CreateStyledButton("[ RESET ALL TO DEFAULTS ]", RedAccent);
        resetAllBtn.Location = new Point(12, 430);
        resetAllBtn.Size = new Size(200, 30);
        resetAllBtn.Click += (_, _) =>
        {
            var result = MessageBox.Show("Reset all buttons to defaults?", "[sudo]",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning);
            if (result == DialogResult.Yes)
            {
                _configStore.ResetAllToDefaults();
                RefreshAllTabs();
            }
        };
        Controls.Add(resetAllBtn);

        var saveBtn = CreateStyledButton("[ SAVE ]", GreenAccent);
        saveBtn.Location = new Point(280, 430);
        saveBtn.Size = new Size(70, 30);
        saveBtn.Click += (_, _) => SaveAll();
        Controls.Add(saveBtn);

        var cancelBtn = CreateStyledButton("[ CANCEL ]", DimText);
        cancelBtn.Location = new Point(360, 430);
        cancelBtn.Size = new Size(75, 30);
        cancelBtn.Click += (_, _) => Close();
        Controls.Add(cancelBtn);
    }

    private TabPage CreateActionTab(PadActionType action)
    {
        var tab = new TabPage($"F{action.GetFKeyNumber()}")
        {
            BackColor = BgColor,
            ForeColor = WhiteText,
            Font = new Font("Consolas", 9),
            Padding = new Padding(10),
        };

        int y = 10;

        // Action name header
        var nameLabel = new Label
        {
            Text = $"F{action.GetFKeyNumber()} - {action.GetDisplayName()}",
            Font = new Font("Consolas", 11, FontStyle.Bold),
            ForeColor = GreenAccent,
            Location = new Point(10, y),
            AutoSize = true,
        };
        tab.Controls.Add(nameLabel);
        y += 30;

        // Mode selection
        var modeLabel = new Label
        {
            Text = "Mode:",
            ForeColor = DimText,
            Location = new Point(10, y),
            AutoSize = true,
        };
        tab.Controls.Add(modeLabel);
        y += 22;

        var simpleRadio = new RadioButton
        {
            Text = "Simple (preset action)",
            ForeColor = WhiteText,
            FlatStyle = FlatStyle.Flat,
            Location = new Point(20, y),
            AutoSize = true,
        };
        _simpleRadios[action] = simpleRadio;
        tab.Controls.Add(simpleRadio);
        y += 24;

        var complexRadio = new RadioButton
        {
            Text = "Complex (search UI for button)",
            ForeColor = WhiteText,
            FlatStyle = FlatStyle.Flat,
            Location = new Point(20, y),
            AutoSize = true,
        };
        _complexRadios[action] = complexRadio;
        tab.Controls.Add(complexRadio);
        y += 32;

        // Simple mode: ComboBox grouped by category
        var simpleLabel = new Label
        {
            Text = "Preset Action:",
            ForeColor = DimText,
            Location = new Point(10, y),
            AutoSize = true,
        };
        tab.Controls.Add(simpleLabel);
        y += 20;

        var combo = new ComboBox
        {
            Location = new Point(10, y),
            Size = new Size(380, 24),
            DropDownStyle = ComboBoxStyle.DropDownList,
            BackColor = PanelBg,
            ForeColor = WhiteText,
            FlatStyle = FlatStyle.Flat,
            Font = new Font("Consolas", 9),
        };
        PopulateSimpleActionCombo(combo);
        _simpleActionCombos[action] = combo;
        tab.Controls.Add(combo);
        y += 35;

        // Complex mode: TextBox for search terms
        var termsLabel = new Label
        {
            Text = "Search Terms (comma-separated):",
            ForeColor = DimText,
            Location = new Point(10, y),
            AutoSize = true,
        };
        tab.Controls.Add(termsLabel);
        y += 20;

        var termsBox = new TextBox
        {
            Location = new Point(10, y),
            Size = new Size(380, 80),
            Multiline = true,
            ScrollBars = ScrollBars.Vertical,
            BackColor = PanelBg,
            ForeColor = WhiteText,
            BorderStyle = BorderStyle.FixedSingle,
            Font = new Font("Consolas", 9),
        };
        _searchTermBoxes[action] = termsBox;
        tab.Controls.Add(termsBox);
        y += 90;

        // Reset this button
        var resetBtn = CreateStyledButton("[ RESET ]", RedAccent);
        resetBtn.Location = new Point(10, y);
        resetBtn.Size = new Size(100, 26);
        resetBtn.Click += (_, _) =>
        {
            _configStore.ResetToDefaults(action);
            RefreshTab(action);
        };
        tab.Controls.Add(resetBtn);

        // Wire up radio button changes
        simpleRadio.CheckedChanged += (_, _) => UpdateModeUI(action);
        complexRadio.CheckedChanged += (_, _) => UpdateModeUI(action);

        // Load current config
        RefreshTab(action);

        return tab;
    }

    private void PopulateSimpleActionCombo(ComboBox combo)
    {
        combo.Items.Clear();
        var groups = SimpleAction.GetGroupedByCategory();
        foreach (var (category, actions) in groups)
        {
            // Add category header (disabled-looking)
            combo.Items.Add($"--- {category} ---");
            foreach (var action in actions)
            {
                var info = SimpleAction.Actions[action];
                combo.Items.Add(new SimpleActionItem(action, info.DisplayName));
            }
        }
    }

    private void RefreshTab(PadActionType action)
    {
        var config = _configStore.GetConfig(action);

        if (config.Mode == ButtonModeType.Simple)
            _simpleRadios[action].Checked = true;
        else
            _complexRadios[action].Checked = true;

        // Set combo selection
        if (config.SimpleAction.HasValue)
        {
            var combo = _simpleActionCombos[action];
            for (int i = 0; i < combo.Items.Count; i++)
            {
                if (combo.Items[i] is SimpleActionItem item && item.ActionType == config.SimpleAction.Value)
                {
                    combo.SelectedIndex = i;
                    break;
                }
            }
        }

        // Set search terms
        var terms = _configStore.SearchTerms(action);
        _searchTermBoxes[action].Text = string.Join(", ", terms);

        UpdateModeUI(action);
    }

    private void RefreshAllTabs()
    {
        foreach (var action in PadAction.AllActions)
            RefreshTab(action);
    }

    private void UpdateModeUI(PadActionType action)
    {
        bool isSimple = _simpleRadios[action].Checked;
        _simpleActionCombos[action].Enabled = isSimple;
        _searchTermBoxes[action].Enabled = !isSimple;

        // Visual feedback
        _simpleActionCombos[action].ForeColor = isSimple ? WhiteText : DimText;
        _searchTermBoxes[action].ForeColor = !isSimple ? WhiteText : DimText;
    }

    private void SaveAll()
    {
        foreach (var action in PadAction.AllActions)
        {
            bool isSimple = _simpleRadios[action].Checked;

            SimpleActionType? simpleAction = null;
            if (_simpleActionCombos[action].SelectedItem is SimpleActionItem selectedItem)
                simpleAction = selectedItem.ActionType;

            string[] searchTerms = _searchTermBoxes[action].Text
                .Split(',', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

            var config = new ButtonConfig
            {
                Mode = isSimple ? ButtonModeType.Simple : ButtonModeType.Complex,
                SimpleAction = simpleAction,
                SearchTerms = searchTerms.Length > 0 ? searchTerms : null,
            };

            _configStore.SetConfig(action, config);
        }

        Close();
    }

    private Button CreateStyledButton(string text, Color foreColor)
    {
        var btn = new Button
        {
            Text = text,
            FlatStyle = FlatStyle.Flat,
            BackColor = BgColor,
            ForeColor = foreColor,
            Font = new Font("Consolas", 9),
            Cursor = Cursors.Hand,
        };
        btn.FlatAppearance.BorderColor = foreColor;
        btn.FlatAppearance.BorderSize = 1;
        btn.FlatAppearance.MouseOverBackColor = Color.FromArgb(0x1E, 0x1E, 0x1E);
        return btn;
    }

    private void StyleTabControl(TabControl tabControl)
    {
        tabControl.DrawMode = TabDrawMode.OwnerDrawFixed;
        tabControl.DrawItem += (sender, e) =>
        {
            var tc = (TabControl)sender!;
            var tabPage = tc.TabPages[e.Index];
            var tabBounds = e.Bounds;

            using var bgBrush = new SolidBrush(
                e.Index == tc.SelectedIndex ? PanelBg : BgColor);
            e.Graphics.FillRectangle(bgBrush, tabBounds);

            using var textBrush = new SolidBrush(
                e.Index == tc.SelectedIndex ? GreenAccent : DimText);
            using var font = new Font("Consolas", 9, FontStyle.Bold);

            var sf = new StringFormat
            {
                Alignment = StringAlignment.Center,
                LineAlignment = StringAlignment.Center
            };
            e.Graphics.DrawString(tabPage.Text, font, textBrush, tabBounds, sf);
        };
    }

    /// <summary>
    /// Wrapper for ComboBox items that preserves the SimpleActionType.
    /// </summary>
    private class SimpleActionItem
    {
        public SimpleActionType ActionType { get; }
        public string DisplayName { get; }

        public SimpleActionItem(SimpleActionType actionType, string displayName)
        {
            ActionType = actionType;
            DisplayName = displayName;
        }

        public override string ToString() => DisplayName;
    }
}
