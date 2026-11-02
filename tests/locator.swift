import AppKit

@main
struct LocatorChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("pdfmaker-locator-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var passed: [String] = []
        func check(_ name: String, _ value: Bool) {
            guard value else { fatalError(name) }
            passed.append(name)
        }
        func makeApp(_ url: URL, identifier: String = "org.libreoffice.script", runnable: Bool = true) throws -> URL {
            try fm.createDirectory(at: url.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier], format: .xml, options: 0)
            try data.write(to: url.appendingPathComponent("Contents/Info.plist"))
            let executable = url.appendingPathComponent("Contents/MacOS/soffice")
            try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions: runnable ? 0o755 : 0o644], ofItemAtPath: executable.path)
            return url
        }
        let system = root.appendingPathComponent("Applications")
        let user = root.appendingPathComponent("User/Applications")
        let custom = try makeApp(root.appendingPathComponent("My Tools/My Office.app"))
        let standard = try makeApp(system.appendingPathComponent("LibreOffice.app"))
        let personal = try makeApp(user.appendingPathComponent("LibreOffice.app"))
        let exe: (URL) -> URL = { $0.appendingPathComponent("Contents/MacOS/soffice") }
        check("System Applications install is found",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [system], registeredApplication: nil) == exe(standard))
        check("User Applications install is found",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [user], registeredApplication: nil) == exe(personal))
        check("Remembered custom app takes priority",
            LibreOfficeLocator.externalExecutable(customApplication: custom, applicationDirectories: [system, user], registeredApplication: nil) == exe(custom))
        check("Removed custom app falls back to installed app",
            LibreOfficeLocator.externalExecutable(customApplication: root.appendingPathComponent("Gone.app"), applicationDirectories: [user], registeredApplication: nil) == exe(personal))
        check("Renamed app registered with macOS is found",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [], registeredApplication: custom) == exe(custom))
        let nested = try makeApp(root.appendingPathComponent("Old PDF Maker.app/Contents/Resources/ConverterEngine.app"))
        check("Engine inside an older Full app is not mistaken for installed LibreOffice",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [], registeredApplication: nested) == nil)
        let trashed = try makeApp(root.appendingPathComponent(".Trash/LibreOffice.app"))
        check("An app in Trash is ignored",
            LibreOfficeLocator.externalExecutable(customApplication: trashed, applicationDirectories: [], registeredApplication: nil) == nil)
        check("An installer volume is not considered an installation",
            !LibreOfficeLocator.isStandaloneInstallation(URL(fileURLWithPath: "/Volumes/LibreOffice/LibreOffice.app")))
        let wrong = try makeApp(root.appendingPathComponent("Unrelated.app"), identifier: "example.not-libreoffice")
        check("An unrelated app is rejected", LibreOfficeLocator.executable(in: wrong) == nil)
        let broken = try makeApp(root.appendingPathComponent("Broken.app"), runnable: false)
        check("An app without an executable converter is rejected", LibreOfficeLocator.executable(in: broken) == nil)
        let symlink = root.appendingPathComponent("Linked/LibreOffice.app")
        try fm.createDirectory(at: symlink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: symlink, withDestinationURL: custom)
        check("A Homebrew-style application symlink is supported",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [symlink.deletingLastPathComponent()], registeredApplication: nil) == exe(symlink))
        check("No installed app yields no executable",
            LibreOfficeLocator.externalExecutable(customApplication: nil, applicationDirectories: [], registeredApplication: nil) == nil)
        let data = try JSONSerialization.data(withJSONObject: ["checks": passed], options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
