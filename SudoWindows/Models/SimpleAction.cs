using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace SudoWindows.Models;

/// <summary>
/// Preset system shortcuts for Windows.
/// </summary>
public enum SimpleActionType
{
    TakeScreenshot,
    TakeScreenshotArea,
    Copy,
    Paste,
    Undo,
    Redo,
    Save,
    SelectAll,
    NewTab,
    CloseTab,
    SwitchApp,
    Search,
    TaskView,
    ShowDesktop,
    LockScreen
}

public class SimpleActionInfo
{
    public string DisplayName { get; }
    public string Category { get; }
    public Keys Key { get; }
    public Keys Modifiers { get; }

    public SimpleActionInfo(string displayName, string category, Keys key, Keys modifiers)
    {
        DisplayName = displayName;
        Category = category;
        Key = key;
        Modifiers = modifiers;
    }
}

public static class SimpleAction
{
    public static readonly Dictionary<SimpleActionType, SimpleActionInfo> Actions = new()
    {
        // Screenshots
        { SimpleActionType.TakeScreenshot, new SimpleActionInfo(
            "Take Screenshot (Full)", "Screenshots",
            Keys.PrintScreen, Keys.None) },
        { SimpleActionType.TakeScreenshotArea, new SimpleActionInfo(
            "Take Screenshot (Area)", "Screenshots",
            Keys.S, Keys.Shift) },

        // Clipboard
        { SimpleActionType.Copy, new SimpleActionInfo(
            "Copy", "Clipboard",
            Keys.C, Keys.Control) },
        { SimpleActionType.Paste, new SimpleActionInfo(
            "Paste", "Clipboard",
            Keys.V, Keys.Control) },

        // Editing
        { SimpleActionType.Undo, new SimpleActionInfo(
            "Undo", "Editing",
            Keys.Z, Keys.Control) },
        { SimpleActionType.Redo, new SimpleActionInfo(
            "Redo", "Editing",
            Keys.Y, Keys.Control) },
        { SimpleActionType.Save, new SimpleActionInfo(
            "Save", "Editing",
            Keys.S, Keys.Control) },
        { SimpleActionType.SelectAll, new SimpleActionInfo(
            "Select All", "Editing",
            Keys.A, Keys.Control) },

        // Browser
        { SimpleActionType.NewTab, new SimpleActionInfo(
            "New Tab", "Browser",
            Keys.T, Keys.Control) },
        { SimpleActionType.CloseTab, new SimpleActionInfo(
            "Close Tab", "Browser",
            Keys.W, Keys.Control) },

        // System
        { SimpleActionType.SwitchApp, new SimpleActionInfo(
            "Switch App (Alt+Tab)", "System",
            Keys.Tab, Keys.Alt) },
        { SimpleActionType.Search, new SimpleActionInfo(
            "Search (Win+S)", "System",
            Keys.S, Keys.None) },
        { SimpleActionType.TaskView, new SimpleActionInfo(
            "Task View (Win+Tab)", "System",
            Keys.Tab, Keys.None) },
        { SimpleActionType.ShowDesktop, new SimpleActionInfo(
            "Show Desktop (Win+D)", "System",
            Keys.D, Keys.None) },
        { SimpleActionType.LockScreen, new SimpleActionInfo(
            "Lock Screen (Win+L)", "System",
            Keys.L, Keys.None) },
    };

    /// <summary>
    /// Whether this action requires the Windows key modifier (handled specially via keybd_event).
    /// </summary>
    public static bool RequiresWinKey(SimpleActionType action)
    {
        return action switch
        {
            SimpleActionType.TakeScreenshot => true,
            SimpleActionType.TakeScreenshotArea => true,
            SimpleActionType.Search => true,
            SimpleActionType.TaskView => true,
            SimpleActionType.ShowDesktop => true,
            SimpleActionType.LockScreen => true,
            _ => false
        };
    }

    public static readonly SimpleActionType[] AllActions = (SimpleActionType[])Enum.GetValues(typeof(SimpleActionType));

    /// <summary>
    /// Returns actions grouped by category for UI display.
    /// </summary>
    public static Dictionary<string, List<SimpleActionType>> GetGroupedByCategory()
    {
        var groups = new Dictionary<string, List<SimpleActionType>>();
        foreach (var action in AllActions)
        {
            var info = Actions[action];
            if (!groups.ContainsKey(info.Category))
                groups[info.Category] = new List<SimpleActionType>();
            groups[info.Category].Add(action);
        }
        return groups;
    }
}
