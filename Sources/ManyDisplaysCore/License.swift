import CryptoKit
import Foundation

/// A purchased licence: a short signed text the user pastes into the app.
///
/// Format: `MD1.<payload>.<signature>`, where payload is base64url of
/// `email|issued|updatesUntil` (dates as YYYY-MM-DD) and signature is base64url of the Ed25519
/// signature of the payload bytes. The app only holds the public key; keys are issued by the
/// shop's backend right after a Stripe checkout (see docs/LICENSING.md), so reading this code
/// does not let anyone forge one. Verification is offline: the app never calls home.
struct LicenseKey: Equatable {
    let email: String
    let issuedAt: Date
    let updatesUntil: Date
    let text: String

    enum Error: Swift.Error, Equatable {
        case malformed
        case badSignature
    }

    static let prefix = "MD1"

    /// Parses and verifies a key against `publicKey` (raw 32 bytes).
    static func verify(_ text: String, publicKey: Data) throws -> LicenseKey {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == prefix,
              let payload = Data(base64URL: String(parts[1])),
              let signature = Data(base64URL: String(parts[2])),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        else { throw Error.malformed }
        guard key.isValidSignature(signature, for: payload) else { throw Error.badSignature }
        guard let fields = String(data: payload, encoding: .utf8)?.split(separator: "|", omittingEmptySubsequences: false),
              fields.count == 3, let issued = Licensing.day(String(fields[1])), let until = Licensing.day(String(fields[2]))
        else { throw Error.malformed }
        return LicenseKey(email: String(fields[0]), issuedAt: issued, updatesUntil: until, text: trimmed)
    }

    /// Issues a key (the tests and scripts/license-tool.swift; the shop does the same in JS).
    static func issue(email: String, issuedAt: Date, updatesUntil: Date, privateKey: Data) throws -> String {
        let signing = try Curve25519.Signing.PrivateKey(rawRepresentation: privateKey)
        let payload = Data("\(email)|\(Licensing.string(issuedAt))|\(Licensing.string(updatesUntil))".utf8)
        let signature = try signing.signature(for: payload)
        return "\(prefix).\(payload.base64URL).\(signature.base64URL)"
    }

    /// Whether a build made on `buildDate` is covered by this licence.
    func covers(buildDate: Date) -> Bool {
        buildDate <= updatesUntil
    }
}

extension Data {
    init?(base64URL: String) {
        var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 {
            s += "="
        }
        self.init(base64Encoded: s)
    }

    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// What the app may do right now. Pure function of the inputs so it can be tested.
enum LicenseState: Equatable {
    /// Development or source build: no licence needed.
    case free
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(LicenseKey)
    /// Licensed, but this build is newer than the licence's update window.
    case updatesExpired(LicenseKey)

    var allowsRestoring: Bool {
        switch self {
        case .free, .trial, .licensed: true
        case .trialExpired, .updatesExpired: false
        }
    }

    static func compute(
        required: Bool,
        key: LicenseKey?,
        trialStartedAt: Date,
        buildDate: Date,
        now: Date = Date(),
        trialDays: Int = Licensing.trialDays
    ) -> LicenseState {
        guard required else { return .free }
        if let key {
            return key.covers(buildDate: buildDate) ? .licensed(key) : .updatesExpired(key)
        }
        let elapsed = Calendar(identifier: .gregorian).dateComponents([.day], from: trialStartedAt, to: now).day ?? 0
        let left = trialDays - elapsed
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }
}

/// Licence storage and the app's view of it. Only the official release build asks for a
/// licence (`MDRequiresLicense` in Info.plist, set by scripts/build-app.sh for DMG builds);
/// anything built from source runs free.
final class Licensing {
    static let shared = Licensing()

    static let trialDays = 14
    static let buyURL = URL(string: "https://manydisplays.com/buy")!
    /// Ed25519 public key of the shop (raw, base64). The private half lives only in the shop.
    static let publicKeyBase64 = "fatp+ja23VTv6hu2oBNuY8lwSZYopvm2tW5QtpCAFEc="

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var cachedKey: LicenseKey??

    var onChange: (() -> Void)?

    var required: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "MDRequiresLicense") as? Bool) ?? false
    }

    /// Day this build was made (set by the release script); today for development builds.
    var buildDate: Date {
        (Bundle.main.object(forInfoDictionaryKey: "MDBuildDate") as? String).flatMap(Self.day) ?? Date()
    }

    var key: LicenseKey? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cachedKey {
            return cached
        }
        let parsed = defaults.string(forKey: "licenseKey").flatMap { try? LicenseKey.verify($0, publicKey: Self.publicKey) }
        cachedKey = .some(parsed)
        return parsed
    }

    var state: LicenseState {
        LicenseState.compute(required: required, key: key, trialStartedAt: trialStartedAt, buildDate: buildDate)
    }

    /// Verifies and stores a key. Throws `LicenseKey.Error` when it is not valid.
    func activate(_ text: String) throws {
        let parsed = try LicenseKey.verify(text, publicKey: Self.publicKey)
        lock.lock()
        defaults.set(parsed.text, forKey: "licenseKey")
        cachedKey = .some(parsed)
        lock.unlock()
        Log.info("Licence activated for \(parsed.email), updates until \(Self.string(parsed.updatesUntil))")
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    func deactivate() {
        lock.lock()
        defaults.removeObject(forKey: "licenseKey")
        cachedKey = .some(nil)
        lock.unlock()
        Log.info("Licence removed")
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }

    /// First launch of a licence-requiring build. Kept both in defaults and in the data folder,
    /// and the earliest of the two wins, so reinstalling does not restart the trial.
    var trialStartedAt: Date {
        let fileURL = LayoutStore.directory.appendingPathComponent(".first-launch")
        let fromDefaults = defaults.object(forKey: "trialStartedAt") as? Date
        let fromFile = (try? String(contentsOf: fileURL, encoding: .utf8))
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .map { Date(timeIntervalSince1970: $0) }
        let earliest = [fromDefaults, fromFile].compactMap { $0 }.min() ?? Date()
        if fromDefaults == nil {
            defaults.set(earliest, forKey: "trialStartedAt")
        }
        if fromFile == nil {
            try? String(earliest.timeIntervalSince1970).write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return earliest
    }

    static var publicKey: Data {
        Data(base64Encoded: publicKeyBase64) ?? Data()
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func day(_ s: String) -> Date? {
        dayFormatter.date(from: s)
    }

    static func string(_ d: Date) -> String {
        dayFormatter.string(from: d)
    }
}
