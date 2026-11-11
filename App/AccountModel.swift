import Foundation
import Combine
import AuthenticationServices
import CryptoKit
import Security
import UIKit
import WHOOPCore

@MainActor
final class AccountModel: NSObject, ObservableObject, @preconcurrency ASWebAuthenticationPresentationContextProviding {
    @Published var bridgeURL: String
    @Published private(set) var isBusy = false
    @Published private(set) var isLinked = false
    @Published private(set) var status = "Add your configured HTTPS bridge to connect your account."
    @Published private(set) var error: String?
    @Published private(set) var displayName: String?
    private var bearer: String?
    private var linkedBaseURL: URL?
    private var session: ASWebAuthenticationSession?
    private var authID: UUID?
    private var authContinuation: CheckedContinuation<URL, Error>?
    private var authAnchor: UIWindow?
    private let defaultsKey = "whoop.account.bridgeURL"
    private let transport: URLSession

    override init() {
        bridgeURL = UserDefaults.standard.string(forKey: "whoop.account.bridgeURL") ?? ""
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 60
        transport = URLSession(configuration: config, delegate: AccountRedirectGuard(), delegateQueue: nil)
        super.init()
        if let url = try? validatedBaseURL() {
            do {
                bearer = try AccountKeychain.read(for: url)
                isLinked = bearer != nil
                if isLinked { linkedBaseURL = url }
                if isLinked { status = "Account connected. Sync to read your recent WHOOP scores." }
            } catch { self.error = "The saved account session is unavailable. Unlock your iPhone and try again." }
        }
    }

    func connect() async throws {
        guard !isBusy, !isLinked else { throw AccountProblem.busy }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let base = try validatedBaseURL()
            let health: Health = try await request(base, path: "health", method: "GET")
            guard health.service == "whoop-local-bridge", health.version == 1 else { throw AccountProblem.invalidServer }
            guard health.configured else { throw AccountProblem.notConfigured }
            UserDefaults.standard.set(base.absoluteString, forKey: defaultsKey)
            bridgeURL = base.absoluteString
            let verifier = try random(), appState = try random()
            let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
            status = "Opening WHOOP’s official authorization page…"
            let link: Link = try await request(base, path: "v1/link", method: "POST", body: ["challenge": challenge, "appState": appState])
            guard let url = URL(string: link.authorizationURL), let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  components.scheme == "https", components.host == "api.prod.whoop.com", components.path == "/oauth/oauth2/auth",
                  components.user == nil, components.password == nil, components.fragment == nil,
                  components.port == nil || components.port == 443 else { throw AccountProblem.invalidAuthorization }
            let callback = try await authenticate(url)
            try Task.checkCancellation()
            guard let values = URLComponents(url: callback, resolvingAgainstBaseURL: false),
                  values.scheme == "whooplocal", values.host == "oauth", values.path.isEmpty,
                  values.user == nil, values.password == nil, values.port == nil, values.fragment == nil else {
                throw AccountProblem.invalidCallback
            }
            let items = values.queryItems ?? []
            guard items.allSatisfy({ ["state", "code", "error"].contains($0.name) }),
                  items.filter({ $0.name == "state" }).count == 1,
                  let received = items.first(where: { $0.name == "state" })?.value,
                  constantTimeEqual(received, appState) else { throw AccountProblem.invalidCallback }
            guard !items.contains(where: { $0.name == "error" }) else { throw AccountProblem.authorizationDenied }
            guard items.filter({ $0.name == "code" }).count == 1,
                  let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 1_024 else {
                throw AccountProblem.invalidCallback
            }
            let result: Session = try await request(base, path: "v1/session", method: "POST", body: ["code": code, "verifier": verifier])
            guard (16...4_096).contains(result.token.utf8.count), result.token.unicodeScalars.allSatisfy({ $0.value >= 33 && $0.value <= 126 }) else {
                throw AccountProblem.invalidServer
            }
            do {
                try Task.checkCancellation()
                try AccountKeychain.save(result.token, for: base)
            } catch {
                // An unstructured cleanup task is not cancelled with the sign-in task.
                Task { @MainActor in
                    _ = try? await self.rawRequest(base, path: "v1/session", method: "DELETE", token: result.token)
                }
                if error is CancellationError { throw error }
                throw AccountProblem.secureStorage
            }
            bearer = result.token; linkedBaseURL = base; isLinked = true
            status = "Account connected. Sync your recent WHOOP scores when you’re ready."
        } catch { report(error); throw error }
    }

    func fetch(days: Int = 30, ending: Date? = nil) async throws -> WhoopAccountImport {
        guard !isBusy else { throw AccountProblem.busy }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            guard days == 14 || days == 30 else { throw AccountProblem.invalidRange }
            let base = try validatedBaseURL()
            guard let bearer, isLinked, linkedBaseURL == base else { throw AccountProblem.notConnected }
            var query = [URLQueryItem(name: "days", value: String(days))]
            if let ending {
                let now = Date()
                guard ending.timeIntervalSince1970.isFinite,
                      ending >= Date(timeIntervalSince1970: 946_684_800),
                      DayCalendar.start(of: ending) <= DayCalendar.start(of: now),
                      let nextMidnight = DayCalendar.utc.date(byAdding: .day, value: 1, to: DayCalendar.start(of: ending)) else {
                    throw AccountProblem.invalidEndingDay
                }
                // Provider end is exclusive. Include the selected UTC day, capped at today so far.
                let formatter = ISO8601DateFormatter()
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.formatOptions = [.withInternetDateTime]
                query.append(URLQueryItem(name: "end", value: formatter.string(from: min(now, nextMidnight))))
            }
            status = "Reading account-supplied WHOOP scores…"
            let data = try await rawRequest(base, path: "v1/account-data", method: "GET", token: bearer,
                                            query: query)
            try Task.checkCancellation()
            let result = try WhoopAccountMapper.map(data)
            displayName = result.displayName
            status = "Read \(result.days.count) days and \(result.activities.count) activities. Ready to save."
            return result
        } catch { report(error); throw error }
    }

    func disconnect() async {
        guard !isBusy else { return }
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let base = try linkedBaseURL ?? validatedBaseURL()
            if let bearer {
                _ = try await rawRequest(base, path: "v1/session", method: "DELETE", token: bearer)
            }
            try AccountKeychain.delete(for: base)
            bearer = nil; linkedBaseURL = nil; isLinked = false; displayName = nil
            status = "Disconnected. Previously saved days stay in Your Data Files."
        } catch { report(error) }
    }

    func forgetLocalConnection() throws {
        guard !isBusy else { throw AccountProblem.busy }
        let base = try linkedBaseURL ?? validatedBaseURL()
        let previousBearer = bearer
        try AccountKeychain.delete(for: base)
        bearer = nil; linkedBaseURL = nil; isLinked = false; displayName = nil; error = nil
        status = "Connection forgotten on this iPhone. Saved measurements remain available."
        if let previousBearer {
            Task { @MainActor in
                _ = try? await self.rawRequest(base, path: "v1/session", method: "DELETE", token: previousBearer)
            }
        }
    }

    func cancel() {
        session?.cancel(); finishAuthentication(.failure(CancellationError()))
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // A real foreground scene's window was required before starting the session.
        if let authAnchor { return authAnchor }
        // A cancelled session may ask for presentation context while it is dismissing.
        return UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }

    private func authenticate(_ url: URL) async throws -> URL {
        try Task.checkCancellation()
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let anchor = scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first else { throw AccountProblem.noWindow }
        authAnchor = anchor
        let attempt = UUID()
        authID = attempt
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                authContinuation = continuation
                let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: "whooplocal") { [weak self] callback, error in
                    Task { @MainActor in
                        if let error {
                            let failure = error as NSError
                            if failure.domain == ASWebAuthenticationSessionError.errorDomain,
                               failure.code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
                                self?.finishAuthentication(.failure(CancellationError()), attempt: attempt)
                            } else { self?.finishAuthentication(.failure(AccountProblem.authorizationFailed), attempt: attempt) }
                        } else if let callback { self?.finishAuthentication(.success(callback), attempt: attempt) }
                        else { self?.finishAuthentication(.failure(AccountProblem.invalidCallback), attempt: attempt) }
                    }
                }
                auth.presentationContextProvider = self
                auth.prefersEphemeralWebBrowserSession = true
                session = auth
                if !auth.start() { finishAuthentication(.failure(AccountProblem.authorizationFailed), attempt: attempt) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.authID == attempt else { return }
                self.cancel()
            }
        }
    }

    private func finishAuthentication(_ result: Result<URL, Error>, attempt: UUID? = nil) {
        guard attempt == nil || attempt == authID else { return }
        let continuation = authContinuation
        authContinuation = nil; session = nil; authAnchor = nil; authID = nil
        continuation?.resume(with: result)
    }

    private func validatedBaseURL() throws -> URL {
        guard let value = URLComponents(string: bridgeURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              value.scheme == "https", let host = value.host, !host.isEmpty,
              value.user == nil, value.password == nil, value.query == nil, value.fragment == nil,
              value.path.isEmpty || value.path == "/", value.port == nil || value.port == 443,
              value.url != nil else { throw AccountProblem.invalidURL }
        var normalized = value
        normalized.host = host.lowercased(); normalized.scheme = "https"; normalized.port = nil; normalized.path = ""
        guard let url = normalized.url else { throw AccountProblem.invalidURL }
        return url
    }

    private func request<T: Decodable>(_ base: URL, path: String, method: String, body: [String: String]? = nil,
                                       token: String? = nil) async throws -> T {
        let data = try await rawRequest(base, path: path, method: method, body: body, token: token)
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AccountProblem.invalidServer }
    }

    func nutritionPost<Input: Encodable, Output: Decodable>(path: String, input: Input) async throws -> Output {
        let allowed = ["analyze-meal", "parse-food", "estimate-exercise", "day-review"]
        guard allowed.contains(path) else { throw AccountProblem.invalidServer }
        let base = try validatedBaseURL()
        guard let bearer, isLinked, linkedBaseURL == base else {
            throw NutritionError.invalid("AI needs your existing account connection. Connect it from More; manual logging works offline.")
        }
        let data = try await rawRequest(base, path: "api/nutrition/" + path, method: "POST", encodedBody: JSONEncoder().encode(input), token: bearer)
        do { return try JSONDecoder().decode(Output.self, from: data) }
        catch { throw NutritionError.invalid("The AI response could not be read. Try again or enter values manually.") }
    }

    private func rawRequest(_ base: URL, path: String, method: String, body: [String: String]? = nil, encodedBody: Data? = nil,
                            token: String? = nil, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { request.httpBody = try JSONEncoder().encode(body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let encodedBody { request.httpBody = encodedBody; request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await transport.data(for: request)
        guard let response = response as? HTTPURLResponse, response.url?.host == base.host,
              data.count <= 16 * 1_024 * 1_024 else { throw AccountProblem.invalidServer }
        if response.statusCode == 401 {
            // A late cleanup response from an earlier attempt must not unlink a newer session.
            if let token, token == bearer, linkedBaseURL == base {
                bearer = nil; linkedBaseURL = nil; isLinked = false; displayName = nil
                try AccountKeychain.delete(for: base)
            }
            throw AccountProblem.expired
        }
        if path.hasPrefix("api/nutrition/"), !(200...299).contains(response.statusCode) {
            struct Failure: Decodable { let error: String }
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error
            let message: String
            switch code {
            case "ai_not_configured": message = "Nutrition AI is not configured. Add AI_API_KEY and AI_API_URL on your server. Manual logging still works."
            case "rate_limited": message = "AI requests are temporarily limited. Wait a moment and try again."
            case "request_too_large": message = "Choose a smaller meal photo or shorter description."
            case "ai_invalid_response": message = "AI could not return usable estimates. Try a clearer photo or description, or enter values manually."
            case "invalid_request": message = "Check the description, photo and weight, then try again."
            default: message = "The nutrition service could not finish this request. Try again or enter values manually."
            }
            throw NutritionError.invalid(message)
        }
        if response.statusCode == 503 { throw AccountProblem.serverFailure }
        if response.statusCode == 429 { throw AccountProblem.rateLimited }
        guard (200...299).contains(response.statusCode) else { throw AccountProblem.serverFailure }
        return data
    }

    private func report(_ failure: Error) {
        if failure is CancellationError || (failure as? URLError)?.code == .cancelled {
            status = "Cancelled. Saved account data has not changed."
        } else {
            // Never render upstream bodies, callback URLs, request headers, or tokens.
            error = (failure is AccountProblem || failure is WhoopAccountError) ? failure.localizedDescription :
                "Couldn’t reach your HTTPS bridge. Check its URL and connection, then try again."
            status = "Account action did not finish."
        }
    }

    private func random() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw AccountProblem.secureStorage }
        return Data(bytes).base64URL
    }
    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs.utf8), b = Array(rhs.utf8)
        // App states always have 43 bytes. Reject length before fixed-size comparison.
        guard a.count == 43, b.count == 43 else { return false }
        var difference: UInt8 = 0
        for index in 0..<43 { difference |= a[index] ^ b[index] }
        return difference == 0
    }
    private struct Health: Decodable { let service: String; let version: Int; let configured: Bool }
    private struct Link: Decodable { let authorizationURL: String }
    private struct Session: Decodable { let token: String }
}

/// Redirects are forbidden for bridge requests, including redirects carrying a bearer.
private final class AccountRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private enum AccountKeychain {
    static func query(_ url: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "whoop.local.account.bridge",
         kSecAttrAccount as String: Data(SHA256.hash(data: Data(url.absoluteString.utf8))).base64URL,
         kSecAttrSynchronizable as String: false]
    }
    static func read(for url: URL) throws -> String? {
        var query = query(url); query[kSecReturnData as String] = true; query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let code = SecItemCopyMatching(query as CFDictionary, &result)
        if code == errSecItemNotFound { return nil }
        guard code == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else { throw AccountProblem.secureStorage }
        return token
    }
    static func save(_ token: String, for url: URL) throws {
        try delete(for: url)
        var value = query(url)
        value[kSecValueData as String] = Data(token.utf8)
        value[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(value as CFDictionary, nil) == errSecSuccess else { throw AccountProblem.secureStorage }
    }
    static func delete(for url: URL) throws {
        let result = SecItemDelete(query(url) as CFDictionary)
        guard result == errSecSuccess || result == errSecItemNotFound else { throw AccountProblem.secureStorage }
    }
}

private enum AccountProblem: LocalizedError {
    case busy, invalidURL, invalidServer, notConfigured, invalidAuthorization, invalidCallback, authorizationDenied,
         authorizationFailed, noWindow, secureStorage, notConnected, invalidRange, invalidEndingDay, expired, rateLimited, serverFailure
    var errorDescription: String? {
        switch self {
        case .busy: return "An account action is already in progress."
        case .invalidURL: return "Enter your bridge’s HTTPS origin, with no path, credentials, query, or custom port."
        case .invalidServer: return "The bridge returned an unsupported response. Check its configuration."
        case .notConfigured: return "The bridge is unavailable or has no WHOOP OAuth configuration. Configure its server credentials and public HTTPS callback first."
        case .invalidAuthorization: return "The bridge did not provide WHOOP’s official authorization address."
        case .invalidCallback: return "The sign-in callback could not be verified. Start Connect again."
        case .authorizationDenied: return "WHOOP authorization was not granted. Connect again when you’re ready."
        case .authorizationFailed: return "The authorization session did not finish. Try Connect again."
        case .noWindow: return "Open this screen in an active iPhone window before connecting."
        case .secureStorage: return "The account session could not be updated in this iPhone’s secure storage. Unlock your iPhone and try again."
        case .notConnected: return "Connect your WHOOP account before syncing."
        case .invalidRange: return "Choose the last 14 or 30 days."
        case .invalidEndingDay: return "Choose an ending day from January 1, 2000 through today in UTC."
        case .expired: return "Your bridge session expired or was revoked. Connect your account again."
        case .rateLimited: return "WHOOP or your bridge is receiving too many requests. Wait a moment and sync again."
        case .serverFailure: return "The bridge could not finish this action. Check its status and try again."
        }
    }
}
