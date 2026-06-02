import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PodedgeCore

/// Displays a filterable list of tool invocation audit entries.
struct AuditLogView: View {
    @Query(sort: \AgentAuditEntry.timestamp, order: .reverse)
    private var entries: [AgentAuditEntry]

    @State private var filterToolName = ""

    private var filteredEntries: [AgentAuditEntry] {
        guard !filterToolName.isEmpty else { return entries }
        return entries.filter { $0.toolName.localizedCaseInsensitiveContains(filterToolName) }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter by tool name…", text: $filterToolName)
                .textFieldStyle(.roundedBorder)
                .padding(8)

            Table(filteredEntries) {
                TableColumn("Time") { entry in
                    Text(entry.timestamp, style: .time)
                        .font(.caption.monospaced())
                }
                .width(min: 60, ideal: 70)

                TableColumn("Tool") { entry in
                    Text(entry.toolName)
                        .font(.caption.monospaced())
                }
                .width(min: 100, ideal: 140)

                TableColumn("Agent") { entry in
                    Text(entry.agentName)
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Scope") { entry in
                    scopeBadge(entry.scope)
                }
                .width(min: 70, ideal: 80)

                TableColumn("Result") { entry in
                    Image(systemName: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(entry.success ? .green : .red)
                }
                .width(min: 40, ideal: 50)

                TableColumn("Duration") { entry in
                    Text(String(format: "%.2fs", entry.durationSeconds))
                        .font(.caption.monospaced())
                }
                .width(min: 50, ideal: 60)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportJSONL()
                } label: {
                    Label("Export JSONL", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export audit log as JSONL")
            }
        }
    }

    private func scopeBadge(_ scope: ToolScope) -> some View {
        let (label, color): (String, Color) = switch scope {
        case .readOnly: ("read", .blue)
        case .mutating: ("write", .orange)
        case .destructive: ("destructive", .red)
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(.capsule)
    }

    private func exportJSONL() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "audit-log.jsonl"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let lines = filteredEntries.compactMap { entry -> String? in
                struct Row: Encodable {
                    let id: UUID
                    let timestamp: Date
                    let agentName: String
                    let toolName: String
                    let scope: String
                    let inputSummary: String
                    let outputSummary: String
                    let durationSeconds: Double
                    let success: Bool
                }
                let row = Row(
                    id: entry.id,
                    timestamp: entry.timestamp,
                    agentName: entry.agentName,
                    toolName: entry.toolName,
                    scope: "\(entry.scope)",
                    inputSummary: entry.inputSummary,
                    outputSummary: entry.outputSummary,
                    durationSeconds: entry.durationSeconds,
                    success: entry.success
                )
                guard let data = try? encoder.encode(row) else { return nil }
                return String(data: data, encoding: .utf8)
            }
            let content = lines.joined(separator: "\n")
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
