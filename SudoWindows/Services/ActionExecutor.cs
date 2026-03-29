using System;
using System.Runtime.InteropServices;
using System.Windows.Automation;

namespace SudoWindows.Services;

/// <summary>
/// Executes found UI Automation elements via InvokePattern or fallback click simulation.
/// Equivalent to ActionExecutor on macOS.
/// </summary>
public class ActionExecutor
{
    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern bool SetCursorPos(int x, int y);

    [DllImport("user32.dll")]
    private static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, IntPtr dwExtraInfo);

    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;

    public enum ExecutionResult
    {
        Success,
        Failure
    }

    public record ExecutionOutcome(ExecutionResult Result, string Detail);

    /// <summary>
    /// Execute a UI Automation element found by the button finder.
    /// </summary>
    public ExecutionOutcome Execute(AutomationElement element)
    {
        // Strategy 1: InvokePattern (preferred - like AXPress on macOS)
        try
        {
            if (element.TryGetCurrentPattern(InvokePattern.Pattern, out object? pattern))
            {
                ((InvokePattern)pattern).Invoke();
                return new ExecutionOutcome(ExecutionResult.Success, "InvokePattern");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] InvokePattern failed: {ex.Message}");
        }

        // Strategy 2: TogglePattern
        try
        {
            if (element.TryGetCurrentPattern(TogglePattern.Pattern, out object? pattern))
            {
                ((TogglePattern)pattern).Toggle();
                return new ExecutionOutcome(ExecutionResult.Success, "TogglePattern");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] TogglePattern failed: {ex.Message}");
        }

        // Strategy 3: SelectionItemPattern
        try
        {
            if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out object? pattern))
            {
                ((SelectionItemPattern)pattern).Select();
                return new ExecutionOutcome(ExecutionResult.Success, "SelectionItemPattern");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] SelectionItemPattern failed: {ex.Message}");
        }

        // Strategy 4: SetFocus + click at element center (fallback)
        try
        {
            var rect = element.Current.BoundingRectangle;
            if (!rect.IsEmpty && rect.Width > 0 && rect.Height > 0)
            {
                int centerX = (int)(rect.X + rect.Width / 2);
                int centerY = (int)(rect.Y + rect.Height / 2);

                try { element.SetFocus(); } catch { /* Focus not always supported */ }

                SetCursorPos(centerX, centerY);
                Thread.Sleep(50);
                mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, IntPtr.Zero);
                Thread.Sleep(50);
                mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, IntPtr.Zero);

                return new ExecutionOutcome(ExecutionResult.Success, $"Click ({centerX}, {centerY})");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Click fallback failed: {ex.Message}");
        }

        return new ExecutionOutcome(ExecutionResult.Failure, "All execution strategies failed");
    }
}
