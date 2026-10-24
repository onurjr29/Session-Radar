import Foundation

public struct SupabaseConfig: Equatable, Sendable {
    public var url: URL
    public var anonKey: String
    public init(url: URL, anonKey: String) { self.url = url; self.anonKey = anonKey }
}

public struct AuthSession: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var userId: String
    public init(accessToken: String, refreshToken: String, expiresAt: Date, userId: String) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt; self.userId = userId
    }
}

public enum SupabaseError: Error, Equatable { case http(Int, String), badResponse }

public typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// eksik anahtarlar (ör. branch nil) NULL olur; paylaşılan alanların sunucu tarafı izin listesi
let upsertColumns = "owner_id,owner_name,session_id,repo_key,branch,topic,open_topics,working,last_request_at"

public struct SupabaseClient: Sendable {
    let config: SupabaseConfig
    let transport: HTTPTransport

    public init(config: SupabaseConfig, transport: @escaping HTTPTransport = { try await URLSession.shared.data(for: $0) }) {
        self.config = config
        self.transport = transport
    }

    public func signIn(email: String, password: String, now: Date) async throws -> AuthSession {
        try await token("password", ["email": email, "password": password], now: now)
    }

    /// süresine 60 sn'den az kaldıysa yeniler, yoksa aynısını döner
    public func authorized(_ s: AuthSession, now: Date) async throws -> AuthSession {
        guard s.expiresAt.timeIntervalSince(now) < 60 else { return s }
        return try await token("refresh_token", ["refresh_token": s.refreshToken], now: now)
    }

    /// benim kayıtlarımı upsert eder, listede olmayan benim kayıtlarımı siler
    public func publish(_ claims: [TeamClaim], as s: AuthSession) async throws {
        var del = "owner_id=eq.\(s.userId)"
        if !claims.isEmpty {
            let mine = claims.map { c -> TeamClaim in var c = c; c.ownerId = s.userId; return c }
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            _ = try await send("POST", "/rest/v1/claims?on_conflict=owner_id,session_id&columns=\(upsertColumns)", body: enc.encode(mine), session: s,
                               prefer: "resolution=merge-duplicates,return=minimal")
            del += "&session_id=not.in.(\(claims.map(\.sessionId).joined(separator: ",")))"
        }
        _ = try await send("DELETE", "/rest/v1/claims?\(del)", session: s)
    }

    public func fetchOthers(as s: AuthSession, since: Date) async throws -> [TeamClaim] {
        let ts = ISO8601DateFormatter().string(from: since)
        let data = try await send("GET", "/rest/v1/claims?select=*&owner_id=neq.\(s.userId)&updated_at=gte.\(ts)", session: s)
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .custom { d in
            let str = try d.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let frac = ISO8601DateFormatter()
            frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = frac.date(from: str) ?? plain.date(from: str) else {
                throw DecodingError.dataCorruptedError(in: try d.singleValueContainer(), debugDescription: "tarih: \(str)")
            }
            return date
        }
        return try dec.decode([TeamClaim].self, from: data)
    }

    private func token(_ grant: String, _ body: [String: String], now: Date) async throws -> AuthSession {
        let data = try await send("POST", "/auth/v1/token?grant_type=\(grant)", body: JSONEncoder().encode(body), session: nil)
        struct Resp: Decodable {
            var access_token: String, refresh_token: String, expires_in: Double
            var user: User
            struct User: Decodable { var id: String }
        }
        guard let r = try? JSONDecoder().decode(Resp.self, from: data) else { throw SupabaseError.badResponse }
        return AuthSession(accessToken: r.access_token, refreshToken: r.refresh_token,
                           expiresAt: now.addingTimeInterval(r.expires_in), userId: r.user.id)
    }

    private func send(_ method: String, _ path: String, body: Data? = nil, session: AuthSession?, prefer: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: config.url)?.absoluteURL else { throw SupabaseError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        if let session { req.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization") }
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await transport(req)
        guard let http = resp as? HTTPURLResponse else { throw SupabaseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw SupabaseError.http(http.statusCode, String(decoding: data, as: UTF8.self).prefix(200).description)
        }
        return data
    }
}
