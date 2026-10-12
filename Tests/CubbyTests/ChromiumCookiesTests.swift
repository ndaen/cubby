import XCTest
import CommonCrypto
import CryptoKit
import SQLite3
@testable import Cubby

final class ChromiumCookiesTests: XCTestCase {
    private let password = Data("test-keychain-password".utf8)
    private var key: Data { ChromiumCookies.deriveKey(password: password)! }

    // Chiffre comme Chromium sur macOS (v10, AES-128-CBC, IV = 16 espaces).
    private func encrypt(_ plain: Data, key: Data) -> Data {
        let iv = [UInt8](repeating: 0x20, count: 16)
        var out = Data(count: plain.count + 16)
        var written = 0
        let status = out.withUnsafeMutableBytes { o in
            plain.withUnsafeBytes { p in
                key.withUnsafeBytes { k in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            k.baseAddress, 16, iv, p.baseAddress, plain.count, o.baseAddress, o.count, &written)
                }
            }
        }
        XCTAssertEqual(status, CCCryptorStatus(kCCSuccess))
        return Data("v10".utf8) + out.prefix(written)
    }

    private func makeDB(rows: [(host: String, name: String, value: String, enc: Data?, secure: Bool, httpOnly: Bool, expires: Int64)]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).db")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE cookies (host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER, is_secure INTEGER, is_httponly INTEGER)", nil, nil, nil)
        for r in rows {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO cookies VALUES (?,?,?,?,'/',?,?,?)", -1, &stmt, nil)
            let t = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(stmt, 1, r.host, -1, t); sqlite3_bind_text(stmt, 2, r.name, -1, t)
            sqlite3_bind_text(stmt, 3, r.value, -1, t)
            if let e = r.enc { _ = e.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(e.count), t) } }
            else { sqlite3_bind_blob(stmt, 4, nil, 0, t) }
            sqlite3_bind_int64(stmt, 5, r.expires); sqlite3_bind_int(stmt, 6, r.secure ? 1 : 0); sqlite3_bind_int(stmt, 7, r.httpOnly ? 1 : 0)
            sqlite3_step(stmt); sqlite3_finalize(stmt)
        }
        return url
    }

    func testDecryptRoundTripWithoutHashPrefix() {
        let enc = encrypt(Data("secret-token".utf8), key: key)
        XCTAssertEqual(ChromiumCookies.decrypt(enc, key: key, hostKey: ".x.com"), "secret-token")
    }

    // Chromium récent préfixe le clair du SHA-256 du host_key : il doit disparaître.
    func testDecryptStripsHostHashPrefix() {
        let hash = Data(SHA256.hash(data: Data(".x.com".utf8)))
        let enc = encrypt(hash + Data("secret-token".utf8), key: key)
        XCTAssertEqual(ChromiumCookies.decrypt(enc, key: key, hostKey: ".x.com"), "secret-token")
    }

    func testDecryptFailsWithWrongKeyOrFormat() {
        let enc = encrypt(Data("v".utf8), key: key)
        let other = ChromiumCookies.deriveKey(password: Data("autre".utf8))!
        // Mauvaise clé : le padding est valide 1 fois sur ~256 par hasard (déchet), d'où
        // « jamais la vraie valeur » plutôt que « nil ».
        XCTAssertNotEqual(ChromiumCookies.decrypt(enc, key: other, hostKey: ".x.com"), "v")
        XCTAssertNil(ChromiumCookies.decrypt(Data("v11xxxxxxxxxxxxxxxxxxxxxxxx".utf8), key: key, hostKey: ".x.com"))
        XCTAssertNil(ChromiumCookies.decrypt(Data(), key: key, hostKey: ".x.com"))
    }

    func testDomainsForHost() {
        XCTAssertEqual(ChromiumCookies.domains(forHost: "x.com"), ["x.com", "twitter.com"])
        XCTAssertEqual(ChromiumCookies.domains(forHost: "twitter.com"), ["x.com", "twitter.com"])
        XCTAssertEqual(ChromiumCookies.domains(forHost: "www.instagram.com"), ["instagram.com", "www.instagram.com"])
        XCTAssertEqual(ChromiumCookies.domains(forHost: "facebook.com"), ["facebook.com"])
    }

    func testExportFiltersByDomainAndFormatsNetscape() throws {
        let hash = Data(SHA256.hash(data: Data(".x.com".utf8)))
        let db = try makeDB(rows: [
            (".x.com", "auth_token", "", encrypt(hash + Data("TOKEN123".utf8), key: key), true, true, 13_400_000_000_000_000),
            ("x.com", "lang", "fr", nil, false, false, 0),                       // valeur en clair, session
            (".twitter.com", "ct0", "", encrypt(Data("CSRF".utf8), key: key), true, false, 0),
            (".bank.example", "sid", "", encrypt(Data("DO-NOT-LEAK".utf8), key: key), true, true, 0),  // autre site
            (".x.com", "broken", "", Data("v10garbage-garbage-garbage".utf8), false, false, 0),
        ])
        defer { try? FileManager.default.removeItem(at: db) }

        let r = try ChromiumCookies.export(database: db, key: key, domains: ["x.com", "twitter.com"])
        XCTAssertEqual(r.exported, 3)
        XCTAssertEqual(r.undecryptable, 1)
        XCTAssertFalse(r.netscape.contains("DO-NOT-LEAK"), "un cookie d'un autre site ne doit jamais sortir")
        XCTAssertFalse(r.netscape.contains("sid"))

        let lines = r.netscape.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "# Netscape HTTP Cookie File")
        // 13_400_000_000_000_000 µs depuis 1601 → 13_400_000_000 − 11_644_473_600 = 1_755_526_400 s
        XCTAssertTrue(lines.contains("#HttpOnly_.x.com\tTRUE\t/\tTRUE\t1755526400\tauth_token\tTOKEN123"))
        XCTAssertTrue(lines.contains("x.com\tFALSE\t/\tFALSE\t0\tlang\tfr"))
        XCTAssertTrue(lines.contains(".twitter.com\tTRUE\t/\tTRUE\t0\tct0\tCSRF"))
    }

    func testTemporaryFileIsOwnerOnly() throws {
        let url = try ChromiumCookies.writeTemporary("x")
        defer { try? FileManager.default.removeItem(at: url) }
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }
}
