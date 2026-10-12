import Foundation
import os

// Pilote yt-dlp : localise/installe le binaire, lance le téléchargement, relaie
// progression et résultat. Le binaire est livré dans le bundle (signé, en lecture
// seule) ; on le copie dans Application Support pour pouvoir le mettre à jour.
enum VideoEngineError: LocalizedError {
    case binaryUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .binaryUnavailable: return "yt-dlp unavailable"
        case .failed(let m): return m
        }
    }
}

final class VideoEngine: @unchecked Sendable {
    static let shared = VideoEngine()

    // Consultable avec : log show --last 10m --predicate 'subsystem == "com.cubby.app"'
    private let log = Logger(subsystem: "com.cubby.app", category: "video")
    private let fm = FileManager.default
    private let lock = NSLock()
    private var process: Process?

    private var binDir: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cubby/bin", isDirectory: true)
    }
    private var ytdlp: URL { binDir.appendingPathComponent("yt-dlp") }
    private let updateStampKey = "cubby.video.lastUpdate"

    // Les apps lancées hors terminal n'ont pas le PATH de Homebrew.
    private var ffmpegDir: URL? {
        [binDir.path, "/opt/homebrew/bin", "/usr/local/bin"]
            .first { fm.isExecutableFile(atPath: $0 + "/ffmpeg") }
            .map { URL(fileURLWithPath: $0) }
    }

    var downloadsDir: URL { fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    // MARK: - Binaire

    private func ensureBinary() async throws {
        if fm.isExecutableFile(atPath: ytdlp.path) { return }
        try fm.createDirectory(at: binDir, withIntermediateDirectories: true)
        if let bundled = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) {
            try fm.copyItem(at: bundled, to: ytdlp)
        } else {
            // build de dev (swift run) : pas de binaire embarqué → on le récupère.
            let remote = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
            let (tmp, resp) = try await URLSession.shared.download(from: remote)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw VideoEngineError.binaryUnavailable }
            try fm.moveItem(at: tmp, to: ytdlp)
        }
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ytdlp.path)
    }

    // Les sites cassent yt-dlp en quelques jours : on se met à jour au plus 1×/jour.
    // Échec silencieux — le binaire en place reste utilisable.
    func updateIfStale() async {
        let last = UserDefaults.standard.object(forKey: updateStampKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 86_400, (try? await ensureBinary()) != nil else { return }
        _ = try? await run(["-U"], onLine: { _ in })
        UserDefaults.standard.set(Date(), forKey: updateStampKey)
    }

    // MARK: - Téléchargement

    /// Télécharge `url` en mp4 dans Téléchargements. `onProgress` reçoit 0…1.
    func download(_ url: URL, cookiesFrom browser: String? = nil, onProgress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try await ensureBinary()
        let format = ffmpegDir != nil
            ? "bv*[vcodec^=avc1][ext=mp4]+ba[ext=m4a]/bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/b"   // H.264 d'abord : lisible partout
            : "b[ext=mp4]/b"                      // sans ffmpeg : flux déjà combiné uniquement
        var args = [
            "-f", format, "--merge-output-format", "mp4",
            // --print rend yt-dlp muet : sans --no-quiet --progress, plus aucune ligne de progression.
            "--newline", "--no-quiet", "--progress", "--no-playlist", "--no-mtime",
            "--print", "after_move:\(YTDLPLine.finishedPrefix)%(filepath)s",
            "-o", downloadsDir.appendingPathComponent("%(title).80B [%(id)s].%(ext)s").path,
        ]
        if let dir = ffmpegDir { args += ["--ffmpeg-location", dir.path] }
        args += VideoBrowser.cookieArgs(for: browser)
        args.append(url.absoluteString)

        let finalPath = LockedString()
        let stderr = try await run(args) { line in
            switch YTDLPLine.parse(line) {
            case .progress(let p): onProgress(p)
            case .finished(let path): finalPath.set(path)
            case .other: break
            }
        }
        let path = finalPath.value
        guard !path.isEmpty, fm.fileExists(atPath: path) else {
            throw VideoEngineError.failed(YTDLPLine.errorMessage(from: stderr) ?? "Download failed")
        }
        return URL(fileURLWithPath: path)
    }

    func cancel() {
        lock.lock(); defer { lock.unlock() }
        process?.terminate()
    }

    // MARK: - Process

    // Retourne stderr. Lève CancellationError si le process a été terminé par cancel().
    private func run(_ args: [String], onLine: @escaping @Sendable (String) -> Void) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = ytdlp
            p.arguments = args
            let out = Pipe(), err = Pipe()
            p.standardOutput = out
            p.standardError = err

            let errBuf = LockedString()
            err.fileHandleForReading.readabilityHandler = { h in
                errBuf.append(String(decoding: h.availableData, as: UTF8.self))
            }
            // yt-dlp sépare ses mises à jour par \n (--newline) : on découpe ligne à ligne.
            let outBuf = LockedString()
            out.fileHandleForReading.readabilityHandler = { h in
                for l in outBuf.appendReturningLines(String(decoding: h.availableData, as: UTF8.self)) { onLine(l) }
            }
            log.info("yt-dlp start: \(args.joined(separator: " "), privacy: .public)")
            p.terminationHandler = { [weak self, log] proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                // vide ce qu'il reste dans le tube avant de conclure
                let rest = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                for l in rest.split(whereSeparator: \.isNewline) { onLine(String(l)) }
                log.info("yt-dlp exit \(proc.terminationStatus) reason \(proc.terminationReason.rawValue)\n\(errBuf.value, privacy: .public)")
                self?.lock.lock(); self?.process = nil; self?.lock.unlock()
                if proc.terminationReason == .uncaughtSignal {
                    cont.resume(throwing: CancellationError())
                } else {
                    cont.resume(returning: errBuf.value)
                }
            }
            do {
                lock.lock(); process = p; lock.unlock()
                try p.run()
            } catch {
                log.error("yt-dlp launch failed: \(error.localizedDescription, privacy: .public)")
                cont.resume(throwing: error)
            }
        }
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var s = ""
    func append(_ t: String) { lock.lock(); s += t; lock.unlock() }
    func set(_ t: String) { lock.lock(); s = t; lock.unlock() }
    // Ajoute un fragment et rend les lignes complètes ; le reste attend le prochain fragment.
    func appendReturningLines(_ t: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        s += t
        var lines: [String] = []
        while let nl = s.firstIndex(of: "\n") {
            lines.append(String(s[..<nl]))
            s.removeSubrange(...nl)
        }
        return lines
    }
    var value: String { lock.lock(); defer { lock.unlock() }; return s }
}
