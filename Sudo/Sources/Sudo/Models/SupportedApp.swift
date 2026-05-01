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

    /// Web domains that should switch to a media-style preset rather than
    /// the generic browser/AI ones. Detected via the same URL-bar / window
    /// title scan as `webDomains`. Maps the matched domain → AppCategory
    /// so the engine can pick the right preset (e.g. youtube → .youtube).
    static let mediaWebDomains: [(domain: String, category: AppCategory)] = [
        ("youtube.com",      .youtube),
        ("music.youtube.com", .youtube),
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

    // MARK: - App Categories

    static let mediaBundleIDs: Set<String> = [
        "com.spotify.client",
        "com.apple.Music",
        "com.apple.iTunes",
        "org.videolan.vlc",
        "com.colliderli.iina",
        "com.plex.PlexDesktop",
        "com.tidal.desktop",
        "tv.plex.plexamp",
    ]

    static let cadBundleIDs: Set<String> = [
        "com.autodesk.Fusion360",
        "com.autodesk.AutoCAD",
        "com.mcneel.rhinoceros",
        "net.freecadweb.FreeCAD",
        "com.sketchup.SketchUp",
        "com.solidworks.SOLIDWORKS",
        "com.autodesk.inventor",
        // Slicer / 3D-print prep — same category, different default preset
        // (overridden per-bundle-ID in SudoSettings).
        "com.bambulab.bambu-studio",
        "com.bambulab.BambuStudio",
    ]

    static let videoEditingBundleIDs: Set<String> = [
        "com.apple.FinalCut",
        "com.blackmagicdesign.resolve",
        "com.adobe.premiere",
        "com.adobe.AfterEffects",
        "com.luma-touch.LumaFusion",
        "com.apple.iMovieApp",
        "com.bytedance.CapCut",
    ]

    static let writingBundleIDs: Set<String> = [
        "notion.id",
        "md.obsidian",
        "com.craftdocs.craftx",
        "com.microsoft.Word",
        "com.apple.Pages",
        "com.apple.Notes",
        "net.shinyfrog.bear",
        "com.ulyssesapp.mac",
        "abnerworks.Typora",
    ]

    static let communicationBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.microsoft.teams2",
        "com.microsoft.teams",
        "com.hnc.Discord",
        "us.zoom.xos",
        "com.google.meet",
        "com.webex.meetingmanager",
    ]

    static let designBundleIDs: Set<String> = [
        "com.figma.Desktop",
        "com.bohemiancoding.sketch3",
        "com.serif.affinity-designer-2",
        "com.serif.affinity-photo-2",
        "com.adobe.Photoshop",
        "com.adobe.Illustrator",
        "com.adobe.xd",
    ]

    /// Name substrings used to detect category when bundle ID doesn't match
    static let categoryNameHints: [(substring: String, category: AppCategory)] = [
        ("fusion", .cad), ("solidworks", .cad), ("autocad", .cad), ("rhino", .cad), ("freecad", .cad), ("onshape", .cad), ("bambu", .cad),
        ("spotify", .media), ("music", .media), ("vlc", .media), ("itunes", .media),
        ("final cut", .videoEditing), ("davinci", .videoEditing), ("premiere", .videoEditing), ("capcut", .videoEditing),
        ("notion", .writing), ("obsidian", .writing), ("word", .writing), ("pages", .writing), ("bear", .writing),
        ("slack", .communication), ("teams", .communication), ("discord", .communication), ("zoom", .communication),
        ("figma", .design), ("sketch", .design), ("photoshop", .design), ("illustrator", .design),
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

// MARK: - App Category

enum AppCategory: String, CaseIterable, Codable {
    case ai
    case terminal
    case browser
    case media
    case youtube
    case cad
    case videoEditing
    case writing
    case communication
    case design
    case unknown

    var displayName: String {
        switch self {
        case .ai:            return "ai apps"
        case .terminal:      return "terminal / ide"
        case .browser:       return "browser"
        case .media:         return "media"
        case .youtube:       return "youtube"
        case .cad:           return "cad"
        case .videoEditing:  return "video editing"
        case .writing:       return "writing"
        case .communication: return "communication"
        case .design:        return "design"
        case .unknown:       return "other"
        }
    }

    /// Determine category from bundle ID
    static func from(bundleID: String, appName: String = "") -> AppCategory {
        if SupportedApp.nativeBundleIDs.contains(bundleID) { return .ai }
        if SupportedApp.editorBundleIDs.contains(bundleID) { return .terminal }
        if SupportedApp.browserBundleIDs.contains(bundleID) { return .browser }
        if SupportedApp.mediaBundleIDs.contains(bundleID) { return .media }
        if SupportedApp.cadBundleIDs.contains(bundleID) { return .cad }
        if SupportedApp.videoEditingBundleIDs.contains(bundleID) { return .videoEditing }
        if SupportedApp.writingBundleIDs.contains(bundleID) { return .writing }
        if SupportedApp.communicationBundleIDs.contains(bundleID) { return .communication }
        if SupportedApp.designBundleIDs.contains(bundleID) { return .design }

        // Fallback: match by app name
        let lower = appName.lowercased()
        for hint in SupportedApp.categoryNameHints {
            if lower.contains(hint.substring) { return hint.category }
        }

        return .unknown
    }

    /// Default preset ID for this category
    var defaultPresetID: String? {
        switch self {
        case .ai:            return "ai-agent"
        case .terminal:      return "claude-code"
        // Browsing → YouTube by default. Space already scrolls pages,
        // J/L are no-ops on non-YouTube sites, F is a safe extra. The
        // user explicitly chose this over back/forward/refresh.
        case .browser:       return "youtube"
        case .media:         return "media"
        case .youtube:       return "youtube"
        case .cad:           return "cad"
        case .videoEditing:  return "video-editing"
        case .writing:       return "writing"
        case .communication: return "communication"
        case .design:        return "design"
        case .unknown:       return nil
        }
    }
}
