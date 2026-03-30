import Foundation

/// AI applications the daemon knows how to interact with
enum SupportedApp: String, CaseIterable {
    // Native AI apps
    case claude     = "com.anthropic.claudefordesktop"
    case chatgpt    = "com.openai.chat"

    // AI-enabled editors
    case cursor     = "com.todesktop.230313mzl4w4u92"
    case vscode     = "com.microsoft.VSCode"
    case vscodeInsiders = "com.microsoft.VSCodeInsiders"
    case vscodium   = "com.vscodium"
    case windsurf   = "com.codeium.windsurf"

    // Terminals running Claude Code
    case terminal   = "com.apple.Terminal"
    case iterm      = "com.googlecode.iterm2"
    case warp       = "dev.warp.Warp-Stable"
    case ghostty    = "com.mitchellh.ghostty"
    case kitty      = "net.kovidgoyal.kitty"
    case alacritty  = "org.alacritty"

    // Web-based AI apps
    case claudeWeb  = "claude.ai"
    case chatgptWeb = "chatgpt.com"
    case grok       = "grok.com"

    static let nativeBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
    ]

    /// Editors and terminals that may run AI agents (Claude Code, Cline, etc.)
    static let editorBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.vscodium",
        "com.codeium.windsurf",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "org.alacritty",
    ]

    static let webDomains: [String] = [
        "claude.ai",
        "chatgpt.com",
        "grok.com",
        "chat.openai.com",
    ]

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "org.mozilla.firefox",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
    ]

    var displayName: String {
        switch self {
        case .claude, .claudeWeb:   return "Claude"
        case .chatgpt, .chatgptWeb: return "ChatGPT"
        case .grok:                 return "Grok"
        case .vscode, .vscodeInsiders: return "VS Code"
        case .cursor:               return "Cursor"
        case .vscodium:             return "VSCodium"
        case .windsurf:             return "Windsurf"
        case .terminal:             return "Terminal"
        case .iterm:                return "iTerm2"
        case .warp:                 return "Warp"
        case .ghostty:              return "Ghostty"
        case .kitty:                return "Kitty"
        case .alacritty:            return "Alacritty"
        }
    }
}
