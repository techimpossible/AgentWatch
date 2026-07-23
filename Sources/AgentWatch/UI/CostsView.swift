import SwiftUI

struct CostsView: View {
    @State private var agg: CostAggregate?
    @State private var loading = false
    @State private var tab: Tab = .profile

    @State private var range: DateRange = .all

    @Environment(\.colorScheme) private var scheme

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
            hairlineDivider
            rangePicker
            hairlineDivider
            if loading {
                ProgressView("Computing…")
                    .font(Theme.prose)
                    .tint(Theme.accentBlue)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let agg {
                summary(agg)
                hairlineDivider
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .tint(Theme.accentBlue)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

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

    /// A quiet hairline separator (spec §7.1).
    private var hairlineDivider: some View {
        Rectangle()
            .fill(Theme.hairline.opacity(scheme == .dark ? 0.12 : 0.10))
            .frame(height: 0.5)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COSTS")
                    .font(Theme.titleWindow)
                    .tracking(0.5)
                    .foregroundStyle(Theme.textPrimary)
                Text("Anthropic published rates as of \(Pricing.asOf) · proxy/gateway billing may differ")
                    .font(Theme.prose)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                reload()
            } label: {
                Label("REFRESH", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.secondary)
            .disabled(loading)
        }
        .padding(20)
    }

    private var rangePicker: some View {
        HStack(spacing: 10) {
            Text("RANGE")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textSecondary)
            Picker("Cost date range", selection: $range) {
                ForEach(DateRange.allCases) { r in Text(r.rawValue).tag(r) }
            }
            .pickerStyle(.segmented)
            .tint(Theme.accentBlue)
            .labelsHidden()
            .frame(maxWidth: 260)
            .accessibilityLabel("Cost date range")
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onChange(of: range) { _, _ in reload() }
    }

    private func summary(_ a: CostAggregate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Grand total — a spend figure is information, not "your turn": no coral, no glow.
            Text(formatUSD(a.totalCost))
                .font(Theme.displayLarge)
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 8) {
                metric("INPUT", value: formatTokens(a.totalInputTokens), tint: Theme.accentBlue)
                metric("OUTPUT", value: formatTokens(a.totalOutputTokens), tint: Theme.accentGreen)
                metric("CACHE READ", value: formatTokens(a.totalCacheRead), tint: Theme.idle)
                metric("CACHE WRITE", value: formatTokens(a.totalCacheWrite), tint: Theme.idle)
            }
            Text("\(a.entriesCounted) ASSISTANT TURNS COUNTED")
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(20)
    }

    private func metric(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Caption row: tiny semantic dot inline with the eyebrow — never a coral
            // fill on routine metrics.
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                Text(label)
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(Theme.monoStrong)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.hairline.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.28 : 0.06), radius: 6, y: 2)
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
                hairlineDivider
                    .padding(.horizontal, 14)
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
        // Proportion tint = profile (profile/project tabs) or calm blue (day/model).
        let barTint = tint ?? Theme.accentBlue
        return HStack {
            Text(label)
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(formatUSD(cost))
                .font(Theme.monoStrong)
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(alignment: .leading) {
            // Single quiet left-anchored proportion fill.
            GeometryReader { geo in
                LinearGradient(
                    colors: [barTint.opacity(0.26), barTint.opacity(0.10)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geo.size.width * fraction)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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
