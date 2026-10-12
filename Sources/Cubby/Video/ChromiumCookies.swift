import Foundation
import CommonCrypto
import CryptoKit
import SQLite3
import Security
import os

// Export de cookies d'un navigateur Chromium que yt-dlp ne sait pas lire (Arc : sa clé de
// chiffrement est sous « Arc Safe Storage », yt-dlp ne cherche que « Chromium Safe Storage »).
// On déchiffre nous-mêmes, uniquement pour le site du lien, vers un fichier Netscape
// temporaire passé à `--cookies`. Jamais de nom ni de valeur dans les logs.
enum CookieExportError: Error {
    case keychainDenied        // l'utilisateur a refusé l'accès à la clé
    case keyNotFound           // navigateur jamais lancé / pas de clé
    case profileNotFound       // pas de base de cookies
    case noCookiesForSite      // aucun profil n'a de cookie pour ce site (pas connecté)
    case readFailed
}

enum ChromiumCookies {
    private static let log = Logger(subsystem: "com.cubby.app", category: "cookies")

    // MARK: - Domaines

    // Domaines dont on exporte les cookies pour un lien. X répond aussi sous twitter.com.
    static func domains(forHost host: String) -> [String] {
        let h = host.lowercased()
        let labels = h.split(separator: ".")
        let base = labels.count >= 2 ? labels.suffix(2).joined(separator: ".") : h
        var out = [base]
        if base == "x.com" || base == "twitter.com" { out = ["x.com", "twitter.com"] }
        if h != base, !out.contains(h) { out.append(h) }
        return out
    }

    // MARK: - Déchiffrement (schéma « v10 » de macOS)

    // AES-128-CBC, clé = PBKDF2-HMAC-SHA1(mot de passe du trousseau, "saltysalt", 1003 tours),
    // IV = 16 espaces. Chromium récent préfixe le clair du SHA-256 du host_key : on l'écarte.
    static func deriveKey(password: Data) -> Data? {
        var key = Data(count: 16)
        let salt = Array("saltysalt".utf8)
        let status = key.withUnsafeMutableBytes { k in
            password.withUnsafeBytes { p in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                     p.bindMemory(to: Int8.self).baseAddress, password.count,
                                     salt, salt.count,
                                     CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                     k.bindMemory(to: UInt8.self).baseAddress, 16)
            }
        }
        return status == kCCSuccess ? key : nil
    }

    static func decrypt(_ encrypted: Data, key: Data, hostKey: String) -> String? {
        guard encrypted.count > 3, encrypted.prefix(3) == Data("v10".utf8) else { return nil }
        let payload = encrypted.dropFirst(3)
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = Data(count: payload.count + 16)
        var written = 0
        let status = out.withUnsafeMutableBytes { o in
            payload.withUnsafeBytes { p in
                key.withUnsafeBytes { k in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, 16, iv, p.baseAddress, payload.count,
                            o.baseAddress, o.count, &written)
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        var plain = out.prefix(written)
        let hostHash = Data(SHA256.hash(data: Data(hostKey.utf8)))
        if plain.count >= 32, plain.prefix(32) == hostHash { plain = plain.dropFirst(32) }
        return String(data: plain, encoding: .utf8)
    }

    // MARK: - Export

    struct Result { let netscape: String; let exported: Int; let undecryptable: Int }

    // Lit une base « Cookies » (copie jetable, la vraie est verrouillée par le navigateur)
    // et rend le contenu au format Netscape, limité aux `domains`.
    static func export(database: URL, key: Data, domains: [String]) throws -> Result {
        var db: OpaquePointer?
        guard sqlite3_open_v2(database.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db); throw CookieExportError.readFailed
        }
        defer { sqlite3_close(db) }

        let wanted = domains.flatMap { [$0, "." + $0] }
        let marks = Array(repeating: "?", count: wanted.count).joined(separator: ",")
        let sql = "SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly " +
                  "FROM cookies WHERE host_key IN (\(marks))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw CookieExportError.readFailed }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, d) in wanted.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), d, -1, transient) }

        var lines = ["# Netscape HTTP Cookie File"]
        var exported = 0, failed = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            let host = text(stmt, 0), name = text(stmt, 1), plainValue = text(stmt, 2), path = text(stmt, 4)
            let expiresUTC = sqlite3_column_int64(stmt, 5)
            let secure = sqlite3_column_int(stmt, 6) != 0, httpOnly = sqlite3_column_int(stmt, 7) != 0

            var value = plainValue
            if value.isEmpty, let blob = sqlite3_column_blob(stmt, 3) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 3)))
                guard let v = decrypt(data, key: key, hostKey: host) else { failed += 1; continue }
                value = v
            }
            // expires_utc : microsecondes depuis 1601 → secondes Unix ; 0 = cookie de session
            let expires = expiresUTC > 0 ? max(expiresUTC / 1_000_000 - 11_644_473_600, 0) : 0
            let domain = (httpOnly ? "#HttpOnly_" : "") + host
            lines.append([domain, host.hasPrefix(".") ? "TRUE" : "FALSE", path, secure ? "TRUE" : "FALSE",
                          String(expires), name, value].joined(separator: "\t"))
            exported += 1
        }
        return Result(netscape: lines.joined(separator: "\n") + "\n", exported: exported, undecryptable: failed)
    }

    private static func text(_ stmt: OpaquePointer?, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    // MARK: - Fichier temporaire

    // Écrit le contenu dans un fichier 0600 du dossier temporaire de l'utilisateur.
    // L'appelant le supprime (voir `VideoEngine.download`).
    static func writeTemporary(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-\(UUID().uuidString).txt")
        guard FileManager.default.createFile(atPath: url.path, contents: Data(content.utf8),
                                             attributes: [.posixPermissions: 0o600]) else {
            throw CookieExportError.readFailed
        }
        return url
    }

    // MARK: - Navigateur Chromium « sur mesure » (Arc)

    struct Flavor { let keychainService: String; let userDataDir: String }
    static let arc = Flavor(keychainService: "Arc Safe Storage", userDataDir: "Arc/User Data")

    // Cookies déchiffrés d'un navigateur Chromium pour les domaines donnés → fichier Netscape.
    // Un navigateur a plusieurs profils (Arc : « Default », « Profile 1 »…) et la connexion au
    // site peut être dans n'importe lequel — pas forcément le plus récent. On examine tous les
    // profils et on garde celui qui a le plus de cookies pour ce site. Jamais de mélange : un
    // `auth_token` d'un compte avec un `ct0` d'un autre ne marcherait pas.
    static func exportFile(flavor: Flavor, domains: [String]) throws -> URL {
        let password = try keychainPassword(service: flavor.keychainService)
        guard let key = deriveKey(password: password) else { throw CookieExportError.readFailed }
        let databases = try cookieDatabases(userData: flavor.userDataDir)

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("cubby-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: work) }

        var best: Result?
        for (n, source) in databases.enumerated() {          // du plus récent au plus ancien
            // copie jetable (+ journaux) : la base d'origine est ouverte par le navigateur
            let copy = work.appendingPathComponent("Cookies-\(n)")
            guard (try? FileManager.default.copyItem(at: source, to: copy)) != nil else { continue }
            for ext in ["-wal", "-shm", "-journal"] {
                let side = URL(fileURLWithPath: source.path + ext)
                if FileManager.default.fileExists(atPath: side.path) {
                    try? FileManager.default.copyItem(at: side, to: URL(fileURLWithPath: copy.path + ext))
                }
            }
            guard let r = try? export(database: copy, key: key, domains: domains) else { continue }
            log.info("profile \(n): \(r.exported) cookies ok, \(r.undecryptable) undecryptable")
            if r.exported > (best?.exported ?? 0) { best = r }   // égalité → le plus récent gagne
        }
        guard let chosen = best else { throw CookieExportError.noCookiesForSite }
        log.info("cookies exported: \(chosen.exported) ok, domains \(domains.joined(separator: ","), privacy: .public)")
        return try writeTemporary(chosen.netscape)
    }

    // Toutes les bases « Cookies » des profils, la plus récemment modifiée d'abord.
    static func cookieDatabases(userData: String) throws -> [URL] {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(userData, isDirectory: true)
        let profiles = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        func modified(_ u: URL) -> Date {
            (try? u.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        let found = profiles.map { $0.appendingPathComponent("Cookies") }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { modified($0) > modified($1) }
        guard !found.isEmpty else { throw CookieExportError.profileNotFound }
        return found
    }

    // Lecture de la clé via l'API Trousseau DANS Cubby (pas via /usr/bin/security) : macOS
    // affiche son invite au nom de Cubby, et « Toujours autoriser » ne profite qu'à Cubby.
    private static func keychainPassword(service: String) throws -> Data {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                                      kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne]
        var item: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess:
            guard let data = item as? Data else { throw CookieExportError.readFailed }
            return data
        case errSecItemNotFound: throw CookieExportError.keyNotFound
        default: throw CookieExportError.keychainDenied     // refus, annulation, trousseau verrouillé
        }
    }
}
