import Foundation

/// One rate-limit window (e.g. the 5-hour session or the weekly cap).
struct LimitWindow: Identifiable, Sendable {
    let id: String
    let label: String
    let percent: Double
    let resetsAt: Date?
    let severity: String
}

/// Share of the weekly window consumed by each surface (Claude Code, Chats, ...).
struct BreakdownRow: Identifiable, Sendable {
    let id: String
    let name: String
    let percent: Double
}

struct LiveUsage: Sendable {
    var limits: [LimitWindow]
    var breakdown: [BreakdownRow]
    var fetchedAt: Date

    var session: LimitWindow? { limits.first { $0.id == "session" } }
    var weekly: LimitWindow? { limits.first { $0.id == "weekly_all" } }
}

enum UsageAPIError: LocalizedError {
    case noCredentials
    case unauthorized
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noCredentials: "No Claude Code login found in Keychain. Run `claude` and log in."
        case .unauthorized: "Login token expired. Run `claude` once to refresh it."
        case .http(429): "Rate limited by the usage endpoint; will retry."
        case .http(let code): "Usage endpoint returned HTTP \(code)."
        case .badResponse: "Unexpected response from the usage endpoint."
        }
    }
}

enum UsageAPI {
    /// Reads the Claude Code OAuth token via the `security` CLI. That binary is already on the
    /// keychain item's access list (Claude Code writes it with it), so no Keychain prompt appears.
    /// We never refresh the token ourselves, to avoid racing Claude Code's refresh-token rotation.
    static func readAccessToken() throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw UsageAPIError.noCredentials }
        return token
    }

    static func fetch() async throws -> LiveUsage {
        let token = try readAccessToken()
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 20

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UsageAPIError.badResponse }
        if http.statusCode == 401 || http.statusCode == 403 { throw UsageAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw UsageAPIError.http(http.statusCode) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAPIError.badResponse
        }
        return parse(obj)
    }

    static func parse(_ obj: [String: Any]) -> LiveUsage {
        var limits: [LimitWindow] = []

        if let arr = obj["limits"] as? [[String: Any]] {
            for l in arr {
                let kind = l["kind"] as? String ?? "unknown"
                limits.append(LimitWindow(
                    id: kind,
                    label: label(forKind: kind),
                    percent: (l["percent"] as? NSNumber)?.doubleValue ?? 0,
                    resetsAt: (l["resets_at"] as? String).flatMap(ISODate.parse),
                    severity: l["severity"] as? String ?? "normal"
                ))
            }
        }

        // Older / model-specific fields. Only add what the `limits` array didn't already cover.
        let legacy: [(key: String, kind: String)] = [
            ("five_hour", "session"),
            ("seven_day", "weekly_all"),
            ("seven_day_opus", "weekly_opus"),
            ("seven_day_sonnet", "weekly_sonnet"),
        ]
        for (key, kind) in legacy where !limits.contains(where: { $0.id == kind }) {
            guard let w = obj[key] as? [String: Any],
                  let util = (w["utilization"] as? NSNumber)?.doubleValue else { continue }
            limits.append(LimitWindow(
                id: kind,
                label: label(forKind: kind),
                percent: util,
                resetsAt: (w["resets_at"] as? String).flatMap(ISODate.parse),
                severity: "normal"
            ))
        }

        var breakdown: [BreakdownRow] = []
        if let b = obj["seven_day_breakdown"] as? [String: Any],
           let rows = b["rows"] as? [[String: Any]] {
            for r in rows {
                let pct = (r["percent"] as? NSNumber)?.doubleValue ?? 0
                guard pct > 0 else { continue }
                breakdown.append(BreakdownRow(
                    id: r["key"] as? String ?? UUID().uuidString,
                    name: r["display_name"] as? String ?? "?",
                    percent: pct
                ))
            }
        }

        return LiveUsage(limits: limits, breakdown: breakdown, fetchedAt: Date())
    }

    static func label(forKind kind: String) -> String {
        switch kind {
        case "session": "Current session (5h)"
        case "weekly_all": "Weekly · all models"
        case "weekly_opus": "Weekly · Opus"
        case "weekly_sonnet": "Weekly · Sonnet"
        default: kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

enum ISODate {
    /// Handles both `2026-10-04T15:19:59.957092+00:00` and `2026-09-17T08:21:33.366Z`
    /// by dropping the fractional seconds, which ISO8601DateFormatter is picky about.
    static func parse(_ s: String) -> Date? {
        let trimmed = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
