import SwiftUI
import SwiftData
import PodedgeCore

/// Settings window with tabs: General, Hosts, Analytics, Models, Distribution, About.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            HostsSettingsTab()
                .tabItem { Label("Hosts", systemImage: "server.rack") }
            AnalyticsSettingsTab()
                .tabItem { Label("Analytics", systemImage: "chart.bar") }
            ModelsSettingsTab()
                .tabItem { Label("Models", systemImage: "cpu") }
            DistributionSettingsTab()
                .tabItem { Label("Distribution", systemImage: "globe") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @AppStorage("autoSaveInterval") private var autoSaveInterval = 30.0
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        Form {
            Section("Preferences") {
                Slider(value: $autoSaveInterval, in: 10...120, step: 10) {
                    Text("Auto-save interval: \(Int(autoSaveInterval))s")
                }
                .accessibilityLabel("Auto-save interval")
            }
            Section("Data") {
                Button("Reset Onboarding") {
                    hasCompletedOnboarding = false
                }
                .accessibilityLabel("Reset onboarding wizard")

                LogExportView()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Hosts (S3 Credentials UI — task 7.3)

private struct HostsSettingsTab: View {
    @Query(sort: \HostBinding.displayName) private var bindings: [HostBinding]
    @Environment(\.modelContext) private var modelContext

    @State private var showingAddSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List {
                ForEach(bindings) { binding in
                    HostBindingRow(binding: binding)
                }
                .onDelete(perform: deleteBindings)
            }
            .overlay {
                if bindings.isEmpty {
                    ContentUnavailableView("No Hosts", systemImage: "server.rack", description: Text("Add an S3-compatible host to publish episodes."))
                }
            }

            HStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Host", systemImage: "plus")
                }
                .accessibilityLabel("Add new host binding")
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingAddSheet) {
            S3CredentialsSheet()
        }
    }

    private func deleteBindings(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(bindings[index])
        }
    }
}

private struct HostBindingRow: View {
    let binding: HostBinding

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(binding.displayName)
                .font(.body)
            Text("\(binding.bucket) • \(binding.region)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// S3 credentials form (task 7.3).
private struct S3CredentialsSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var prefix = ""
    @State private var publicBaseURL = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var endpoint = ""
    @State private var keychainError: String?

    var body: some View {
        Form {
            Section("Host Details") {
                TextField("Display Name", text: $displayName)
                TextField("Bucket", text: $bucket)
                TextField("Region", text: $region)
                TextField("Path Prefix", text: $prefix)
                TextField("Public Base URL", text: $publicBaseURL)
                    .textContentType(.URL)
            }
            Section("Credentials") {
                TextField("Access Key ID", text: $accessKeyID)
                SecureField("Secret Access Key", text: $secretAccessKey)
                TextField("Custom Endpoint (optional)", text: $endpoint)
                    .textContentType(.URL)
                if let keychainError {
                    Text(keychainError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 400)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { saveHost() }
                    .disabled(displayName.isEmpty || bucket.isEmpty || accessKeyID.isEmpty || secretAccessKey.isEmpty)
            }
        }
    }

    private func saveHost() {
        guard let baseURL = URL(string: publicBaseURL) else { return }
        let keychainRef = "host-\(UUID().uuidString)"

        let credential = HostCredential(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey,
            endpoint: endpoint.isEmpty ? nil : URL(string: endpoint)
        )
        keychainError = nil
        Task {
            do {
                let keychain = KeychainService()
                try await keychain.storeCredential(credential, forKey: keychainRef)
                let binding = HostBinding(
                    displayName: displayName,
                    bucket: bucket,
                    region: region,
                    prefix: prefix,
                    publicBaseURL: baseURL,
                    keychainRef: keychainRef
                )
                modelContext.insert(binding)
                dismiss()
            } catch {
                keychainError = "Failed to store credentials: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Analytics

private struct AnalyticsSettingsTab: View {
    @Query private var analyticsBindings: [AnalyticsBinding]
    @Environment(\.modelContext) private var modelContext

    @State private var showingImport = false
    @State private var importShowUUID = ""

    var body: some View {
        Form {
            if let binding = analyticsBindings.first {
                Section("OP3 Analytics") {
                    LabeledContent("Status") {
                        if let showID = binding.externalShowID, !showID.isEmpty {
                            Label("Registered", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else {
                            Label("Pending — registers on first publish", systemImage: "clock")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }
                    if let showID = binding.externalShowID, !showID.isEmpty {
                        LabeledContent("Show UUID") {
                            Text(showID)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    LabeledContent("Prefix") {
                        Text(binding.prefixBaseURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Link("View analytics on op3.dev", destination: URL(string: "https://op3.dev")!)
                        .font(.caption)
                }
                Section {
                    Button("Remove OP3 Analytics", role: .destructive) {
                        modelContext.delete(binding)
                    }
                    .accessibilityLabel("Remove OP3 analytics binding")
                }
            } else {
                Section("OP3 Analytics") {
                    Text("Download analytics are not enabled.")
                        .foregroundStyle(.secondary)
                        .font(.caption)

                    Button("Enable OP3 Analytics") {
                        let binding = AnalyticsBinding(
                            provider: "op3",
                            prefixBaseURL: URL(string: "https://op3.dev/e")!
                        )
                        modelContext.insert(binding)
                    }
                    .accessibilityLabel("Enable OP3 analytics")
                }

                Section("Import Existing OP3 Data") {
                    Text("If you already have OP3 analytics from another app, enter your Show UUID to link your existing data.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("OP3 Show UUID", text: $importShowUUID)
                        .font(.caption.monospaced())
                    Button("Import") {
                        guard !importShowUUID.isEmpty else { return }
                        let binding = AnalyticsBinding(
                            provider: "op3",
                            externalShowID: importShowUUID,
                            prefixBaseURL: URL(string: "https://op3.dev/e")!
                        )
                        modelContext.insert(binding)
                        importShowUUID = ""
                    }
                    .disabled(importShowUUID.isEmpty)
                    .accessibilityLabel("Import existing OP3 analytics")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Models

private struct ModelsSettingsTab: View {
    @State private var models: [String] = []
    @State private var isLoading = false

    var body: some View {
        Form {
            Section("Transcription Models") {
                if isLoading {
                    ProgressView("Loading models…")
                } else if models.isEmpty {
                    Text("No models downloaded. Model management is coming in a future update.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(models, id: \.self) { model in
                        Text(model)
                    }
                }
            }
            Section("Storage") {
                LabeledContent("Models Directory") {
                    Text("~/Library/Application Support/Podedge/Models/")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button("Open in Finder") {
                    let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                        .appendingPathComponent("Podedge/Models", isDirectory: true)
                    NSWorkspace.shared.open(url)
                }
                .accessibilityLabel("Open models directory in Finder")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Distribution

private struct DistributionSettingsTab: View {
    @Query private var records: [DistributionRecord]

    var body: some View {
        Form {
            Section("Distribution Directories") {
                if records.isEmpty {
                    Text("No distribution records. Submit your show to directories from the show editor.")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    ForEach(records) { record in
                        HStack {
                            Text(record.targetID.capitalized)
                            Spacer()
                            Text(record.status.rawValue.capitalized)
                                .font(.caption)
                                .foregroundStyle(record.status == .live ? .green : .secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Podedge")
                .font(.title)
                .fontWeight(.bold)

            Text("Local-first podcast publishing for macOS")
                .foregroundStyle(.secondary)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            Text("Built with SwiftUI, SwiftData, and Swift Concurrency.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
