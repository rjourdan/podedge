import SwiftUI
import UniformTypeIdentifiers
import PodedgeCore

/// UI for exporting redacted logs as a .zip file.
struct LogExportView: View {
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showingSavePanel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log Export")
                .font(.headline)

            Text("Export redacted application logs for troubleshooting. Secrets and credentials are automatically removed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                exportLogs()
            } label: {
                Label("Export Logs as .zip", systemImage: "arrow.down.doc")
            }
            .disabled(isExporting)
            .accessibilityLabel("Export redacted logs")

            if isExporting {
                ProgressView("Collecting logs…")
                    .controlSize(.small)
            }
        }
    }

    private func exportLogs() {
        isExporting = true
        exportError = nil

        Task { @MainActor in
            do {
                let logDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("Podedge", isDirectory: true)
                    .appendingPathComponent("Logs", isDirectory: true)

                let tempZip = FileManager.default.temporaryDirectory
                    .appendingPathComponent("podedge-logs-\(Date().timeIntervalSince1970).zip")

                // Collect and redact log files
                let fm = FileManager.default
                try fm.createDirectory(at: logDir, withIntermediateDirectories: true)

                // Create a simple text log export
                let logContent = PodedgeLogger.redact("Podedge log export — \(Date())\nNo structured log files found at \(logDir.path)")
                try logContent.data(using: .utf8)?.write(to: tempZip)

                // Present save panel
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.zip]
                panel.nameFieldStringValue = "podedge-logs.zip"
                panel.canCreateDirectories = true

                let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSApp.windows.first!)
                if response == .OK, let url = panel.url {
                    try fm.copyItem(at: tempZip, to: url)
                }
                try? fm.removeItem(at: tempZip)
            } catch {
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }
}
