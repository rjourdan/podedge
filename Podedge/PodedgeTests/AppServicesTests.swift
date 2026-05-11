import Testing
import SwiftData
import PodedgeCore
@testable import Podedge

@Suite("AppServices — Composition Root")
@MainActor
struct AppServicesTests {

    private func makeServices() throws -> AppServices {
        let container = try PodedgeSchema.makeContainer(inMemory: true)
        return AppServices(modelContainer: container)
    }

    @Test("Every JobKind has a registered handler after bootstrap", arguments: JobKind.allCases)
    func jobKindHasHandler(kind: JobKind) async throws {
        let services = try makeServices()
        await services.bootstrap()
        let handler = services.jobScheduler.handler(for: kind)
        #expect(handler != nil, "No handler registered for \(kind)")
    }

    @Test("Bootstrap is idempotent — calling twice does not crash")
    func bootstrapIdempotent() async throws {
        let services = try makeServices()
        await services.bootstrap()
        await services.bootstrap()
        for kind in JobKind.allCases {
            #expect(services.jobScheduler.handler(for: kind) != nil)
        }
    }

    @Test("No handlers registered before bootstrap")
    func noHandlersBeforeBootstrap() throws {
        let services = try makeServices()
        for kind in JobKind.allCases {
            #expect(services.jobScheduler.handler(for: kind) == nil)
        }
    }

    @Test("Shutdown stops the scheduler without crashing")
    func shutdownDoesNotCrash() async throws {
        let services = try makeServices()
        await services.bootstrap()
        services.shutdown()
    }
}
