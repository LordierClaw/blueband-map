import Foundation
import BlueBandMapCore

final class FileRenderRunStore {
    enum Error: Swift.Error, Equatable {
        case invalidRoot
    }

    private let fileManager: FileManager
    private let rootURL: URL

    init(rootURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.rootURL = rootURL ?? applicationSupport
            .appendingPathComponent("BlueBandMap", isDirectory: true)
            .appendingPathComponent("test-runs", isDirectory: true)
    }

    func save(_ record: RenderRunRecord, previewPNG: Data? = nil) throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let directory = rootURL.appendingPathComponent(directoryName(for: record), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try record.identityData().write(to: directory.appendingPathComponent("run.json"), options: .atomic)
        try record.eventsJSONLData().write(to: directory.appendingPathComponent("events.jsonl"), options: .atomic)
        try record.metricsData().write(to: directory.appendingPathComponent("metrics.json"), options: .atomic)
        try Data((record.payloadSHA256 + "\n").utf8)
            .write(to: directory.appendingPathComponent("payload.sha256"), options: .atomic)
        if let previewPNG {
            try previewPNG.write(to: directory.appendingPathComponent("preview.png"), options: .atomic)
        }
        return directory
    }

    func export(_ record: RenderRunRecord) throws -> URL {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let url = rootURL.appendingPathComponent("h1-run-\(safeComponent(record.identity.runID)).json")
        try record.sanitizedExportData().write(to: url, options: .atomic)
        return url
    }

    private func directoryName(for record: RenderRunRecord) -> String {
        "\(safeComponent(record.identity.startedAt))-\(safeComponent(record.identity.runID))-\(record.identity.renderer.rawValue)"
    }

    private func safeComponent(_ value: String) -> String {
        String(value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_" ? character : "_"
        })
    }
}
