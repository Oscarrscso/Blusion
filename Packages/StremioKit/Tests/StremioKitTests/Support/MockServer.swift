import Foundation
@testable import StremioKit

/// Gives tests a running mock addon. Uses the one `verify.sh` started (MOCK_ADDON_CATALOG_URL / MOCK_ADDON_STREAM_URL) when present,
/// otherwise spawns `node Tools/MockAddon/server.js` on free ports and lets it die with the test process (`--watch-stdin`).
final class MockServer: @unchecked Sendable {
    struct LaunchError: Error, CustomStringConvertible { let description: String }

    let catalog: URL
    let stream: URL
    /// How long `flag-slow` takes on this server.
    let slowDelay: TimeInterval
    private let process: Process?
    private let stdin: Pipe?

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: MockServer?

    private init(catalog: URL, stream: URL, slowDelay: TimeInterval, process: Process?, stdin: Pipe?) {
        self.catalog = catalog
        self.stream = stream
        self.slowDelay = slowDelay
        self.process = process
        self.stdin = stdin
    }

    static func shared() throws -> MockServer {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let server = try launch()
        cached = server
        return server
    }

    private static func launch() throws -> MockServer {
        let env = ProcessInfo.processInfo.environment
        if let c = env["MOCK_ADDON_CATALOG_URL"], let s = env["MOCK_ADDON_STREAM_URL"], let catalog = URL(string: c), let stream = URL(string: s) {
            let delay = (Double(env["MOCK_DELAY_MS"] ?? "") ?? 3000) / 1000
            return MockServer(catalog: catalog, stream: stream, slowDelay: delay, process: nil, stdin: nil)
        }

        // …/Packages/StremioKit/Tests/StremioKitTests/Support/MockServer.swift -> repo root is five levels up.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let script = root.appendingPathComponent("Tools/MockAddon/server.js")
        guard FileManager.default.fileExists(atPath: script.path) else { throw LaunchError(description: "mock server script not found at \(script.path)") }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path, "--catalog-port", "0", "--stream-port", "0", "--watch-stdin"]
        var childEnv = env
        childEnv["MOCK_DELAY_MS"] = "1200"
        process.environment = childEnv
        let out = Pipe()
        let input = Pipe()
        process.standardOutput = out
        process.standardInput = input
        process.standardError = FileHandle.standardError
        try process.run()

        var buffer = Data()
        while !buffer.contains(UInt8(ascii: "\n")) {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { throw LaunchError(description: "mock server exited before it was ready") }
            buffer.append(chunk)
        }
        guard let line = buffer.split(separator: UInt8(ascii: "\n")).first,
              let json = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let c = json["catalog"] as? String, let s = json["stream"] as? String,
              let catalog = URL(string: c), let stream = URL(string: s) else { throw LaunchError(description: "unexpected mock server output") }
        return MockServer(catalog: catalog, stream: stream, slowDelay: 1.2, process: process, stdin: input)
    }

    /// `<origin>/flag-a/flag-b/<token>`; flags switch on misbehaviour, the token stands in for a user secret.
    func catalogBase(flags: [String] = [], token: String? = nil) -> URL { url(catalog, flags: flags, token: token) }

    func streamBase(flags: [String] = [], token: String? = nil) -> URL { url(stream, flags: flags, token: token) }

    func catalogManifestURL(flags: [String] = [], token: String? = nil) -> URL {
        catalogBase(flags: flags, token: token).appendingPathComponent("manifest.json")
    }

    func streamManifestURL(flags: [String] = [], token: String? = nil) -> URL {
        streamBase(flags: flags, token: token).appendingPathComponent("manifest.json")
    }

    private func url(_ origin: URL, flags: [String], token: String?) -> URL {
        var url = origin
        for flag in flags { url.appendPathComponent("flag-\(flag)") }
        if let token { url.appendPathComponent(token) }
        return url
    }
}
