import Foundation

@MainActor
final class PlatformBridgeRuntime {
    static let shared = PlatformBridgeRuntime()

    private(set) var isStarting = false
    private(set) var lastError: String?
    private var process: Process?

    private init() {}

    func ensureRunning() async -> Result<Void, Error> {
        if await isReachable() {
            lastError = nil
            return .success(())
        }
        if isStarting {
            // The account panel can ask for the status several times while the
            // first launch is still booting. Wait for that launch instead of
            // making the second caller report a false failure.
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if await isReachable() {
                    lastError = nil
                    return .success(())
                }
                if !isStarting { break }
            }
            if isStarting {
                return .failure(BridgeRuntimeError.starting)
            }
        }

        guard let bridgeRoot = locateBridgeRoot() else {
            let error = BridgeRuntimeError.notFound
            lastError = error.localizedDescription
            return .failure(error)
        }
        guard let runtime = locateRuntime(in: bridgeRoot) else {
            let error = BridgeRuntimeError.runtimeNotFound
            lastError = error.localizedDescription
            return .failure(error)
        }

        isStarting = true
        defer { isStarting = false }
        let child = Process()
        child.executableURL = runtime.executable
        child.arguments = ["server.js"]
        child.currentDirectoryURL = bridgeRoot
        var environment = ProcessInfo.processInfo.environment
        environment["HOST"] = "127.0.0.1"
        environment["PORT"] = "3000"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioSampleBuffer", isDirectory: true)
            .appendingPathComponent("PlatformCredentials", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        environment["COOKIE_FILE"] = support.appendingPathComponent("netease.cookie").path
        environment["QQ_COOKIE_FILE"] = support.appendingPathComponent("qq.cookie").path
        environment["KUGOU_COOKIE_FILE"] = support.appendingPathComponent("kugou.cookie").path
        environment["QISHUI_COOKIE_FILE"] = support.appendingPathComponent("qishui.cookie").path
        environment["QISHUI_QR_CONFIG_FILE"] = support.appendingPathComponent("qishui-qr.json").path
        child.environment = environment

        // Keep a small persistent log. The Bridge is a separate Node process,
        // so without this file an Xcode launch only exposed a generic
        // connection-refused error and hid missing-runtime/module failures.
        let logURL = support.deletingLastPathComponent().appendingPathComponent("bridge.log")
        try? FileManager.default.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()
        child.standardOutput = logHandle ?? FileHandle.nullDevice
        child.standardError = logHandle ?? FileHandle.nullDevice
        do {
            try child.run()
        } catch {
            let detail = "\(error.localizedDescription)；日志：\(logURL.path)"
            lastError = "Bridge 启动失败：\(detail)"
            return .failure(error)
        }
        process = child

        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 200_000_000)
            if await isReachable() {
                lastError = nil
                return .success(())
            }
            if !child.isRunning { break }
        }

        let detail: String
        if child.isRunning {
            detail = "启动超时；运行时：\(runtime.executable.path)；资源：\(bridgeRoot.path)；日志：\(logURL.path)"
        } else {
            detail = "进程已退出；运行时：\(runtime.executable.path)；资源：\(bridgeRoot.path)；日志：\(logURL.path)"
        }
        let error = BridgeRuntimeError.failed(detail)
        lastError = error.localizedDescription
        process = nil
        return .failure(error)
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
    }

    private func isReachable() async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:3000/api/login/status") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func locateBridgeRoot() -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let configured = ProcessInfo.processInfo.environment["MINERADIO_BRIDGE_PATH"], !configured.isEmpty {
            candidates.append(URL(fileURLWithPath: configured))
        }
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("MineradioBridge"))
            candidates.append(resource.appendingPathComponent("Bridge"))
        }
        let bundleURL = Bundle.main.bundleURL
        candidates.append(bundleURL.appendingPathComponent("MacDesktopPlayer_MacDesktopPlayer.bundle/Bridge"))
        candidates.append(bundleURL.appendingPathComponent("Contents/Resources/MineradioBridge"))
        candidates.append(bundleURL.appendingPathComponent("Contents/Resources/Bridge"))
        // When launched directly by Xcode, Bundle.main can resolve differently
        // for an app without a document scene. Resolve from the executable too.
        if let executable = Bundle.main.executableURL {
            let resources = executable
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Resources")
            candidates.append(resources.appendingPathComponent("Bridge"))
            candidates.append(resources.appendingPathComponent("MineradioBridge"))
        }
        candidates.append(URL(fileURLWithPath: "/tmp/mrrepo.4Gdw5d"))

        return candidates.first { candidate in
            fileManager.fileExists(atPath: candidate.appendingPathComponent("server.js").path)
                && fileManager.fileExists(atPath: candidate.appendingPathComponent("package.json").path)
        }
    }

    private func locateRuntime(in bridgeRoot: URL) -> BridgeRuntimeExecutable? {
        let fileManager = FileManager.default
        // Mineradio's Bridge imports Electron for its official QR-login module,
        // so prefer the Electron runtime when it is available. Plain Node is
        // kept as a fallback for a bridge build with that module removed.
        let electronCandidates = [
            bridgeRoot.appendingPathComponent("node_modules/electron/dist/Electron.app/Contents/MacOS/Electron"),
            URL(fileURLWithPath: "/opt/homebrew/bin/electron"),
            URL(fileURLWithPath: "/usr/local/bin/electron")
        ]
        if let electron = electronCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }) {
            return BridgeRuntimeExecutable(executable: electron)
        }
        let nodeCandidates = [
            bridgeRoot.appendingPathComponent("runtime/node").path,
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node"
        ]
        guard let node = nodeCandidates.lazy.map(URL.init(fileURLWithPath:)).first(where: {
            fileManager.isExecutableFile(atPath: $0.path)
        }) else { return nil }
        return BridgeRuntimeExecutable(executable: node)
    }
}

private struct BridgeRuntimeExecutable {
    let executable: URL
}

private enum BridgeRuntimeError: LocalizedError {
    case notFound
    case runtimeNotFound
    case starting
    case failed(String?)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "未找到 Mineradio Bridge。请设置 MINERADIO_BRIDGE_PATH，或把 Bridge 放入 App 的 Resources/MineradioBridge。"
        case .runtimeNotFound:
            return "未找到 Bridge 运行时。请安装 Node.js；如果使用 Mineradio 原版 Bridge，还需要 Electron 依赖。"
        case .starting:
            return "Bridge 正在启动，请稍候再刷新。"
        case .failed(let detail):
            return detail?.isEmpty == false ? "Bridge 启动失败：\(detail!)" : "Bridge 启动失败，请检查 Node.js 依赖是否已安装。"
        }
    }
}
