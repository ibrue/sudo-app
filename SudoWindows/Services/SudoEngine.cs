using System;
using SudoWindows.Models;

namespace SudoWindows.Services;

/// <summary>
/// Central orchestrator: receives pad actions and coordinates detection -> execution.
/// Equivalent to SudoEngine on macOS.
/// </summary>
public class SudoEngine : IDisposable
{
    public string LastAction { get; private set; } = "Waiting for input...";
    public string LastMethod { get; private set; } = "";
    public string DetectedApp { get; private set; } = "No AI app detected";
    public bool IsConnected { get; private set; }

    public event Action? StatusChanged;

    private readonly AppDetector _appDetector = new();
    private readonly UIAutomationButtonFinder _buttonFinder = new();
    private readonly ActionExecutor _executor = new();
    private readonly SimpleActionExecutor _simpleExecutor = new();
    private readonly HotkeyListener _hotkeyListener = new();
    private readonly ButtonConfigStore _configStore = ButtonConfigStore.Shared;
    private System.Windows.Forms.Timer? _appDetectionTimer;
    private bool _disposed;

    public void Start()
    {
        _hotkeyListener.HotkeyPressed += HandleAction;
        _hotkeyListener.Start();
        IsConnected = true;

        // Poll for foreground app every second (like macOS version)
        _appDetectionTimer = new System.Windows.Forms.Timer { Interval = 1000 };
        _appDetectionTimer.Tick += (_, _) => UpdateDetectedApp();
        _appDetectionTimer.Start();

        StatusChanged?.Invoke();
    }

    public void Stop()
    {
        _appDetectionTimer?.Stop();
        _appDetectionTimer?.Dispose();
        _appDetectionTimer = null;

        _hotkeyListener.HotkeyPressed -= HandleAction;
        _hotkeyListener.Stop();
        IsConnected = false;
        StatusChanged?.Invoke();
    }

    private void UpdateDetectedApp()
    {
        var app = _appDetector.DetectForegroundApp();
        if (app != null)
        {
            string label = app.IsBrowser
                ? $"{app.ProcessName} ({app.MatchedDomain ?? "web"})"
                : app.DisplayName;
            DetectedApp = label;
        }
        else
        {
            DetectedApp = "No AI app detected";
        }
        // Don't fire StatusChanged for every poll to avoid excessive redraws
    }

    private void HandleAction(PadActionType action)
    {
        LastAction = $"Processing: {action.GetDisplayName()}...";
        LastMethod = "";
        StatusChanged?.Invoke();

        var config = _configStore.GetConfig(action);

        // Simple mode: execute preset action directly
        if (config.Mode == ButtonModeType.Simple && config.SimpleAction.HasValue)
        {
            bool success = _simpleExecutor.Execute(config.SimpleAction.Value);
            var info = SimpleAction.Actions[config.SimpleAction.Value];
            LastAction = success
                ? $"{action.GetDisplayName()}"
                : $"{action.GetDisplayName()} - failed";
            LastMethod = success
                ? $"Simple -> {info.DisplayName}"
                : "Simple action failed";
            StatusChanged?.Invoke();
            return;
        }

        // Complex mode: detect app -> find button -> execute
        var app = _appDetector.DetectForegroundApp();
        if (app == null)
        {
            LastAction = $"{action.GetDisplayName()} - no AI app in focus";
            LastMethod = "";
            StatusChanged?.Invoke();
            return;
        }

        Console.WriteLine($"[sudo] Target: {app.DisplayName} (PID {app.ProcessId}), action: {action.GetDisplayName()}");

        // UI Automation search
        var searchTerms = _configStore.SearchTerms(action);
        var result = _buttonFinder.FindButton(searchTerms, app.WindowHandle);

        if (result.Succeeded && result.Element != null)
        {
            var execResult = _executor.Execute(result.Element);
            if (execResult.Result == ActionExecutor.ExecutionResult.Success)
            {
                LastAction = $"{action.GetDisplayName()}";
                LastMethod = $"UI Automation -> {execResult.Detail}";
                Console.WriteLine($"[sudo] OK: {action.GetDisplayName()} via UI Automation -> {execResult.Detail}");
            }
            else
            {
                LastAction = $"{action.GetDisplayName()} - failed";
                LastMethod = $"UI Automation: {execResult.Detail}";
            }
        }
        else
        {
            LastAction = $"{action.GetDisplayName()} - button not found";
            LastMethod = $"Searched UI Automation tree";
            Console.WriteLine($"[sudo] Button not found: {result.FailureReason}");
        }

        StatusChanged?.Invoke();
    }

    public void Dispose()
    {
        if (!_disposed)
        {
            Stop();
            _hotkeyListener.Dispose();
            _disposed = true;
        }
        GC.SuppressFinalize(this);
    }
}
