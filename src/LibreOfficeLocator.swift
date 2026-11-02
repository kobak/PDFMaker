import AppKit

enum LibreOfficeLocator {
    static let preferenceKey = "LibreOfficeApplicationPath"

    static func usesBundledEngine(in bundle: Bundle = .main) -> Bool {
        bundle.object(forInfoDictionaryKey: "PDFMakerEngineMode") as? String == "bundled"
    }

    /// Validate an application package without launching or modifying it.
    static func executable(in application: URL) -> URL? {
        guard application.isFileURL, application.pathExtension.lowercased() == "app",
              let data = try? Data(contentsOf: application.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundleIdentifier"] as? String == "org.libreoffice.script" else { return nil }
        let executable = application.appendingPathComponent("Contents/MacOS/soffice")
        return FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil
    }

    static func isStandaloneInstallation(_ application: URL) -> Bool {
        let resolved = application.resolvingSymlinksInPath().standardizedFileURL
        // Launch Services can return the engine inside an older Full build,
        // an app in Trash, or an installer volume. These are not installations.
        let parents = resolved.deletingLastPathComponent().pathComponents
        return !parents.contains(where: { $0.lowercased().hasSuffix(".app") })
            && !parents.contains(".Trash") && !parents.contains(".Trashes")
            && !resolved.path.hasPrefix("/Volumes/")
    }

    static func externalExecutable(customApplication: URL?,
                                   applicationDirectories: [URL],
                                   registeredApplication: URL?) -> URL? {
        var candidates: [URL] = []
        if let customApplication { candidates.append(customApplication) }
        for directory in applicationDirectories {
            for name in ["LibreOffice.app", "LibreOfficeDev.app"] {
                candidates.append(directory.appendingPathComponent(name))
            }
        }
        if let registeredApplication { candidates.append(registeredApplication) }
        return candidates.lazy.filter(isStandaloneInstallation).compactMap { executable(in: $0) }.first
    }

    static func current(in bundle: Bundle = .main, overrideApplication: URL? = nil) -> URL? {
        // An explicit command-line location is used only for verification and
        // never changes the saved location or silently falls back elsewhere.
        if let overrideApplication { return executable(in: overrideApplication) }
        if usesBundledEngine(in: bundle) {
            return executable(in: bundle.bundleURL.appendingPathComponent("Contents/Resources/ConverterEngine.app"))
        }
        let saved = UserDefaults.standard.string(forKey: preferenceKey).map { URL(fileURLWithPath: $0) }
        return externalExecutable(customApplication: saved,
            applicationDirectories: [URL(fileURLWithPath: "/Applications", isDirectory: true),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)],
            registeredApplication: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.libreoffice.script"))
    }
}
