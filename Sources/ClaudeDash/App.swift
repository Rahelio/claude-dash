import SwiftUI

@main
struct ClaudeDashApp: App {
    @StateObject private var store = UsageStore()

    init() {
        if CommandLine.arguments.contains("--dump") { Self.dump() }
    }

    /// `ClaudeDash --dump` prints what the menu would show, for debugging from a terminal.
    private static func dump() -> Never {
        let r = LocalScanner.scan()
        for d in r.days {
            print(d.day.formatted(date: .abbreviated, time: .omitted), Fmt.tokens(d.total.total), "\(d.total.messages) msgs")
            for (m, t) in d.byModel { print("   ", Fmt.modelName(m), Fmt.tokens(t.total), "out", Fmt.tokens(t.output)) }
        }
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                for l in try await UsageAPI.fetch().limits {
                    print(l.label, "\(l.percent)%", "resets", l.resetsAt.map { $0.formatted() } ?? "-")
                }
            } catch { print("live error:", error.localizedDescription) }
            sem.signal()
        }
        sem.wait()
        exit(0)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView()
                .environmentObject(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageStore: ObservableObject {
    @Published var live: LiveUsage?
    @Published var liveError: String?
    @Published var local: LocalReport?
    @Published var isRefreshing = false

    private var timers: [Timer] = []

    init() {
        refreshAll()
        // The usage endpoint is rate limited, so poll it gently; local files are cheap to rescan.
        timers.append(Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLive() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshLocal() }
        })
    }

    func refreshAll() {
        Task {
            isRefreshing = true
            async let a: Void = refreshLive()
            async let b: Void = refreshLocal()
            _ = await (a, b)
            isRefreshing = false
        }
    }

    func refreshLive() async {
        do {
            live = try await UsageAPI.fetch()
            liveError = nil
        } catch {
            liveError = error.localizedDescription
        }
    }

    func refreshLocal() async {
        local = await Task.detached(priority: .utility) { LocalScanner.scan() }.value
    }
}

struct MenuBarLabel: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            if let live = store.live {
                let s = live.session.map { "\(Int($0.percent.rounded()))%" } ?? "–"
                let w = live.weekly.map { "\(Int($0.percent.rounded()))%" } ?? "–"
                Text("\(s) · \(w)").monospacedDigit()
            } else if let today = store.local?.today {
                Text(Fmt.tokens(today.total.total))
            }
        }
    }
}
