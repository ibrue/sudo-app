using System;
using System.Windows.Automation;

namespace SudoWindows.Services;

/// <summary>
/// Uses the Windows UI Automation framework to walk the automation tree
/// of the target window and find buttons matching search terms.
/// Equivalent to AXButtonFinder on macOS.
/// </summary>
public class UIAutomationButtonFinder
{
    public class FindResult
    {
        public AutomationElement? Element { get; init; }
        public string? MatchedText { get; init; }
        public bool Succeeded { get; init; }
        public string? FailureReason { get; init; }

        public static FindResult Found(AutomationElement element, string matchedText) =>
            new() { Element = element, MatchedText = matchedText, Succeeded = true };

        public static FindResult NotFound(string reason) =>
            new() { Succeeded = false, FailureReason = reason };
    }

    private static readonly ControlType[] ClickableTypes =
    {
        ControlType.Button,
        ControlType.Hyperlink,
        ControlType.MenuItem,
        ControlType.ListItem,
        ControlType.DataItem,
        ControlType.Custom,
    };

    public FindResult FindButton(string[] searchTerms, IntPtr windowHandle)
    {
        AutomationElement? windowElement;
        try
        {
            windowElement = AutomationElement.FromHandle(windowHandle);
        }
        catch (Exception ex)
        {
            return FindResult.NotFound($"Could not access window: {ex.Message}");
        }

        if (windowElement == null)
            return FindResult.NotFound("Window element not found");

        var lowerTerms = searchTerms.Select(t => t.ToLower()).ToArray();

        // Strategy 1: Search for standard clickable control types
        foreach (var controlType in ClickableTypes)
        {
            var condition = new PropertyCondition(
                AutomationElement.ControlTypeProperty, controlType);

            AutomationElementCollection? elements;
            try
            {
                elements = windowElement.FindAll(TreeScope.Descendants, condition);
            }
            catch
            {
                continue;
            }

            foreach (AutomationElement element in elements)
            {
                try
                {
                    string? name = element.Current.Name;
                    if (!string.IsNullOrEmpty(name) && MatchesSearchTerms(name, lowerTerms))
                    {
                        if (IsElementActionable(element))
                        {
                            Console.WriteLine($"[sudo] UI Automation found: '{name}' ({controlType.ProgrammaticName})");
                            return FindResult.Found(element, name);
                        }
                    }

                    // Also check AutomationId and HelpText
                    string? helpText = element.Current.HelpText;
                    if (!string.IsNullOrEmpty(helpText) && MatchesSearchTerms(helpText, lowerTerms))
                    {
                        if (IsElementActionable(element))
                        {
                            Console.WriteLine($"[sudo] UI Automation found via HelpText: '{helpText}'");
                            return FindResult.Found(element, helpText);
                        }
                    }
                }
                catch
                {
                    // Element may have become stale
                    continue;
                }
            }
        }

        // Strategy 2: Broad search using Text control type for labels near buttons
        try
        {
            var textCondition = new PropertyCondition(
                AutomationElement.ControlTypeProperty, ControlType.Text);
            var textElements = windowElement.FindAll(TreeScope.Descendants, textCondition);

            foreach (AutomationElement textElement in textElements)
            {
                try
                {
                    string? name = textElement.Current.Name;
                    if (!string.IsNullOrEmpty(name) && MatchesSearchTerms(name, lowerTerms))
                    {
                        // Check if the parent or nearby element is clickable
                        var parent = TreeWalker.ControlViewWalker.GetParent(textElement);
                        if (parent != null && IsElementActionable(parent))
                        {
                            Console.WriteLine($"[sudo] UI Automation found text '{name}' with clickable parent");
                            return FindResult.Found(parent, name);
                        }
                    }
                }
                catch
                {
                    continue;
                }
            }
        }
        catch
        {
            // Ignore broad search failures
        }

        return FindResult.NotFound("No matching button found in UI Automation tree");
    }

    private bool MatchesSearchTerms(string text, string[] lowerTerms)
    {
        string lower = text.ToLower().Trim();
        return lowerTerms.Any(term => lower == term || lower.Contains(term));
    }

    private bool IsElementActionable(AutomationElement element)
    {
        try
        {
            if (!element.Current.IsEnabled)
                return false;

            if (!element.Current.IsOffscreen)
            {
                // Check if element supports invoke or toggle patterns
                if (element.TryGetCurrentPattern(InvokePattern.Pattern, out _))
                    return true;
                if (element.TryGetCurrentPattern(TogglePattern.Pattern, out _))
                    return true;
                if (element.TryGetCurrentPattern(SelectionItemPattern.Pattern, out _))
                    return true;

                // Even without patterns, if it's a clickable type and enabled, consider it actionable
                var controlType = element.Current.ControlType;
                if (controlType == ControlType.Button ||
                    controlType == ControlType.Hyperlink ||
                    controlType == ControlType.MenuItem)
                    return true;
            }
        }
        catch
        {
            return false;
        }

        return false;
    }
}
