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
    private Dictionary<string, HotkeyConfig> _hotkeyConfigs = new();

    public event Action? ConfigChanged;
    public event Action? HotkeyConfigChanged;

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
        _hotkeyConfigs.Clear();
        Save();
        ConfigChanged?.Invoke();
        HotkeyConfigChanged?.Invoke();
    }

    // MARK: - Hotkey Config

    /// <summary>
    /// Returns the hotkey config for a given action -- custom if set, otherwise default (Ctrl+Shift+F13-F16).
    /// </summary>
    public HotkeyConfig GetHotkeyConfig(PadActionType action)
    {
        if (_hotkeyConfigs.TryGetValue(action.ToString(), out var config))
            return config;
        return HotkeyConfig.DefaultFor(action);
    }

    /// <summary>
    /// Sets a custom hotkey config for a given action.
    /// </summary>
    public void SetHotkeyConfig(HotkeyConfig config, PadActionType action)
    {
        _hotkeyConfigs[action.ToString()] = config;
        Save();
        HotkeyConfigChanged?.Invoke();
    }

    /// <summary>
    /// Resets the hotkey config for a given action back to its default.
    /// </summary>
    public void ResetHotkeyConfig(PadActionType action)
    {
        _hotkeyConfigs.Remove(action.ToString());
        Save();
        HotkeyConfigChanged?.Invoke();
    }

    /// <summary>
    /// Whether the user has a custom hotkey config for this action.
    /// </summary>
    public bool HasCustomHotkey(PadActionType action)
    {
        return _hotkeyConfigs.ContainsKey(action.ToString());
    }

    private void Load()
    {
        try
        {
            if (File.Exists(_configPath))
            {
                string json = File.ReadAllText(_configPath);

                // Try loading the new wrapper format first
                try
                {
                    var wrapper = JsonSerializer.Deserialize<ConfigWrapper>(json, JsonOptions);
                    if (wrapper != null)
                    {
                        _configs = wrapper.Buttons ?? new Dictionary<string, ButtonConfig>();
                        _hotkeyConfigs = wrapper.Hotkeys ?? new Dictionary<string, HotkeyConfig>();
                        Console.WriteLine($"[sudo] Loaded config from {_configPath}");
                        return;
                    }
                }
                catch
                {
                    // Fall through to legacy format
                }

                // Legacy format: top-level Dictionary<string, ButtonConfig>
                _configs = JsonSerializer.Deserialize<Dictionary<string, ButtonConfig>>(json, JsonOptions)
                           ?? new Dictionary<string, ButtonConfig>();
                _hotkeyConfigs = new Dictionary<string, HotkeyConfig>();
                Console.WriteLine($"[sudo] Loaded legacy config from {_configPath}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Failed to load config: {ex.Message}");
            _configs = new Dictionary<string, ButtonConfig>();
            _hotkeyConfigs = new Dictionary<string, HotkeyConfig>();
        }
    }

    private void Save()
    {
        try
        {
            Directory.CreateDirectory(_configDir);
            var wrapper = new ConfigWrapper
            {
                Buttons = _configs,
                Hotkeys = _hotkeyConfigs
            };
            string json = JsonSerializer.Serialize(wrapper, JsonOptions);
            File.WriteAllText(_configPath, json);
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[sudo] Failed to save config: {ex.Message}");
        }
    }

    /// <summary>
    /// Wrapper for serializing both button configs and hotkey configs.
    /// </summary>
    private class ConfigWrapper
    {
        [JsonPropertyName("buttons")]
        public Dictionary<string, ButtonConfig>? Buttons { get; set; }

        [JsonPropertyName("hotkeys")]
        public Dictionary<string, HotkeyConfig>? Hotkeys { get; set; }
    }
}
