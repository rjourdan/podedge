import SwiftUI
import SwiftData
import Charts
import PodedgeCore

/// SwiftCharts line chart of downloads over time from AnalyticsSnapshot data.
struct AnalyticsView: View {
    let showID: PersistentIdentifier?

    // NOTE: SwiftData @Query does not support filtering by PersistentIdentifier in predicates.
    // We fetch all snapshots and filter in memory. For large datasets, consider a manual fetch.
    @Query(sort: \AnalyticsSnapshot.capturedAt) private var allSnapshots: [AnalyticsSnapshot]

    /// Snapshots filtered to the selected show.
    private var snapshots: [AnalyticsSnapshot] {
        guard let showID else { return [] }
        return allSnapshots.filter { $0.show?.persistentModelID == showID }
    }

    @State private var timeRange: TimeRange = .week

    enum TimeRange: String, CaseIterable {
        case week = "7 Days"
        case month = "30 Days"
        case quarter = "90 Days"

        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .quarter: 90
            }
        }
    }

    private var filteredSnapshots: [AnalyticsSnapshot] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -timeRange.days, to: Date())!
        return snapshots.filter { $0.capturedAt >= cutoff }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Analytics")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                    Picker("Range", selection: $timeRange) {
                        ForEach(TimeRange.allCases, id: \.self) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                    .accessibilityLabel("Time range")
                }

                if filteredSnapshots.isEmpty {
                    ContentUnavailableView("No Analytics Data", systemImage: "chart.line.downtrend.xyaxis", description: Text("Analytics data will appear after OP3 polling begins."))
                } else {
                    downloadsChart
                    listenersChart
                    summaryStats
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var downloadsChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Downloads")
                .font(.headline)
            Chart(filteredSnapshots) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.capturedAt),
                    y: .value("Downloads", snapshot.downloads)
                )
                .foregroundStyle(.blue)
                AreaMark(
                    x: .value("Date", snapshot.capturedAt),
                    y: .value("Downloads", snapshot.downloads)
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
            .frame(height: 200)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6))
            }
            .accessibilityLabel("Downloads over time chart")
        }
    }

    private var listenersChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Unique Listeners")
                .font(.headline)
            Chart(filteredSnapshots) { snapshot in
                LineMark(
                    x: .value("Date", snapshot.capturedAt),
                    y: .value("Listeners", snapshot.uniqueListeners)
                )
                .foregroundStyle(.green)
            }
            .frame(height: 160)
            .accessibilityLabel("Unique listeners over time chart")
        }
    }

    private var summaryStats: some View {
        let totalDownloads = filteredSnapshots.reduce(0) { $0 + $1.downloads }
        let totalListeners = filteredSnapshots.reduce(0) { $0 + $1.uniqueListeners }

        return HStack(spacing: 24) {
            VStack {
                Text("\(totalDownloads)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Total Downloads")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Total Downloads: \(totalDownloads)")
            VStack {
                Text("\(totalListeners)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Unique Listeners")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Unique Listeners: \(totalListeners)")
            VStack {
                Text("\(filteredSnapshots.count)")
                    .font(.title)
                    .fontWeight(.bold)
                Text("Data Points")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Data Points: \(filteredSnapshots.count)")
        }
        .accessibilityElement(children: .contain)
    }
}
