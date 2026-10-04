import Foundation

struct ModelTokens: Sendable {
    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0
    var messages = 0

    var total: Int { input + output + cacheWrite + cacheRead }

    mutating func add(_ usage: [String: Any]) {
        func int(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        input += int("input_tokens")
        output += int("output_tokens")
        cacheWrite += int("cache_creation_input_tokens")
        cacheRead += int("cache_read_input_tokens")
        messages += 1
    }

    static func + (a: ModelTokens, b: ModelTokens) -> ModelTokens {
        ModelTokens(input: a.input + b.input, output: a.output + b.output,
                    cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead,
                    messages: a.messages + b.messages)
    }
}

struct DayUsage: Identifiable, Sendable {
    let day: Date
    var byModel: [String: ModelTokens]
    var id: Date { day }
    var total: ModelTokens { byModel.values.reduce(ModelTokens(), +) }
}

struct LocalReport: Sendable {
    /// Oldest first; always `dayCount` entries, including empty days.
    let days: [DayUsage]
    let scannedAt: Date

    var today: DayUsage? { days.last }

    var weekByModel: [(model: String, tokens: ModelTokens)] {
        var acc: [String: ModelTokens] = [:]
        for d in days { for (m, t) in d.byModel { acc[m, default: ModelTokens()] = acc[m, default: ModelTokens()] + t } }
        return acc.map { ($0.key, $0.value) }.sorted { $0.tokens.total > $1.tokens.total }
    }
}

/// Aggregates token usage from Claude Code's local transcripts (`~/.claude/projects/**/*.jsonl`).
enum LocalScanner {
    static func roots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var dirs = [
            home.appendingPathComponent(".claude/projects"),
            home.appendingPathComponent(".config/claude/projects"),
        ]
        if let custom = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] {
            dirs.insert(URL(fileURLWithPath: custom).appendingPathComponent("projects"), at: 0)
        }
        return dirs
    }

    static func scan(dayCount: Int = 7) -> LocalReport {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(dayCount - 1), to: startToday)!
        let fm = FileManager.default
        let needle = Data("\"usage\"".utf8)

        var seen = Set<String>()
        var buckets: [Date: [String: ModelTokens]] = [:]
        var visitedRoots = Set<String>()

        for root in roots() {
            let resolved = root.resolvingSymlinksInPath().path
            guard visitedRoots.insert(resolved).inserted,
                  let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey])
            else { continue }

            for case let url as URL in en where url.pathExtension == "jsonl" {
                let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let mod, mod < start { continue }
                guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { continue }

                for line in data.split(separator: UInt8(ascii: "\n")) where line.range(of: needle) != nil {
                    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          let msg = obj["message"] as? [String: Any],
                          let usage = msg["usage"] as? [String: Any],
                          let model = msg["model"] as? String, model != "<synthetic>",
                          let ts = obj["timestamp"] as? String,
                          let date = ISODate.parse(ts), date >= start
                    else { continue }

                    // A single API response is written once per content block; count it once.
                    if let id = msg["id"] as? String {
                        let key = id + ":" + (obj["requestId"] as? String ?? "")
                        guard seen.insert(key).inserted else { continue }
                    }

                    let day = cal.startOfDay(for: date)
                    buckets[day, default: [:]][model, default: ModelTokens()].add(usage)
                }
            }
        }

        let days = (0..<dayCount).map { offset -> DayUsage in
            let d = cal.date(byAdding: .day, value: offset, to: start)!
            return DayUsage(day: d, byModel: buckets[d] ?? [:])
        }
        return LocalReport(days: days, scannedAt: Date())
    }
}

enum Fmt {
    /// `claude-opus-5-5` -> `Opus 5.5`, `claude-sonnet-4-5-20250929` -> `Sonnet 4.5`
    static func modelName(_ raw: String) -> String {
        var parts = raw.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        parts.removeAll { $0.count == 8 && Int($0) != nil }
        guard let family = parts.first else { return raw }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? family.capitalized : "\(family.capitalized) \(version)"
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1_000_000_000...: return String(format: "%.2fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(n)"
        }
    }
}
