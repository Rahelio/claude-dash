import Charts
import ServiceManagement
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: UsageStore
    @AppStorage("tokenMetric") private var metric: TokenMetric = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            limitsSection
            Divider()
            todaySection
            Divider()
            weekSection
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text("Claude Usage").font(.headline)
            Spacer()
            if let t = store.live?.fetchedAt ?? store.local?.scannedAt {
                Text("Updated \(t, style: .time)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                store.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default,
                               value: store.isRefreshing)
            }
            .buttonStyle(.borderless)
            .help("Refresh now")
        }
    }

    // MARK: Limits

    @ViewBuilder
    private var limitsSection: some View {
        if let err = store.liveError {
            Label(err, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let live = store.live {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(live.limits) { LimitRow(limit: $0) }
                if !live.breakdown.isEmpty {
                    HStack(spacing: 10) {
                        Text("This week:").foregroundStyle(.secondary)
                        ForEach(live.breakdown) { row in
                            Text("\(row.name) \(Int(row.percent))%")
                        }
                    }
                    .font(.caption)
                }
            }
        } else if store.liveError == nil {
            ProgressView().controlSize(.small)
        }
    }

    // MARK: Today

    @ViewBuilder
    private var todaySection: some View {
        let today = store.local?.today
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Today")
                Spacer()
                if let today {
                    Text("\(Fmt.tokens(metric.value(today.total))) tokens · \(today.total.messages) msgs")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let today, !today.byModel.isEmpty {
                ForEach(today.byModel.sorted { $0.value.total > $1.value.total }, id: \.key) { model, t in
                    ModelRow(model: model, tokens: t, metric: metric)
                }
            } else {
                Text("No Claude Code activity yet today.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Week

    @ViewBuilder
    private var weekSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("Last 7 days")
                Spacer()
                Picker("", selection: $metric) {
                    ForEach(TokenMetric.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 170)
            }

            if let local = store.local {
                Chart {
                    ForEach(local.days) { day in
                        ForEach(day.byModel.sorted { $0.key < $1.key }, id: \.key) { model, t in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Tokens", metric.value(t))
                            )
                            .foregroundStyle(by: .value("Model", Fmt.modelName(model)))
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) {
                        AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks { v in
                        AxisGridLine()
                        AxisValueLabel { if let n = v.as(Int.self) { Text(Fmt.tokens(n)) } }
                    }
                }
                .chartLegend(position: .bottom, spacing: 6)
                .frame(height: 140)

                SectionTitle("By model (7 days)").padding(.top, 4)
                ForEach(local.weekByModel, id: \.model) { item in
                    ModelRow(model: item.model, tokens: item.tokens, metric: metric)
                }
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            LaunchAtLoginToggle()
            Spacer()
            Link("claude.ai usage", destination: URL(string: "https://claude.ai/settings/usage")!)
                .font(.caption)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

// MARK: - Components

enum TokenMetric: String, CaseIterable, Identifiable {
    case all, noCacheRead, output
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "All"
        case .noCacheRead: "No cache"
        case .output: "Output"
        }
    }
    func value(_ t: ModelTokens) -> Int {
        switch self {
        case .all: t.total
        case .noCacheRead: t.input + t.output + t.cacheWrite
        case .output: t.output
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.subheadline.weight(.semibold))
    }
}

struct LimitRow: View {
    let limit: LimitWindow

    private var tint: Color {
        if limit.severity != "normal" || limit.percent >= 90 { return .red }
        if limit.percent >= 70 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.label).font(.subheadline)
                Spacer()
                Text("\(Int(limit.percent.rounded()))%")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            ProgressView(value: min(limit.percent, 100), total: 100).tint(tint)
            if let reset = limit.resetsAt {
                HStack(spacing: 4) {
                    Text("Resets")
                    if reset > Date() {
                        Text(reset, style: .relative)
                        Text("·")
                    }
                    Text(reset.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct ModelRow: View {
    let model: String
    let tokens: ModelTokens
    let metric: TokenMetric

    var body: some View {
        HStack {
            Text(Fmt.modelName(model))
            Spacer()
            Text("\(tokens.messages) msgs").foregroundStyle(.secondary)
            Text(Fmt.tokens(metric.value(tokens)))
                .frame(width: 60, alignment: .trailing)
        }
        .font(.caption)
        .monospacedDigit()
        .help("in \(Fmt.tokens(tokens.input)) · out \(Fmt.tokens(tokens.output)) · cache write \(Fmt.tokens(tokens.cacheWrite)) · cache read \(Fmt.tokens(tokens.cacheRead))")
    }
}

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Open at login", isOn: $enabled)
            .toggleStyle(.checkbox)
            .font(.caption)
            .onChange(of: enabled) { _, on in
                do {
                    if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    enabled = SMAppService.mainApp.status == .enabled
                }
            }
    }
}
