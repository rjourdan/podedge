import SwiftUI
import SwiftData
import PodedgeCore

/// The main entry point for the Podedge macOS app.
@main
struct PodedgeApp: App {
    /// The composition root owning all application services.
    private let services: AppServices

    /// Checks GitHub for new releases on launch.
    private let updateChecker = UpdateChecker()

    /// Tracks whether the user has completed onboarding.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    /// Monitors scene phase for shutdown.
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try PodedgeSchema.makeContainer()
            services = AppServices(modelContainer: container)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
            .environment(services.confirmationCoordinator)
            .environment(\.appServices, services)
            .sheet(item: Bindable(services.confirmationCoordinator).pendingConfirmation) { item in
                ConfirmationSheetView(item: item) {
                    Task { await services.confirmationCoordinator.confirm() }
                } onCancel: {
                    services.confirmationCoordinator.cancel()
                }
            }
            .task {
                await services.bootstrap()
            }
            .task {
                await NotificationService.shared.requestAuthorization()
            }
            .task {
                await updateChecker.checkForUpdate()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    services.shutdown()
                }
            }
        }
        .modelContainer(services.modelContainer)
        .defaultSize(width: 1100, height: 720)

        MenuBarExtra("Podedge", systemImage: "antenna.radiowaves.left.and.right") {
            MenuBarContentView()
                .modelContainer(services.modelContainer)
        }

        Settings {
            SettingsView()
                .modelContainer(services.modelContainer)
        }
    }
}
