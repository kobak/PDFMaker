import Foundation
import PDFKit
import Darwin

struct ConversionResult: Codable {
    let input: String
    let output: String?
    let pages: Int?
    let error: String?
}

enum ConversionError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

/// A UI and the command-line verification path use exactly the same converter.
struct Converter {
    let engineURL: URL?
    let usesBundledEngine: Bool
    let timeout: TimeInterval

    init(bundle: Bundle = .main, timeout: TimeInterval = 90, applicationURL: URL? = nil) {
        engineURL = LibreOfficeLocator.current(in: bundle, overrideApplication: applicationURL)
        usesBundledEngine = LibreOfficeLocator.usesBundledEngine(in: bundle)
        self.timeout = timeout
    }

    func convert(_ source: URL) throws -> (url: URL, pages: Int) {
        let fm = FileManager.default
        guard source.isFileURL, ["doc", "docx"].contains(source.pathExtension.lowercased()) else {
            throw ConversionError.message(L("error.file_type"))
        }
        guard let properties = try? source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
            throw ConversionError.message(L("error.unreadable"))
        }
        guard properties.isRegularFile == true, (properties.fileSize ?? 0) > 0 else {
            throw ConversionError.message(L("error.empty"))
        }
        guard let handle = try? FileHandle(forReadingFrom: source) else {
            throw ConversionError.message(L("error.unreadable"))
        }
        let signature = try handle.read(upToCount: 8) ?? Data()
        try handle.close()
        let isOLE = signature.starts(with: [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
        let isZIP = signature.starts(with: [0x50, 0x4B, 0x03, 0x04])
        let isRTF = signature.starts(with: Array("{\\rtf".utf8))
        guard isOLE || (source.pathExtension.lowercased() == "docx" ? isZIP : isRTF) else {
            throw ConversionError.message(L("error.invalid"))
        }
        guard let engineURL, fm.isExecutableFile(atPath: engineURL.path) else {
            throw ConversionError.message(L(usesBundledEngine ? "error.bundled_engine_missing" : "error.engine_missing"))
        }

        let workspace = fm.temporaryDirectory.appendingPathComponent("pdf-keszito-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workspace, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: workspace) }
        let outputFolder = workspace.appendingPathComponent("output", isDirectory: true)
        let profile = workspace.appendingPathComponent("profile", isDirectory: true)
        let user = profile.appendingPathComponent("user", isDirectory: true)
        try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: user, withIntermediateDirectories: true)
        // Each conversion has an isolated profile; document macros never run.
        let settings = """
        <?xml version="1.0" encoding="UTF-8"?>
        <oor:items xmlns:oor="http://openoffice.org/2001/registry">
          <item oor:path="/org.openoffice.Office.Common/Security/Scripting">
            <prop oor:name="MacroSecurityLevel" oor:op="fuse"><value>3</value></prop>
          </item>
          <item oor:path="/org.openoffice.Office.Writer/Content/Update">
            <prop oor:name="Link" oor:op="fuse"><value>0</value></prop>
          </item>
          <item oor:path="/org.openoffice.Office.Jobs/Jobs/org.openoffice.Office.Jobs:Job['UpdateCheck']/Arguments">
            <prop oor:name="AutoCheckEnabled" oor:op="fuse"><value>false</value></prop>
            <prop oor:name="AutoDownloadEnabled" oor:op="fuse"><value>false</value></prop>
          </item>
        </oor:items>
        """
        try settings.write(to: user.appendingPathComponent("registrymodifications.xcu"), atomically: true, encoding: .utf8)

        let logURL = workspace.appendingPathComponent("conversion.log")
        fm.createFile(atPath: logURL.path, contents: nil)
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        let task = Process()
        task.executableURL = engineURL
        task.arguments = ["-env:UserInstallation=\(profile.absoluteString)",
                          "--headless", "--nologo", "--nodefault", "--norestore",
                          "--convert-to", "pdf:writer_pdf_Export", "--outdir", outputFolder.path, source.path]
        task.standardOutput = log
        task.standardError = log
        task.standardInput = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        environment["SAL_USE_VCLPLUGIN"] = "svp"
        // The embedded engine must not depend on the caller's library overrides.
        for key in Array(environment.keys) where key.hasPrefix("DYLD_") { environment.removeValue(forKey: key) }
        task.environment = environment
        let completed = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in completed.signal() }
        do { try task.run() } catch {
            throw ConversionError.message(L("error.engine_start"))
        }
        if completed.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            if completed.wait(timeout: .now() + 2) == .timedOut {
                kill(task.processIdentifier, SIGKILL)
                task.waitUntilExit()
            }
            throw ConversionError.message(L("error.timeout"))
        }
        task.waitUntilExit()
        let generated = outputFolder.appendingPathComponent(source.deletingPathExtension().lastPathComponent + ".pdf")
        guard task.terminationStatus == 0,
              let pdf = PDFDocument(url: generated), !pdf.isLocked, pdf.pageCount > 0 else {
            throw ConversionError.message(L("error.conversion"))
        }
        let pages = pdf.pageCount
        let stem = source.deletingPathExtension().lastPathComponent
        let parent = source.deletingLastPathComponent()
        // copyItem fails if another process has already created the target.
        // Never remove or overwrite an existing file, including a symlink.
        for index in 0..<10000 {
            let name = index == 0 ? "\(stem).pdf" : "\(stem) (\(index + 1)).pdf"
            let destination = parent.appendingPathComponent(name)
            do {
                try fm.copyItem(at: generated, to: destination)
                return (destination, pages)
            } catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
                throw ConversionError.message(L("error.save", error.localizedDescription))
            }
        }
        throw ConversionError.message(L("error.too_many"))
    }
}
