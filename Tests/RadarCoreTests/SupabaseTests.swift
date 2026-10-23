import Testing
import Foundation
@testable import RadarCore

private let cfg = SupabaseConfig(url: URL(string: "https://x.supabase.co")!, anonKey: "ANON")
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private final class Recorder: @unchecked Sendable {
    var requests: [URLRequest] = []
}

private func client(_ rec: Recorder, status: Int = 200, body: String = "[]") -> SupabaseClient {
    SupabaseClient(config: cfg) { req in
        rec.requests.append(req)
        let resp = HTTPURLResponse(url: req.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), resp)
    }
}

private func session(expiresIn: TimeInterval = 3600) -> AuthSession {
    AuthSession(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(expiresIn), userId: "u1")
}

private func claim(_ id: String) -> TeamClaim {
    TeamClaim(ownerId: nil, ownerName: "Ali", sessionId: id, repoKey: "github.com/x/y", branch: "main", topic: "konu",
              openTopics: [], working: true, lastRequestAt: now, updatedAt: nil)
}

private func bodyString(_ r: URLRequest) -> String { String(decoding: r.httpBody ?? Data(), as: UTF8.self) }

@Test func signInBuildsPasswordGrantAndParsesSession() async throws {
    let rec = Recorder()
    let body = #"{"access_token":"AT","refresh_token":"RT","expires_in":3600,"user":{"id":"u1"}}"#
    let s = try await client(rec, body: body).signIn(email: "a@b.c", password: "pw", now: now)
    let r = try #require(rec.requests.first)
    #expect(r.httpMethod == "POST")
    #expect(r.url?.path == "/auth/v1/token")
    #expect(r.url?.query == "grant_type=password")
    #expect(r.value(forHTTPHeaderField: "apikey") == "ANON")
    #expect(r.value(forHTTPHeaderField: "Content-Type") == "application/json")
    let sent = try JSONSerialization.jsonObject(with: r.httpBody!) as? [String: String]
    #expect(sent == ["email": "a@b.c", "password": "pw"])
    #expect(s == AuthSession(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(3600), userId: "u1"))
}

@Test func publishUpsertsWithOwnerAndDeletesOthers() async throws {
    let rec = Recorder()
    try await client(rec).publish([claim("s1"), claim("s2")], as: session())
    #expect(rec.requests.count == 2)
    let up = rec.requests[0]
    #expect(up.httpMethod == "POST")
    #expect(up.url?.path == "/rest/v1/claims")
    #expect(up.url?.query == "on_conflict=owner_id,session_id&columns=owner_id,owner_name,session_id,repo_key,branch,topic,open_topics,working,last_request_at")
    #expect(up.value(forHTTPHeaderField: "Prefer") == "resolution=merge-duplicates,return=minimal")
    #expect(up.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
    #expect(up.value(forHTTPHeaderField: "apikey") == "ANON")
    #expect(bodyString(up).contains(#""owner_id":"u1""#))
    #expect(bodyString(up).contains(#""session_id":"s1""#))
    let del = rec.requests[1]
    #expect(del.httpMethod == "DELETE")
    #expect(del.url?.query == "owner_id=eq.u1&session_id=not.in.(s1,s2)")
    #expect(del.value(forHTTPHeaderField: "Authorization") == "Bearer AT")
}

@Test func publishEmptyDeletesAllMine() async throws {
    let rec = Recorder()
    try await client(rec).publish([], as: session())
    #expect(rec.requests.count == 1)
    #expect(rec.requests[0].httpMethod == "DELETE")
    #expect(rec.requests[0].url?.query == "owner_id=eq.u1")
}

@Test func fetchOthersDecodesPostgresTimestamps() async throws {
    let rec = Recorder()
    let row = { (id: String, at: String) in
        #"{"owner_id":"u2","owner_name":"Veli","session_id":"\#(id)","repo_key":"k","branch":null,"topic":"t","open_topics":[],"working":false,"last_request_at":"\#(at)","updated_at":"\#(at)"}"#
    }
    let body = "[" + row("a", "2026-10-24T10:00:00.123456+00:00") + "," + row("b", "2026-10-24T10:00:00+00:00") + "]"
    let out = try await client(rec, body: body).fetchOthers(as: session(), since: now)
    #expect(out.count == 2)
    let base = ISO8601DateFormatter().date(from: "2026-10-24T10:00:00Z")!
    #expect(out[1].lastRequestAt == base)
    #expect(abs(out[0].lastRequestAt.timeIntervalSince(base) - 0.123456) < 0.001)
    #expect(out[0].updatedAt != nil)
    let q = try #require(rec.requests.first?.url?.query)
    #expect(q.contains("owner_id=neq.u1"))
    #expect(q.contains("select=*"))
    #expect(q.contains("updated_at=gte.2027-01-15T08:00:00Z"))
    #expect(rec.requests[0].httpMethod == "GET")
}

@Test func httpErrorSurfaces() async throws {
    let rec = Recorder()
    await #expect(throws: SupabaseError.http(401, "nope")) {
        _ = try await client(rec, status: 401, body: "nope").fetchOthers(as: session(), since: now)
    }
}

@Test func authorizedRefreshesNearExpiry() async throws {
    let rec = Recorder()
    let body = #"{"access_token":"AT2","refresh_token":"RT2","expires_in":3600,"user":{"id":"u1"}}"#
    let c = client(rec, body: body)
    let fresh = try await c.authorized(session(expiresIn: 3600), now: now)
    #expect(rec.requests.isEmpty)
    #expect(fresh == session())
    let renewed = try await c.authorized(session(expiresIn: 30), now: now)
    let r = try #require(rec.requests.first)
    #expect(r.url?.query == "grant_type=refresh_token")
    #expect(bodyString(r).contains(#""refresh_token":"RT""#))
    #expect(renewed.accessToken == "AT2")
    #expect(renewed.expiresAt == now.addingTimeInterval(3600))
}

@Test func publishMixedNilBranchSendsColumnsList() async throws {
    let rec = Recorder()
    var a = claim("s1"); a.branch = nil
    var b = claim("s2"); b.branch = "main"
    try await client(rec).publish([a, b], as: session())
    let up = rec.requests[0]
    #expect(up.url?.query == "on_conflict=owner_id,session_id&columns=owner_id,owner_name,session_id,repo_key,branch,topic,open_topics,working,last_request_at")
    #expect(bodyString(up).contains(#""session_id":"s1""#))
    #expect(bodyString(up).contains(#""session_id":"s2""#))
    #expect(rec.requests.count == 2)
}
