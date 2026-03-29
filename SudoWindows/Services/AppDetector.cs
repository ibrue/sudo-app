using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace SudoWindows.Services;

/// <summary>
/// Detects whether the foreground window belongs to a supported AI application.
/// </summary>
public class AppDetector
{
    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowTextLength(IntPtr hWnd);

    /// <summary>
    /// Native desktop app process names (case-insensitive match).
    /// </summary>
    private static readonly HashSet<string> NativeAppProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "claude",           // Claude Desktop
        "Claude",
        "ChatGPT",          // ChatGPT Desktop
        "chatgpt",
    };

    /// <summary>
    /// Browser process names.
    /// </summary>
    private static readonly HashSet<string> BrowserProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "chrome",
        "firefox",
        "msedge",
        "brave",
        "opera",
        "iexplore",
        "vivaldi",
    };

    /// <summary>
    /// Web domains for AI apps.
    /// </summary>
    private static readonly string[] WebDomains =
    {
        "claude.ai",
        "chatgpt.com",
        "grok.com",
        "chat.openai.com",
    };

    public class DetectedApp
    {
        public string ProcessName { get; init; } = "";
        public string WindowTitle { get; init; } = "";
        public int ProcessId { get; init; }
        public IntPtr WindowHandle { get; init; }
        public bool IsBrowser { get; init; }
        public string? MatchedDomain { get; init; }

        public string DisplayName
        {
            get
            {
                if (MatchedDomain != null)
                {
                    return MatchedDomain switch
                    {
                        "claude.ai" => "Claude",
                        "chatgpt.com" or "chat.openai.com" => "ChatGPT",
                        "grok.com" => "Grok",
                        _ => MatchedDomain
                    };
                }

                return ProcessName.ToLower() switch
                {
                    "claude" => "Claude",
                    "chatgpt" => "ChatGPT",
                    _ => ProcessName
                };
            }
        }
    }

    public DetectedApp? DetectForegroundApp()
    {
        IntPtr hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return null;

        GetWindowThreadProcessId(hwnd, out uint processId);
        if (processId == 0) return null;

        Process process;
        try
        {
            process = Process.GetProcessById((int)processId);
        }
        catch
        {
            return null;
        }

        string processName = process.ProcessName;
        string windowTitle = GetWindowTitle(hwnd);

        // Check native AI desktop apps
        if (NativeAppProcessNames.Contains(processName))
        {
            return new DetectedApp
            {
                ProcessName = processName,
                WindowTitle = windowTitle,
                ProcessId = (int)processId,
                WindowHandle = hwnd,
                IsBrowser = false,
                MatchedDomain = null
            };
        }

        // Check browsers for AI web apps
        if (BrowserProcessNames.Contains(processName))
        {
            string? matchedDomain = DetectAIDomainInBrowser(windowTitle);
            if (matchedDomain != null)
            {
                return new DetectedApp
                {
                    ProcessName = processName,
                    WindowTitle = windowTitle,
                    ProcessId = (int)processId,
                    WindowHandle = hwnd,
                    IsBrowser = true,
                    MatchedDomain = matchedDomain
                };
            }
        }

        return null;
    }

    private string? DetectAIDomainInBrowser(string windowTitle)
    {
        string titleLower = windowTitle.ToLower();

        foreach (var domain in WebDomains)
        {
            if (titleLower.Contains(domain))
                return domain;
        }

        // Also check common patterns in browser title bars
        // e.g. "Claude - Google Chrome", "ChatGPT - Mozilla Firefox"
        if (titleLower.Contains("claude"))
            return "claude.ai";
        if (titleLower.Contains("chatgpt"))
            return "chatgpt.com";
        if (titleLower.Contains("grok"))
            return "grok.com";

        return null;
    }

    private static string GetWindowTitle(IntPtr hwnd)
    {
        int length = GetWindowTextLength(hwnd);
        if (length == 0) return "";

        var sb = new StringBuilder(length + 1);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }
}
