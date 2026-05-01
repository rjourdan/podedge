import SwiftUI
import SwiftData
import PodedgeCore

/// The main entry point for the Podedge macOS app.
@main
struct PodedgeApp: App {
    /// The shared model container created from the PodedgeCore schema.
    private let modelContainer: ModelContainer

    /// The tool registry holding all registered tools.
    private let toolRegistry: ToolRegistry

    /// The broker that mediates tool invocations with confirmation gating.
    private let toolBroker: ToolBroker

    /// Coordinates destructive-action confirmation sheets.
    @State private var confirmationCoordinator = ConfirmationCoordinator()

    /// Checks GitHub for new releases on launch.
    private let updateChecker = UpdateChecker()

    /// Tracks whether the user has completed onboarding.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        do {
            modelContainer = try PodedgeSchema.makeContainer()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        let registry = ToolRegistry()
        self.toolRegistry = registry
        self.toolBroker = ToolBroker(registry: registry)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainWindowView()
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                }
            }
            .environment(confirmationCoordinator)
            .environment(\.toolBroker, toolBroker)
            .sheet(item: $confirmationCoordinator.pendingConfirmation) { item in
                ConfirmationSheetView(item: item) {
                    Task { await confirmationCoordinator.confirm() }
                } onCancel: {
                    confirmationCoordinator.cancel()
                }
            }
            .task {
                await NotificationService.shared.requestAuthorization()
            }
            .task {
                await updateChecker.checkForUpdate()
            }
        }
        .modelContainer(modelContainer)
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra("Podedge", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarContentView()
                .modelContainer(modelContainer)
        }

        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
    }
}

// MARK: - ToolBroker Environment Key

private struct ToolBrokerKey: EnvironmentKey {
    static let defaultValue: ToolBroker? = nil
}

extension EnvironmentValues {
    var toolBroker: ToolBroker? {
        get { self[ToolBrokerKey.self] }
        set { self[ToolBrokerKey.self] = newValue }
    }
}
