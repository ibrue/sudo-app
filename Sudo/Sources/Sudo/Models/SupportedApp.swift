import Foundation

/// AI applications the daemon knows how to interact with
enum SupportedApp: String, CaseIterable {
    // Native AI apps
    case claude     = "com.anthropic.claudefordesktop"
    case chatgpt    = "com.openai.chat"

    // AI-enabled editors
    case cursor     = "com.todesktop.230313mzl4w4u92"
    case vscode     = "com.microsoft.VSCode"
    case vscodium   = "com.vscodium"
    case windsurf   = "com.codeium.windsurf"

    // Web-based AI apps
    case claudeWeb  = "claude.ai"
    case chatgptWeb = "chatgpt.com"
    case grok       = "grok.com"

    static let nativeBundleIDs: Set<String> = [
        // AI chat apps
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
        // AI-enabled editors
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.microsoft.VSCode",
        "com.vscodium",
        "com.codeium.windsurf",            // Windsurf
        // Terminals running Claude Code
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "io.alacritty",
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
        case .cursor:               return "Cursor"
        case .vscode:               return "VS Code"
        case .vscodium:             return "VSCodium"
        case .windsurf:             return "Windsurf"
        }
    }
}
