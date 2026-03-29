using System;
using System.Collections.Generic;
using System.Windows.Forms;

namespace SudoWindows.Models;

/// <summary>
/// Maps each macro pad button to a semantic action.
/// </summary>
public enum PadActionType
{
    Approve,
    Reject,
    Action3,
    Action4
}

public static class PadAction
{
    /// <summary>
    /// Virtual key codes for F13-F16.
    /// </summary>
    public static readonly Dictionary<PadActionType, int> KeyCodes = new()
    {
        { PadActionType.Approve, 0x7C },  // F13
        { PadActionType.Reject,  0x7D },  // F14
        { PadActionType.Action3, 0x7E },  // F15
        { PadActionType.Action4, 0x7F },  // F16
    };

    public static readonly Dictionary<PadActionType, int> FKeyNumbers = new()
    {
        { PadActionType.Approve, 13 },
        { PadActionType.Reject,  14 },
        { PadActionType.Action3, 15 },
        { PadActionType.Action4, 16 },
    };

    public static readonly Dictionary<PadActionType, string> DisplayNames = new()
    {
        { PadActionType.Approve, "Approve / Yes" },
        { PadActionType.Reject,  "Reject / No" },
        { PadActionType.Action3, "Action 3" },
        { PadActionType.Action4, "Action 4" },
    };

    public static readonly Dictionary<PadActionType, string[]> DefaultSearchTerms = new()
    {
        {
            PadActionType.Approve, new[]
            {
                "Allow", "allow once", "allow for this chat",
                "Yes", "Approve", "Accept", "Confirm", "Continue",
                "Run", "Execute", "allow", "yes", "approve",
                "Allow Once", "Allow for This Chat"
            }
        },
        {
            PadActionType.Reject, new[]
            {
                "Deny", "deny", "No", "Reject", "Cancel", "Decline",
                "Don't Allow", "Block", "Stop", "no", "reject", "cancel"
            }
        },
        {
            PadActionType.Action3, new[]
            {
                "Continue", "Next", "Skip", "Retry"
            }
        },
        {
            PadActionType.Action4, new[]
            {
                "Stop", "Cancel", "Close", "Dismiss"
            }
        }
    };

    public static readonly PadActionType[] AllActions =
    {
        PadActionType.Approve,
        PadActionType.Reject,
        PadActionType.Action3,
        PadActionType.Action4
    };

    public static string GetDisplayName(this PadActionType action) => DisplayNames[action];
    public static int GetFKeyNumber(this PadActionType action) => FKeyNumbers[action];
    public static int GetKeyCode(this PadActionType action) => KeyCodes[action];
    public static string[] GetDefaultSearchTerms(this PadActionType action) => DefaultSearchTerms[action];
}
