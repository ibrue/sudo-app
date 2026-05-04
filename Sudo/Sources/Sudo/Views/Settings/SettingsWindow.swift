import SwiftUI

/// Root view for the standalone settings window. Sidebar on the left,
/// detail on the right — the standard macOS Preferences-style layout that
/// also adapts cleanly to iPadOS / iOS via NavigationSplitView.
///
/// Each panel is a self-contained SwiftUI view. Clipboard, URL opening,
/// and app-lifecycle calls go through the `Services/Platform/` shim, so
/// the only macOS-specific file in this surface is `SettingsWindowManager`
/// (NSWindow lifecycle). To port to iOS, swap that manager for a sheet
/// or `NavigationStack` and add the iOS branches to the platform shim.
struct SettingsWindow: View {

    enum Section: String, CaseIterable, Identifiable {
        case general
        case buttons
        case macros
        case autoSwitch
        case autoApprove
        case developer
        case history
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:     return "general"
            case .buttons:     return "buttons"
            case .macros:      return "macros"
            case .autoSwitch:  return "auto-switch"
            case .autoApprove: return "auto-approve"
            case .developer:   return "developer"
            case .history:     return "history"
            case .about:       return "about"
            }
        }

        var systemImage: String {
            switch self {
            case .general:     return "slider.horizontal.3"
            case .buttons:     return "square.grid.2x2"
            case .macros:      return "list.number"
            case .autoSwitch:  return "arrow.triangle.2.circlepath"
            case .autoApprove: return "checkmark.shield"
            case .developer:   return "terminal"
            case .history:     return "clock.arrow.circlepath"
            case .about:       return "info.circle"
            }
        }
    }

    @ObservedObject var engine: SudoEngine
    @ObservedObject var updater: OTAUpdater
    @ObservedObject var rebuilder: DevRebuilder
    @ObservedObject var apiServer: LocalAPIServer
    @ObservedObject private var settings = SudoSettings.shared

    let initialSection: Section
    @State private var selection: Section?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(Section.allCases) { section in
                    if section == .developer && !settings.isDeveloperMode {
                        EmptyView()
                    } else {
                        Label(section.title, systemImage: section.systemImage)
                            .font(SudoTheme.body)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(.ultraThinMaterial)
        }
        .navigationTitle("settings")
        .onAppear {
            if selection == nil { selection = initialSection }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowSelectSection)) { note in
            if let section = note.object as? Section {
                selection = section
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralPanel(engine: engine)
        case .buttons:
            ButtonsPanel()
        case .macros:
            MacrosPanel()
        case .autoSwitch:
            AutoSwitchPanel(engine: engine)
        case .autoApprove:
            AutoApprovePanel(engine: engine)
        case .developer:
            DeveloperPanel(engine: engine, apiServer: apiServer, rebuilder: rebuilder)
        case .history:
            HistoryPanel(engine: engine)
        case .about:
            AboutPanel(updater: updater)
        }
    }
}

/// Shared chrome for every settings panel — title row + scrollable body.
struct SettingsPanelScaffold<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: () -> Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(SudoTheme.title)
                    .foregroundColor(SudoTheme.text)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(SudoTheme.body)
                        .foregroundColor(SudoTheme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 14)

            SudoDivider()

            ScrollView {
                VStack(alignment: .leading, spacing: SudoTheme.sectionSpacing) {
                    content()
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
