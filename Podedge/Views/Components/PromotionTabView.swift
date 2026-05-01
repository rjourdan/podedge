import SwiftUI
import PodedgeCore

/// Promotion tab within the episode editor — generates social media blurbs.
struct PromotionTabView: View {
    let episode: Episode

    @State private var selectedPlatform = "x"
    @State private var generatedText = ""
    @State private var isGenerating = false
    @State private var errorMessage: String?

    private let platforms = [
        ("x", "X (Twitter)", 280),
        ("bluesky", "Bluesky", 300),
        ("mastodon", "Mastodon", 500),
        ("threads", "Threads", 500),
        ("linkedin", "LinkedIn", 3000),
    ]

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

                if let limit = platforms.first(where: { $0.0 == selectedPlatform })?.2 {
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

            HStack {
                // TODO: Wire to SocialBlurbRenderer via ToolBroker once WS5 (LLM integration) is complete.
                Button("Generate Blurb") {
                    generatedText = "Check out \"\(episode.title)\" — our latest episode! 🎙️"
                }
                .disabled(isGenerating)
                .help("AI-powered blurb generation requires WS5 (LLM integration).")
                .accessibilityLabel("Generate social media blurb")

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(generatedText, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .disabled(generatedText.isEmpty)
                .accessibilityLabel("Copy blurb to clipboard")
            }
        }
        .padding()
    }
}
