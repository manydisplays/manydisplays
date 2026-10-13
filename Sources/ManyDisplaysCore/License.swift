import Foundation

/// A licence key bought on Lemon Squeezy and activated on this Mac. Lemon Squeezy issues the
/// key with the order, emails it to the buyer, and its public licence API validates it; the app
/// keeps a copy of the answer so it works offline afterwards.
struct LicenseKey: Codable, Equatable {
    let key: String
    let email: String?
    /// End of the update window (the key's `expires_at`); nil means forever.
    let updatesUntil: Date?
    /// "active", "expired", "disabled"…
    let status: String
    /// Lemon Squeezy activation instance on this Mac (needed to deactivate).
    let instanceID: String?
    let validatedAt: Date

    /// Whether a build made on `buildDate` is covered by this licence.
    func covers(buildDate: Date) -> Bool {
        guard status != "disabled" else { return false }
        guard let updatesUntil else { return true }
        return buildDate <= updatesUntil
    }
}

/// What the app may do right now. Pure function of the inputs so it can be tested.
enum LicenseState: Equatable {
    /// Development or source build: no licence needed.
    case free
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(LicenseKey)
    /// Licensed, but this build is newer than the licence's update window (or the key was disabled).
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

/// Lemon Squeezy licence API (https://docs.lemonsqueezy.com/api/license-api). These endpoints
/// need no API key: they only know the licence key itself.
enum LemonSqueezy {
    static let baseURL = URL(string: "https://api.lemonsqueezy.com/v1/licenses/")!
    /// Store and product the key must belong to (0 = not checked). Filled in once the shop exists.
    static let storeID = 0
    static let productID = 0

    enum Error: Swift.Error, Equatable {
        case rejected(String)
        case wrongProduct
        case malformedResponse
    }

    struct Response: Decodable {
        struct Key: Decodable {
            let status: String
            let key: String
            let expires_at: String?
        }

        struct Instance: Decodable { let id: String }
        struct Meta: Decodable {
            let store_id: Int?
            let product_id: Int?
            let customer_email: String?
        }

        let activated: Bool?
        let valid: Bool?
        let error: String?
        let license_key: Key?
        let instance: Instance?
        let meta: Meta?
    }

    static func activate(_ key: String, instanceName: String, session: URLSession = .shared) async throws -> LicenseKey {
        try await parse(
            call("activate", ["license_key": key, "instance_name": instanceName], session: session),
            requestedKey: key
        )
    }

    static func validate(_ license: LicenseKey, session: URLSession = .shared) async throws -> LicenseKey {
        var form = ["license_key": license.key]
        if let id = license.instanceID {
            form["instance_id"] = id
        }
        var fresh = try await parse(call("validate", form, session: session), requestedKey: license.key)
        fresh = LicenseKey(
            key: fresh.key,
            email: fresh.email ?? license.email,
            updatesUntil: fresh.updatesUntil,
            status: fresh.status,
            instanceID: license.instanceID,
            validatedAt: fresh.validatedAt
        )
        return fresh
    }

    static func deactivate(_ license: LicenseKey, session: URLSession = .shared) async throws {
        guard let id = license.instanceID else { return }
        _ = try await call("deactivate", ["license_key": license.key, "instance_id": id], session: session)
    }

    private static func call(_ endpoint: String, _ form: [String: String], session: URLSession) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = form.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await session.data(for: request)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw Error.malformedResponse }
        return response
    }

    /// Turns an API answer into a licence. A key that exists but is expired or disabled is still
    /// returned (with its status), so an old build that it covers keeps working.
    static func parse(_ response: Response, requestedKey: String) throws -> LicenseKey {
        guard let key = response.license_key else {
            throw Error.rejected(response.error ?? "The licence key was not recognised.")
        }
        if let meta = response.meta {
            if storeID != 0, let store = meta.store_id, store != storeID {
                throw Error.wrongProduct
            }
            if productID != 0, let product = meta.product_id, product != productID {
                throw Error.wrongProduct
            }
        }
        if let error = response.error, response.activated != true, response.valid != true,
           key.status != "expired" {
            throw Error.rejected(error)
        }
        return LicenseKey(
            key: key.key.isEmpty ? requestedKey : key.key,
            email: response.meta?.customer_email,
            updatesUntil: key.expires_at.flatMap(Self.date),
            status: key.status,
            instanceID: response.instance?.id,
            validatedAt: Date()
        )
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain = ISO8601DateFormatter()

    static func date(_ s: String) -> Date? {
        iso.date(from: s) ?? isoPlain.date(from: s)
    }
}

/// Licence storage and the app's view of it. Only the official release build asks for a
/// licence (`MDRequiresLicense` in Info.plist, set by scripts/build-app.sh for DMG builds);
/// anything built from source runs free.
final class Licensing {
    static let shared = Licensing()

    static let trialDays = 14
    static let buyURL = URL(string: "https://manydisplays.com/buy")!
    /// A stored licence is checked again with the shop at most this often (quietly, when online).
    static let revalidateInterval: TimeInterval = 7 * 24 * 3600

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var cachedKey: LicenseKey??
    private var revalidating = false

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
        let stored = defaults.data(forKey: "license").flatMap { try? JSONDecoder().decode(LicenseKey.self, from: $0) }
        cachedKey = .some(stored)
        return stored
    }

    var state: LicenseState {
        LicenseState.compute(required: required, key: key, trialStartedAt: trialStartedAt, buildDate: buildDate)
    }

    /// Activates a key with the shop and stores the answer.
    func activate(_ text: String) async throws {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let license = try await LemonSqueezy.activate(key, instanceName: Host.current().localizedName ?? "Mac")
        store(license)
        Log.info("Licence activated (\(license.status)), updates until \(license.updatesUntil.map(Self.string) ?? "forever")")
    }

    func deactivate() async {
        if let key {
            try? await LemonSqueezy.deactivate(key)
        }
        store(nil)
        Log.info("Licence removed")
    }

    /// Re-checks the stored key with the shop now and then (refunded keys get disabled).
    func revalidateIfDue() {
        guard required, let key, !revalidating,
              Date().timeIntervalSince(key.validatedAt) > Self.revalidateInterval else { return }
        revalidating = true
        Task {
            defer { revalidating = false }
            if let fresh = try? await LemonSqueezy.validate(key) {
                store(fresh)
                if fresh.status != key.status {
                    Log.info("Licence status changed to \(fresh.status)")
                }
            }
        }
    }

    private func store(_ license: LicenseKey?) {
        lock.lock()
        if let license, let data = try? JSONEncoder().encode(license) {
            defaults.set(data, forKey: "license")
        } else {
            defaults.removeObject(forKey: "license")
        }
        cachedKey = .some(license)
        lock.unlock()
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
