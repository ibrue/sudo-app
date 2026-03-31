import Foundation
import Combine

/// Definition of a plugin loaded from a JSON file.
struct PluginDefinition: Identifiable, Codable {
    let id: String
    let name: String
    let bundle_ids: [String]
    let search_terms: [String: [String]]?
}

/// Scans ~/Library/Application Support/Sudo/Plugins/ for .json plugin files
/// and registers them with app detection.
final class PluginManager: ObservableObject {

    static let shared = PluginManager()

    @Published var loadedPlugins: [PluginDefinition] = []

    /// Bundle IDs contributed by all loaded plugins.
    private(set) var pluginBundleIDs: Set<String> = []

    /// Map from bundle ID to plugin definition for quick lookup.
    private(set) var pluginsByBundleID: [String: PluginDefinition] = [:]

    private var pluginsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Sudo/Plugins")
    }

    private init() {}

    /// Create the plugins directory if needed, then load all .json files.
    func loadPlugins() {
        let fm = FileManager.default
        let dir = pluginsURL

        // create directory if it doesn't exist
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }

        var plugins: [PluginDefinition] = []
        var bundleIDs: Set<String> = []
        var byBundleID: [String: PluginDefinition] = [:]

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let plugin = try? JSONDecoder().decode(PluginDefinition.self, from: data) else {
                print("[sudo] plugin: failed to load \(file.lastPathComponent)")
                continue
            }
            plugins.append(plugin)
            for bid in plugin.bundle_ids {
                bundleIDs.insert(bid)
                byBundleID[bid] = plugin
            }
            print("[sudo] plugin: loaded \(plugin.name) (\(plugin.bundle_ids.count) bundle ids)")
        }

        DispatchQueue.main.async {
            self.loadedPlugins = plugins
            self.pluginBundleIDs = bundleIDs
            self.pluginsByBundleID = byBundleID
        }
    }

    /// Open the plugins folder in Finder.
    func openPluginsFolder() {
        let fm = FileManager.default
        let dir = pluginsURL
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(dir)
    }
}
