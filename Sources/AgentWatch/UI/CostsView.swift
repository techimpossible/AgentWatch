import SwiftUI

struct CostsView: View {
    @State private var agg: CostAggregate?
    @State private var loading = false
    @State private var tab: Tab = .profile

    @State private var range: DateRange = .all

    enum Tab: String, CaseIterable, Identifiable {
        case profile = "By profile", project = "By project", day = "By day", model = "By model"
        var id: String { rawValue }
    }

    enum DateRange: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", all = "All"
        var id: String { rawValue }
        /// Start of the window, or nil for "All" (no lower bound).
        var since: Date? {
            switch self {
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .day, value: -30, to: Date())
            case .all:   return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            rangePicker
            Divider()
            if loading {
                ProgressView("Computing…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let agg {
                summary(agg)
                Divider()
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(8)

                ScrollView {
                    switch tab {
                    case .profile: bucketList(agg.byProfile, sortDescending: false, colorByProfile: true)
                    case .project: bucketList(agg.byProject, sortDescending: false, colorByProfile: true)
                    case .day:     bucketList(agg.byDay, sortDescending: true)
                    case .model:   bucketList(agg.byModel, sortDescending: false)
                    }
                }
            } else {
                ContentUnavailableView("Loading costs…", systemImage: "ellipsis")
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .darkGlassBackground()
        .onAppear { reload() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COSTS")
                    .font(Theme.chromeTitle)
                    .tracking(3.0)
                    .foregroundStyle(Theme.dpGold)
                Text("Anthropic published rates as of \(Pricing.asOf) · proxy/gateway billing may differ")
                    .font(Theme.chromeCaption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                reload()
            } label: {
                Label("REFRESH", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.neonGold)
            .disabled(loading)
        }
        .padding(16)
    }

    private var rangePicker: some View {
        HStack(spacing: 10) {
            Text("RANGE")
                .font(Theme.chromeCaption)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
            Picker("Cost date range", selection: $range) {
                ForEach(DateRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            .accessibilityLabel("Cost date range")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onChange(of: range) { _, _ in reload() }
    }

    private func summary(_ a: CostAggregate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(formatUSD(a.totalCost))
                .font(Theme.displayLarge)
                .foregroundStyle(Theme.dpGold)
                .shadow(color: Theme.dpGold.opacity(0.5), radius: 8)
            HStack(spacing: 14) {
                metric("INPUT", value: formatTokens(a.totalInputTokens), tint: Theme.neonCyan)
                metric("OUTPUT", value: formatTokens(a.totalOutputTokens), tint: Theme.neonMagenta)
                metric("CACHE READ", value: formatTokens(a.totalCacheRead), tint: Theme.dpChrome)
                metric("CACHE WRITE", value: formatTokens(a.totalCacheWrite), tint: Theme.dpChrome)
            }
            Text("\(a.entriesCounted) ASSISTANT TURNS COUNTED")
                .font(Theme.chromeCaption)
                .tracking(1.2)
                .foregroundStyle(.tertiary)
        }
        .padding(16)
    }

    private func metric(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Theme.chromeCaption)
                .tracking(1.2)
                .foregroundStyle(tint.opacity(0.85))
            Text(value)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.tint(tint.opacity(0.10)), in: RoundedRectangle(cornerRadius: 6))
    }

    private func bucketList(_ dict: [String: Double], sortDescending: Bool, colorByProfile: Bool = false) -> some View {
        let pairs: [(String, Double)] = sortDescending
            ? dict.sorted { $0.key > $1.key }
            : dict.sorted { $0.value > $1.value }
        let max = pairs.map { $0.1 }.max() ?? 1
        return VStack(spacing: 0) {
            ForEach(Array(pairs.enumerated()), id: \.0) { _, pair in
                row(label: pair.0, cost: pair.1, fraction: pair.1 / max,
                    tint: colorByProfile ? Theme.profileColor(profileToken(pair.0)) : nil)
                Divider()
            }
        }
    }

    /// The leading profile token of a bucket key ("console · home" -> "console",
    /// "or" -> "or"). Used to colour profile/project rows by their profile.
    private func profileToken(_ key: String) -> String {
        if let sep = key.range(of: " · ") {
            return String(key[key.startIndex..<sep.lowerBound])
        }
        return key
    }

    private func row(label: String, cost: Double, fraction: Double, tint: Color? = nil) -> some View {
        HStack {
            Text(label)
                .font(.system(.callout, design: .rounded))
                .lineLimit(1)
            Spacer()
            Text(formatUSD(cost))
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Theme.dpGold)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(alignment: .leading) {
            GeometryReader { geo in
                let colors = tint.map { [$0.opacity(0.28), $0.opacity(0.10)] }
                    ?? [Theme.neonCyan.opacity(0.18), Theme.neonMagenta.opacity(0.10)]
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * fraction)
            }
        }
    }

    private func reload() {
        loading = true
        let since = range.since
        Task.detached(priority: .userInitiated) {
            let computed = CostCalculator.computeAll(since: since)
            await MainActor.run {
                agg = computed
                loading = false
            }
        }
    }

    private func formatUSD(_ v: Double) -> String {
        String(format: "$%.2f", v)
    }
    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
