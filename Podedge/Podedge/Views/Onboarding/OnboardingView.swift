import SwiftUI
import SwiftData
import PodedgeCore

/// Stepper onboarding: welcome → show → S3 → OP3 → models → done.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices

    @State private var step: OnboardingStep = .welcome
    @State private var keychainError: String?
    @State private var isSavingHost = false

    // Show fields
    @State private var showTitle = ""
    @State private var showAuthor = ""
    @State private var showCategory = "Technology"
    @State private var ownerEmail = ""
    @State private var ownerName = ""

    // S3 fields
    @State private var hostDisplayName = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var publicBaseURL = ""
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""

    // OP3 fields
    @State private var enableOP3 = true
    @State private var hasExistingOP3 = false
    @State private var existingOP3ShowUUID = ""
    @State private var op3Status: String?

    // AI provider fields
    @State private var aiProviderComplete = false

    // Model download fields
    @State private var models: [TranscriptionModelInfo] = []
    @State private var selectedModel = "mlx-community/parakeet-tdt-0.6b-v3"
    @State private var downloadProgress: [String: Double] = [:]
    @State private var isDownloading = false
    @State private var downloadError: String?

    enum OnboardingStep: Int, CaseIterable {
        case welcome, show, s3, op3, models, aiProvider, done
    }

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator
            Divider()
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            navigationButtons
        }
        .frame(width: 560, height: 480)
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { s in
                Circle()
                    .fill(s.rawValue <= step.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 12)
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch step {
                case .welcome: welcomeStep
                case .show: showStep
                case .s3: s3Step
                case .op3: op3Step
                case .models: modelsStep
                case .aiProvider: aiProviderStep
                case .done: doneStep
                }
            }
            .padding(24)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Welcome to Podedge")
                .font(.largeTitle)
                .fontWeight(.bold)
            Text("Local-first podcast publishing for macOS. Let's set up your first show.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var showStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Your Show")
                .font(.title2)
                .fontWeight(.semibold)
            TextField("Show Title", text: $showTitle)
                .textFieldStyle(.roundedBorder)
            TextField("Author", text: $showAuthor)
                .textFieldStyle(.roundedBorder)
            TextField("Category", text: $showCategory)
                .textFieldStyle(.roundedBorder)
            TextField("Owner Name", text: $ownerName)
                .textFieldStyle(.roundedBorder)
            TextField("Owner Email", text: $ownerEmail)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var s3Step: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("S3 Hosting")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Podedge uploads your audio and RSS feed to an S3 bucket. See the [setup guide](https://github.com/rjourdan/podedge/blob/main/docs/user/s3-hosting-setup.md) for step-by-step instructions.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let keychainError {
                Text(keychainError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            TextField("Display Name", text: $hostDisplayName)
                .textFieldStyle(.roundedBorder)
            TextField("Bucket", text: $bucket)
                .textFieldStyle(.roundedBorder)
            TextField("Region", text: $region)
                .textFieldStyle(.roundedBorder)
            TextField("Public Base URL (e.g. https://d1234.cloudfront.net)", text: $publicBaseURL)
                .textFieldStyle(.roundedBorder)
            TextField("Access Key ID", text: $accessKeyID)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret Access Key", text: $secretAccessKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var op3Step: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download Analytics")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Podedge uses OP3, a free open-source service, to count episode downloads without tracking your listeners.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Enable download analytics", isOn: $enableOP3)
                .accessibilityLabel("Enable OP3 download analytics")

            if enableOP3 {
                Text("Podedge will automatically register your show with OP3 when you publish your first episode. No account or sign-up needed.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                DisclosureGroup("Already using OP3?") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("If you're migrating from another app and already have OP3 analytics for this show, enter your existing OP3 Show UUID below. Podedge will link to your existing data instead of creating a new registration.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Toggle("I have an existing OP3 Show UUID", isOn: $hasExistingOP3)
                            .font(.caption)
                        if hasExistingOP3 {
                            TextField("OP3 Show UUID", text: $existingOP3ShowUUID)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                            Text("Find this at op3.dev under your show's dashboard.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .font(.caption)
            }
        }
    }

    private var modelsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Models")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Podedge uses local AI models for transcription. Download at least one model to continue.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let downloadError {
                Text(downloadError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ForEach(models, id: \.name) { model in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(model.name)
                                .font(.callout)
                            if model.name == "mlx-community/parakeet-tdt-0.6b-v3" {
                                Text("Recommended")
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(.tint.opacity(0.15))
                                    .clipShape(.capsule)
                            }
                        }
                        Text("~\(model.sizeBytes / 1_000_000) MB")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if model.isDownloaded {
                        Label("Downloaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if let progress = downloadProgress[model.name] {
                        ProgressView(value: progress)
                            .frame(width: 80)
                    } else {
                        Button("Download") {
                            downloadModel(model.name)
                        }
                        .controlSize(.small)
                        .disabled(isDownloading)
                    }
                }
                .padding(.vertical, 4)
            }

            Label("Models are stored in ~/Library/Application Support/Podedge/Models/", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .task {
            await loadModels()
        }
    }

    private func loadModels() async {
        guard let appServices else { return }
        models = (try? await appServices.modelManager.availableModels()) ?? []
    }

    private func downloadModel(_ name: String) {
        guard let appServices else { return }
        isDownloading = true
        downloadError = nil
        Task { @MainActor in
            do {
                try await appServices.modelManager.downloadModel(named: name) { fraction in
                    Task { @MainActor in
                        downloadProgress[name] = fraction
                    }
                }
                downloadProgress.removeValue(forKey: name)
                await loadModels()
            } catch {
                downloadError = error.localizedDescription
            }
            isDownloading = false
        }
    }

    private var aiProviderStep: some View {
        AIProviderPickerView(isComplete: $aiProviderComplete)
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("You're All Set!")
                .font(.title)
                .fontWeight(.bold)
            Text("Your show is ready. Drop an MP3 into the sidebar to create your first episode.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Navigation

    private var navigationButtons: some View {
        HStack {
            if step != .welcome {
                Button("Back") {
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue - 1) ?? .welcome }
                }
                .disabled(isSavingHost)
                .accessibilityLabel("Previous step")
            }
            Spacer()
            if step == .done {
                Button("Get Started") {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Complete onboarding")
            } else {
                Button(isSavingHost ? "Saving…" : "Next") {
                    advanceStep()
                }
                .buttonStyle(.borderedProminent)
                .disabled(nextDisabled)
                .accessibilityLabel("Next step")
            }
        }
        .padding(16)
    }

    private var nextDisabled: Bool {
        if isSavingHost { return true }
        if step == .show { return showTitle.isEmpty || showAuthor.isEmpty }
        if step == .models { return !models.contains(where: \.isDownloaded) }
        return false
    }

    private func advanceStep() {
        switch step {
        case .show:
            createShowIfNeeded()
            withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
        case .s3:
            // Await keychain storage before advancing to prevent concurrent modelContext access.
            saveHostThenAdvance()
        default:
            withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
        }
    }

    // MARK: - Data Creation

    private func createShowIfNeeded() {
        guard !showTitle.isEmpty else { return }
        let slug = showTitle
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let show = Show(
            title: showTitle,
            author: showAuthor,
            summary: "",
            category: showCategory,
            ownerEmail: ownerEmail,
            ownerName: ownerName,
            hostBindingID: UUID(),
            feedRemotePath: "shows/\(slug)/feed.xml"
        )
        modelContext.insert(show)
    }

    /// Stores S3 credentials in Keychain, inserts the HostBinding, then advances.
    /// The step only advances after the insert completes — no concurrent modelContext access.
    private func saveHostThenAdvance() {
        guard !bucket.isEmpty, !accessKeyID.isEmpty, let baseURL = URL(string: publicBaseURL) else {
            // No S3 configured — just skip ahead.
            withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
            return
        }
        let keychainRef = "host-\(UUID().uuidString)"
        let credential = HostCredential(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey
        )
        keychainError = nil
        isSavingHost = true
        Task {
            do {
                let keychain = KeychainService()
                try await keychain.storeCredential(credential, forKey: keychainRef)
                let binding = HostBinding(
                    displayName: hostDisplayName.isEmpty ? bucket : hostDisplayName,
                    bucket: bucket,
                    region: region,
                    publicBaseURL: baseURL,
                    keychainRef: keychainRef
                )
                modelContext.insert(binding)
                isSavingHost = false
                withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
            } catch {
                isSavingHost = false
                keychainError = "Failed to store credentials: \(error.localizedDescription)"
            }
        }
    }

    private func finishOnboarding() {
        if enableOP3 {
            let prefixURL = URL(string: "https://op3.dev/e")!
            let binding = AnalyticsBinding(
                provider: "op3",
                externalShowID: hasExistingOP3 && !existingOP3ShowUUID.isEmpty
                    ? existingOP3ShowUUID
                    : nil,
                prefixBaseURL: prefixURL
            )
            modelContext.insert(binding)
            // If no existing UUID, registration happens automatically on first publish
            // via AnalyticsService → OP3AnalyticsProvider.register().
        }
        hasCompletedOnboarding = true
    }
}
