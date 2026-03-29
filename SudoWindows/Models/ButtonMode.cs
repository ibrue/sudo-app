using System;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace SudoWindows.Models;

/// <summary>
/// Determines whether a button executes a simple preset action or a complex UI-search action.
/// </summary>
public enum ButtonModeType
{
    Simple,
    Complex
}

/// <summary>
/// Serializable configuration for a single button.
/// </summary>
public class ButtonConfig
{
    [JsonPropertyName("mode")]
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ButtonModeType Mode { get; set; } = ButtonModeType.Complex;

    [JsonPropertyName("simpleAction")]
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public SimpleActionType? SimpleAction { get; set; }

    [JsonPropertyName("searchTerms")]
    public string[]? SearchTerms { get; set; }

    public ButtonConfig() { }

    public ButtonConfig(ButtonModeType mode, SimpleActionType? simpleAction = null, string[]? searchTerms = null)
    {
        Mode = mode;
        SimpleAction = simpleAction;
        SearchTerms = searchTerms;
    }
}
