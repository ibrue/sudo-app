using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using SudoWindows.Models;

namespace SudoWindows.Services;

/// <summary>
/// Persists per-button configuration to %APPDATA%/Sudo/config.json.
/// Equivalent to ButtonConfigStore on macOS.
/// </summary>
public class ButtonConfigStore
{
    private static readonly Lazy<ButtonConfigStore> _instance = new(() => new ButtonConfigStore());
    public static ButtonConfigStore Shared => _instance.Value;

    private readonly string _configDir;
    private readonly string _configPath;
    private Dictionary<string, ButtonConfig> _configs = new();

    public event Action? ConfigChanged;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() }
    };

    private ButtonConfigStore()
    {
        _configDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "Sudo");
        _configPath = Path.Combine(_configDir, "config.json");
        Load();
    }

    /// <summary>
    /// Returns the active search terms for a given action -- custom if set, otherwise default.
    /// </summary>
    public string[] SearchTerms(PadActionType action)
    {
        if (_configs.TryGetValue(action.ToString(), out var config) &&
            config.SearchTerms != null && config.SearchTerms.Length > 0)
        {
            return config.SearchTerms;
        }
        return action.GetDefaultSearchTerms();
    }

    /// <summary>
    /// Gets the button configuration for an action.
    /// </summary>
    public ButtonConfig GetConfig(PadActionType action)
    {
        if (_configs.TryGetValue(action.ToString(), out var config))
            return config;

        return new ButtonConfig(ButtonModeType.Complex);
    }

    /// <summary>
    /// Sets the button configuration for an action.
    /// </summary>
    public void SetConfig(PadActionType action, ButtonConfig config)
    {
        _configs[action.ToString()] = config;
        Save();
        ConfigChanged?.Invoke();
    }

    /// <summary>
    /// Updates the search terms for a given action. Pass null or empty to reset to defaults.
    /// </summary>
    public void SetSearchTerms(string[]? terms, PadActionType action)
    {
        var config = GetConfig(action);
        config.SearchTerms = (terms != null && terms.Length > 0) ? terms : null;
        _configs[action.ToString()] = config;
        Save();
        ConfigChanged?.Invoke();
    }

    /// <summary>
    /// Whether the user has customized the terms for this action.
    /// </summary>
    public bool IsCustomized(PadActionType action)
    {
        if (_configs.TryGetValue(action.ToString(), out var config))
        {
            return (config.SearchTerms != null && config.SearchTerms.Length > 0) ||
                   config.Mode == ButtonModeType.Simple;
        }
        return false;
    }

    /// <summary>
    /// Reset a single action back to defaults.
    /// </summary>
    public void ResetToDefaults(PadActionType action)
    {
        _configs.Remove(action.ToString());
        Save();
        ConfigChanged?.Invoke();
    }

    /// <summary>
    /// Reset all actions back to defaults.
    /// </summary>
    public void ResetAllToDefaults()
    {
        _configs.Clear();
        Save();
        ConfigChanged?.Invoke();
    }

    private void Load()
    {
        try
        {
            if (File.Exists(_configPath))
            {
                string json = File.ReadAllText(_configPath);
                _configs = JsonSerializer.Deserialize<Dictionary<string, ButtonConfig>>(json, JsonOptions)
                           ?? new Dictionary<string, ButtonConfig>();
                Console.WriteLine($"[sudo] Loaded config from {_configPath}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Failed to load config: {ex.Message}");
            _configs = new Dictionary<string, ButtonConfig>();
        }
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(_configDir);
            string json = JsonSerializer.Serialize(_configs, JsonOptions);
            File.WriteAllText(_configPath, json);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Failed to save config: {ex.Message}");
        }
    }
}
