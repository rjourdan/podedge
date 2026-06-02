import SwiftUI
import SwiftData
import PodedgeCore

/// Promotion tab within the episode editor — generates social media blurbs and posts them.
struct PromotionTabView: View {
    let episode: Episode

    @Query private var allSuggestions: [EpisodeSuggestions]
    @Environment(\.appServices) private var appServices

    @State private var selectedPlatform = "x"
    @State private var generatedText = ""
    @State private var isGenerating = false
    @State private var isPosting = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    private let platforms: [(String, String, Int, SocialPostingMode)] = [
        ("x", "X (Twitter)", 280, .copyPaste),
        ("bluesky", "Bluesky", 300, .api),
        ("mastodon", "Mastodon", 500, .api),
        ("threads", "Threads", 500, .copyPaste),
        ("linkedin", "LinkedIn", 3000, .copyPaste),
    ]

    /// Returns the suggestions matching this episode, if any exist.
    private var suggestions: EpisodeSuggestions? {
        allSuggestions.first { $0.episodeID == episode.id }
    }

    /// The current platform tuple.
    private var currentPlatform: (String, String, Int, SocialPostingMode)? {
        platforms.first { $0.0 == selectedPlatform }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Social Promotion")
                .font(.headline)

            Picker("Platform", selection: $selectedPlatform) {
                ForEach(platforms, id: \.0) { platform in
                    Text(platform.1).tag(platform.0)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Social media platform")

            if isGenerating {
                ProgressView("Generating blurb…")
            } else {
                TextEditor(text: $generatedText)
                    .frame(minHeight: 120)
                    .border(.separator)
                    .accessibilityLabel("Generated social media text")

                if let limit = currentPlatform?.2 {
                    HStack {
                        Text("\(generatedText.count)/\(limit) characters")
                            .font(.caption)
                            .foregroundStyle(generatedText.count > limit ? .red : .secondary)
                        Spacer()
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            HStack {
                Button("Generate Blurb") {
                    if let suggestions {
                        generatedText = blurb(for: selectedPlatform, from: suggestions)
                    } else {
                        Task {
                            guard let services = appServices else { return }
                            let job = Job(kind: .generateMetadata, targetID: episode.id)
                            let context = services.modelContainer.mainContext
                            context.insert(job)
                            try? context.save()
                        }
                    }
                }
                .disabled(isGenerating)
                .accessibilityLabel("Generate social media blurb")

                Spacer()

                if let platform = currentPlatform {
                    if platform.3 == .api {
                        if let services = appServices {
                            ToolButton(
                                title: "Post",
                                toolName: "social.post",
                                input: { encodeSocialPost(platformID: platform.0) },
                                broker: services.toolBroker,
                                caller: AppCaller(),
                                systemImage: "paperplane"
                            )
                            .disabled(generatedText.isEmpty || isPosting)
                        }
                    } else {
                        Button {
                            copyToClipboard()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .disabled(generatedText.isEmpty)
                        .accessibilityLabel("Copy blurb to clipboard")
                    }
                }
            }
        }
        .padding()
        .alert("Posting Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onChange(of: selectedPlatform) { _, newValue in
            if let suggestions {
                generatedText = blurb(for: newValue, from: suggestions)
            }
        }
        .onAppear {
            if generatedText.isEmpty, let suggestions {
                generatedText = blurb(for: selectedPlatform, from: suggestions)
            }
        }
    }

    // MARK: - Actions

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(generatedText, forType: .string)
        showStatus("Copied!")
    }

    private func encodeSocialPost(platformID: String) -> Data {
        let payload: [String: String] = [
            "episodeID": episode.id.uuidString,
            "platformID": platformID,
            "text": generatedText
        ]
        return (try? JSONEncoder().encode(payload)) ?? Data()
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    // MARK: - Helpers

    private func blurb(for platform: String, from suggestions: EpisodeSuggestions) -> String {
        switch platform {
        case "x": return suggestions.blurbTwitter
        case "bluesky": return suggestions.blurbBluesky
        case "mastodon": return suggestions.blurbMastodon
        case "threads": return suggestions.blurbThreads
        case "linkedin": return suggestions.blurbLinkedIn
        default: return ""
        }
    }
}
