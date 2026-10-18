import Foundation

nonisolated struct ApplicationDiscoveryTestDirectory: Sendable {
    let root: URL

    init() throws {
        let temporary = FileManager.default.temporaryDirectory
        let canonical = try temporary.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        root = URL(filePath: canonical ?? temporary.path, directoryHint: .isDirectory)
            .appendingPathComponent("LaunchpodDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func directory(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func application(
        _ name: String,
        in directory: URL? = nil,
        identifier: String? = "com.example.DiscoveryFixture",
        values: [String: Any] = [:]
    ) throws -> URL {
        let url = (directory ?? root).appendingPathComponent(name, isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        let executables = contents.appendingPathComponent("MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: executables, withIntermediateDirectories: true)
        let executable = executables.appendingPathComponent("Fixture")
        try FileManager.default.copyItem(at: URL(filePath: "/usr/bin/true"), to: executable)
        var info: [String: Any] = [
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "Fixture",
            "CFBundleName": "Fixture Name",
            "CFBundleDisplayName": "Fixture Display Name"
        ]
        if let identifier { info["CFBundleIdentifier"] = identifier }
        info.merge(values, uniquingKeysWith: { _, new in new })
        try writeInfo(info, at: url)
        return url
    }

    func writeInfo(_ info: [String: Any], at application: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: application.appendingPathComponent("Contents/Info.plist"), options: .atomic)
    }

    func alias(to target: URL, named name: String, in directory: URL? = nil) throws -> URL {
        let alias = (directory ?? root).appendingPathComponent(name)
        let bookmark = try target.bookmarkData(options: .suitableForBookmarkFile)
        try URL.writeBookmarkData(bookmark, to: alias)
        return alias
    }

    func symbolicLink(to target: URL, named name: String, in directory: URL? = nil) throws -> URL {
        let link = (directory ?? root).appendingPathComponent(name)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        return link
    }

    func canonicalURL(_ existingURL: URL) throws -> URL {
        let values = try existingURL.resourceValues(forKeys: [.canonicalPathKey])
        guard let path = values.canonicalPath else { throw CocoaError(.fileReadUnknown) }
        return URL(fileURLWithPath: path)
    }
}
