import SwiftUI
import SwiftData
import PodedgeCore

/// Stepper onboarding: welcome → show → S3 → OP3 → models → done.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.modelContext) private var modelContext

    @State private var step: OnboardingStep = .welcome
    @State private var keychainError: String?

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
    @State private var op3PrefixURL = "https://op3.dev/e"
    @State private var skipOP3 = false

    enum OnboardingStep: Int, CaseIterable {
        case welcome, show, s3, op3, models, done
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
                case .welcome:
                    welcomeStep
                case .show:
                    showStep
                case .s3:
                    s3Step
                case .op3:
                    op3Step
                case .models:
                    modelsStep
                case .done:
                    doneStep
                }
            }
            .padding(24)
        }
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 56))
                .foregroundStyle(.accent)
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
            Text("Configure your S3-compatible storage for hosting audio and feeds.")
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
            TextField("Public Base URL", text: $publicBaseURL)
                .textFieldStyle(.roundedBorder)
            TextField("Access Key ID", text: $accessKeyID)
                .textFieldStyle(.roundedBorder)
            SecureField("Secret Access Key", text: $secretAccessKey)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var op3Step: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OP3 Analytics")
                .font(.title2)
                .fontWeight(.semibold)
            Text("OP3 provides open podcast analytics. This step is optional.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Skip OP3 setup", isOn: $skipOP3)
            if !skipOP3 {
                TextField("OP3 Prefix URL", text: $op3PrefixURL)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var modelsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Models")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Podedge uses local AI models for transcription. Models can be downloaded later from Settings → Models.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Label("Models are stored in ~/Library/Application Support/Podedge/Models/", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
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
                Button("Next") {
                    if step == .show { createShowIfNeeded() }
                    if step == .s3 { createHostIfNeeded() }
                    withAnimation { step = OnboardingStep(rawValue: step.rawValue + 1) ?? .done }
                }
                .buttonStyle(.borderedProminent)
                .disabled(step == .show && (showTitle.isEmpty || showAuthor.isEmpty))
                .accessibilityLabel("Next step")
            }
        }
        .padding(16)
    }

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

    private func createHostIfNeeded() {
        guard !bucket.isEmpty, !accessKeyID.isEmpty, let baseURL = URL(string: publicBaseURL) else { return }
        let keychainRef = "host-\(UUID().uuidString)"
        let credential = HostCredential(
            accessKeyID: accessKeyID,
            secretAccessKey: secretAccessKey
        )
        keychainError = nil
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
            } catch {
                keychainError = "Failed to store credentials: \(error.localizedDescription)"
            }
        }
    }

    private func finishOnboarding() {
        if !skipOP3, let url = URL(string: op3PrefixURL) {
            let binding = AnalyticsBinding(prefixBaseURL: url)
            modelContext.insert(binding)
        }
        hasCompletedOnboarding = true
    }
}
