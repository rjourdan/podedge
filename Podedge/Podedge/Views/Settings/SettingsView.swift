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
            LLMProvidersSettingsTab()
                .tabItem { Label("LLM Providers", systemImage: "brain") }
            DistributionSettingsTab()
                .tabItem { Label("Distribution", systemImage: "globe") }
            SocialSettingsTab()
                .tabItem { Label("Social", systemImage: "bubble.left.and.bubble.right") }
            AuditLogView()
                .tabItem { Label("Audit Log", systemImage: "list.clipboard") }
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 600, height: 420)
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

// MARK: - LLM Providers

private struct LLMProvidersSettingsTab: View {
    @AppStorage("llm.provider.activeID") private var activeID = ""
    @AppStorage("llm.provider.modelID") private var modelID = ""
    @State private var ollamaModels: [OllamaModelInfo] = []
    @State private var connectionStatus: String?
    @State private var isTesting = false
    @Environment(\.appServices) private var appServices

    var body: some View {
        Form {
            Section("Active Provider") {
                LabeledContent("Provider") {
                    Text(activeID.isEmpty ? "Not configured" : activeID.uppercased())
                        .foregroundStyle(activeID.isEmpty ? .secondary : .primary)
                }
                LabeledContent("Model") {
                    Text(modelID.isEmpty ? "None" : modelID)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Change Provider") {
                Picker("Provider", selection: $activeID) {
                    Text("None").tag("")
                    Text("MLX (built-in)").tag("mlx")
                    Text("Ollama (local service)").tag("ollama")
                }
                .pickerStyle(.segmented)

                if activeID == "mlx" {
                    Picker("Model", selection: $modelID) {
                        Text("Gemma 4 E4B (4-bit)").tag("mlx-community/gemma-4-e4b-it-4bit-MAD")
                        Text("Qwen 3 8B (4-bit DWQ)").tag("mlx-community/Qwen3-8B-4bit-DWQ-053125")
                        Text("Mistral Small 24B (4-bit)").tag("mlx-community/Mistral-Small-24B-Instruct-2501-4bit")
                    }
                } else if activeID == "ollama" {
                    if ollamaModels.isEmpty {
                        Text("No models found. Is Ollama running?")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Model", selection: $modelID) {
                            ForEach(ollamaModels, id: \.name) { model in
                                Text(model.name).tag(model.name)
                            }
                        }
                    }
                    Button("Refresh Models") { fetchOllamaModels() }
                        .controlSize(.small)
                }
            }

            if activeID == "ollama" {
                Section("Connection") {
                    HStack {
                        Button("Test Connection") { testConnection() }
                            .disabled(isTesting)
                        if let connectionStatus {
                            Text(connectionStatus)
                                .font(.caption)
                                .foregroundStyle(connectionStatus.contains("OK") ? .green : .red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            if activeID == "ollama" { fetchOllamaModels() }
        }
    }

    private func fetchOllamaModels() {
        guard let appServices else { return }
        Task { @MainActor in
            ollamaModels = (try? await appServices.modelManager.availableOllamaModels()) ?? []
        }
    }

    private func testConnection() {
        guard let appServices else { return }
        isTesting = true
        connectionStatus = nil
        Task { @MainActor in
            do {
                _ = try await appServices.modelManager.availableOllamaModels()
                connectionStatus = "OK — Ollama is reachable"
            } catch {
                connectionStatus = "Failed: \(error.localizedDescription)"
            }
            isTesting = false
        }
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

// MARK: - Social

private struct SocialSettingsTab: View {
    @Environment(\.appServices) private var appServices

    @State private var blueskyHandle = ""
    @State private var blueskyAppPassword = ""
    @State private var blueskyConnected = false
    @State private var blueskyError: String?
    @State private var blueskyTesting = false

    @State private var mastodonServer = ""
    @State private var mastodonToken = ""
    @State private var mastodonConnected = false
    @State private var mastodonError: String?
    @State private var mastodonTesting = false

    var body: some View {
        Form {
            Section("Bluesky") {
                TextField("Handle (e.g. user.bsky.social)", text: $blueskyHandle)
                SecureField("App Password", text: $blueskyAppPassword)
                HStack {
                    Button("Connect") { connectBluesky() }
                        .disabled(blueskyHandle.isEmpty || blueskyAppPassword.isEmpty || blueskyTesting)
                    if blueskyTesting { ProgressView().controlSize(.small) }
                    if blueskyConnected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if let error = blueskyError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Mastodon") {
                TextField("Server URL (e.g. https://mastodon.social)", text: $mastodonServer)
                SecureField("Access Token", text: $mastodonToken)
                HStack {
                    Button("Connect") { connectMastodon() }
                        .disabled(mastodonServer.isEmpty || mastodonToken.isEmpty || mastodonTesting)
                    if mastodonTesting { ProgressView().controlSize(.small) }
                    if mastodonConnected { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
                if let error = mastodonError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section {
                Text("X, LinkedIn, and Threads use copy-to-clipboard. No account connection needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { checkExistingCredentials() }
    }

    private func connectBluesky() {
        blueskyTesting = true
        blueskyError = nil
        Task {
            guard let services = appServices else { return }
            do {
                let url = URL(string: "https://bsky.social/xrpc/com.atproto.server.createSession")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let body = ["identifier": blueskyHandle, "password": blueskyAppPassword]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    blueskyError = "Invalid credentials"
                    blueskyTesting = false
                    return
                }
                try await services.keychainService.setBlueskyAppPassword(blueskyAppPassword, handle: blueskyHandle)
                let target = BlueskyTarget(handle: blueskyHandle, keychainService: services.keychainService, keychainRef: "bluesky.\(blueskyHandle)")
                await services.socialPostingService.register(target)
                blueskyConnected = true
                blueskyTesting = false
            } catch {
                blueskyError = error.localizedDescription
                blueskyTesting = false
            }
        }
    }

    private func connectMastodon() {
        mastodonTesting = true
        mastodonError = nil
        Task {
            guard let services = appServices else { return }
            do {
                guard let serverURL = URL(string: mastodonServer) else {
                    mastodonError = "Invalid server URL"
                    mastodonTesting = false
                    return
                }
                let verifyURL = serverURL.appendingPathComponent("api/v1/accounts/verify_credentials")
                var request = URLRequest(url: verifyURL)
                request.setValue("Bearer \(mastodonToken)", forHTTPHeaderField: "Authorization")
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    mastodonError = "Invalid token or server"
                    mastodonTesting = false
                    return
                }
                let host = serverURL.host ?? mastodonServer
                try await services.keychainService.setMastodonAccessToken(mastodonToken, serverHost: host)
                let target = MastodonTarget(serverURL: serverURL, keychainService: services.keychainService, keychainRef: "mastodon.\(host)")
                await services.socialPostingService.register(target)
                mastodonConnected = true
                mastodonTesting = false
            } catch {
                mastodonError = error.localizedDescription
                mastodonTesting = false
            }
        }
    }

    private func checkExistingCredentials() {
        Task {
            guard appServices != nil else { return }
            // Credentials are checked when user explicitly connects.
            // Future: persist handle/server in UserDefaults to auto-detect.
        }
    }
}
