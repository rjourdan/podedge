import SwiftUI

/// Confirmation sheet presented for destructive tool actions.
struct ConfirmationSheetView: View {
    let item: ConfirmationItem
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)

            Text("Confirm Action")
                .font(.headline)

            Text("Are you sure you want to \(item.displayName)?")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text("This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel action")

                Button("Confirm", role: .destructive, action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Confirm destructive action")
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
