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
            Image(nsImage: Self.botHead)
            if let session = store.live?.session {
                Text("\(Int(session.percent.rounded()))%").monospacedDigit()
            }
        }
    }

    /// A small bot head (antenna, rounded face, two eyes) drawn as a template image so it
    /// follows the menu bar's light/dark appearance. SF Symbols has no robot glyph.
    static let botHead: NSImage = {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.set()
            // Antenna
            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 9, y: 2.5))
            stem.line(to: NSPoint(x: 9, y: 5.5))
            stem.lineWidth = 1.4
            stem.stroke()
            NSBezierPath(ovalIn: NSRect(x: 7.6, y: 0.6, width: 2.8, height: 2.8)).fill()
            // Ears
            NSBezierPath(roundedRect: NSRect(x: 0.8, y: 9, width: 1.8, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 15.4, y: 9, width: 1.8, height: 4), xRadius: 0.8, yRadius: 0.8).fill()
            // Face
            let face = NSBezierPath(roundedRect: NSRect(x: 3.2, y: 5.7, width: 11.6, height: 10.6), xRadius: 3, yRadius: 3)
            face.lineWidth = 1.5
            face.stroke()
            // Eyes
            NSBezierPath(ovalIn: NSRect(x: 5.7, y: 9, width: 2.4, height: 2.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 9.9, y: 9, width: 2.4, height: 2.4)).fill()
            // Mouth
            let mouth = NSBezierPath()
            mouth.move(to: NSPoint(x: 7, y: 13.6))
            mouth.line(to: NSPoint(x: 11, y: 13.6))
            mouth.lineWidth = 1.2
            mouth.lineCapStyle = .round
            mouth.stroke()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "Claude usage"
        return img
    }()
}
