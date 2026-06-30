import SwiftUI
import PodedgeCore

/// Notification posted when the assistant input field should gain focus.
extension Notification.Name {
    static let focusAssistantInput = Notification.Name("focusAssistantInput")
}

/// Trailing pane displaying the assistant conversation and input field.
struct AssistantPaneView: View {
    @Environment(\.appServices) private var appServices
    @State private var inputText = ""
    @FocusState private var inputFocused: Bool

    var body: some View {
        if let controller = appServices?.assistantController {
            VStack(spacing: 0) {
                messageList(controller: controller)
                Divider()
                inputBar(controller: controller)
            }
            .frame(width: 320)
            .onReceive(NotificationCenter.default.publisher(for: .focusAssistantInput)) { _ in
                inputFocused = true
            }
        } else {
            Text("Assistant unavailable")
                .foregroundStyle(.secondary)
                .frame(width: 320)
        }
    }

    // MARK: - Message List

    @ViewBuilder
    private func messageList(controller: AssistantController) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(controller.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: controller.messages.count) { _, _ in
                if let last = controller.messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Input Bar

    @ViewBuilder
    private func inputBar(controller: AssistantController) -> some View {
        HStack(spacing: 8) {
            TextField("Ask Podedge…", text: $inputText)
                .textFieldStyle(.plain)
                .focused($inputFocused)
                .disabled(controller.isRunning)
                .onSubmit { send(controller: controller) }
                .accessibilityLabel("Assistant input")

            if controller.isRunning {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    send(controller: controller)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send(controller: AssistantController) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        inputText = ""
        Task {
            await controller.submit(text)
        }
    }
}

// MARK: - Message Bubble

private struct MessageBubble: View {
    let message: AssistantMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message.role == .user ? "You" : "Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if message.isStreaming && message.text.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(message.text)
                    .textSelection(.enabled)
            }

            if let label = message.providerLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            ForEach(message.toolCalls) { call in
                ToolCallRow(call: call)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Assistant"): \(message.text)")
    }
}

// MARK: - Tool Call Row

private struct ToolCallRow: View {
    let call: ToolCallRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(resultText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } label: {
            Label(call.toolName, systemImage: "wrench")
                .font(.caption)
        }
        .accessibilityLabel("Tool call: \(call.toolName)")
    }

    private var resultText: String {
        switch call.result {
        case .success(let data):
            return String(data: data, encoding: .utf8) ?? "(binary)"
        case .failure(let msg):
            return "Error: \(msg)"
        case .needsConfirmation:
            return "Awaiting confirmation…"
        case .none:
            return "Pending…"
        }
    }
}
