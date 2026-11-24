import Foundation

public struct AppRoot: Sendable {
    public var url: URL
    public var label: String

    public init(url: URL, label: String) {
        self.url = url
        self.label = label
    }
}

public struct AppEntry: Equatable, Hashable, Identifiable, Sendable {
    public var name: String
    public var path: String
    public var folder: String
    public var id: String { path }

    public init(name: String, path: String, folder: String) {
        self.name = name
        self.path = path
        self.folder = folder
    }
}

public enum AppCatalog {
    public static var standardRoots: [AppRoot] {
        [AppRoot(url: URL(fileURLWithPath: "/Applications"), label: "Applications"),
         AppRoot(url: URL(fileURLWithPath: "/System/Applications"), label: "System"),
         AppRoot(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                 label: "Home")]
    }

    public static func scan(_ roots: [AppRoot]) async -> [AppEntry] {
        await Task.detached(priority: .userInitiated) { scan(roots) }.value
    }

    // Blocking disk walk: call off the main thread, or use the async overload.
    public static func scan(_ roots: [AppRoot]) -> [AppEntry] {
        var seen = Set<String>()
        var found: [AppEntry] = []
        func add(_ url: URL, folder: String) {
            let resolved = url.resolvingSymlinksInPath().path
            guard seen.insert(resolved).inserted else { return }
            found.append(AppEntry(name: name(forPath: url.path), path: url.path, folder: folder))
        }
        for root in roots {
            for item in listing(root.url) {
                if isApp(item) {
                    if isDirectory(item) { add(item, folder: root.label) }
                } else if isDirectory(item) {
                    for inner in listing(item) where isApp(inner) && isDirectory(inner) {
                        add(inner, folder: "\(root.label)/\(item.lastPathComponent)")
                    }
                }
            }
        }
        return found.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.path < $1.path : order == .orderedAscending
        }
    }

    public static func entry(forApp url: URL) -> AppEntry? {
        guard isApp(url), isDirectory(url) else { return nil }
        return AppEntry(name: name(forPath: url.path), path: url.path,
                        folder: url.deletingLastPathComponent().lastPathComponent)
    }

    public static func name(forPath path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if let bundle = Bundle(url: url) {
            let localized = bundle.localizedInfoDictionary
            let plain = bundle.infoDictionary
            let candidates = [localized?["CFBundleDisplayName"], plain?["CFBundleDisplayName"],
                              localized?["CFBundleName"], plain?["CFBundleName"]]
            for case let value as String in candidates where !value.isEmpty { return value }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    public static func filter(_ apps: [AppEntry], query: String) -> [AppEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return apps }
        return apps.filter { $0.name.localizedStandardContains(trimmed) }
    }

    private static func listing(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isHiddenKey],
            options: [.skipsHiddenFiles])) ?? []
    }

    private static func isApp(_ url: URL) -> Bool {
        url.lastPathComponent.hasSuffix(".app")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
}
