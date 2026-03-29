import Foundation

/// AI applications the daemon knows how to interact with
enum SupportedApp: String, CaseIterable {
    case claude     = "com.anthropic.claudefordesktop"
    case claudeWeb  = "claude.ai"
    case chatgpt    = "com.openai.chat"
    case chatgptWeb = "chatgpt.com"
    case grok       = "grok.com"

    static let nativeBundleIDs: Set<String> = [
        "com.anthropic.claudefordesktop",
        "com.openai.chat",
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
        }
    }
}
