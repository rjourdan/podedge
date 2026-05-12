import Foundation
import SwiftData
import Testing

@testable import PodedgeCore

// MARK: - Pure Redaction Tests (no SwiftData)

@Suite("AuditLogService Redaction")
struct AuditLogRedactionTests {

    @Test("Redacts api_key=value patterns")
    func redactsAPIKey() {
        let input = "config: api_key=sk-abc123secret endpoint=https://api.example.com"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("sk-abc123secret"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts Bearer tokens")
    func redactsBearerToken() {
        let input = "Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.sig"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("eyJhbGciOiJIUzI1NiJ9"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts token= patterns")
    func redactsToken() {
        let input = "token=mysecrettoken123"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("mysecrettoken123"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts secret= patterns")
    func redactsSecret() {
        let input = "secret: supersecretvalue"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("supersecretvalue"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts sk- prefixed keys")
    func redactsSKPrefix() {
        let input = "key is sk-abcdefghijklmnopqrstuvwxyz"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("sk-abcdefghijklmnopqrstuvwxyz"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts ghp_ prefixed GitHub tokens")
    func redactsGitHubToken() {
        let input = "github token: ghp_abcdefghijklmnopqrstuvwxyz0123456789"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Leaves clean input unchanged")
    func cleanInputUnchanged() {
        let input = "list all shows with title containing podcast"
        let redacted = AuditLogService.redact(input)
        #expect(redacted == input)
    }

    @Test("Redacts AWS access key IDs")
    func redactsAWSAccessKeyID() {
        let input = "credentials: AKIAIOSFODNN7EXAMPLE"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("AKIAIOSFODNN7EXAMPLE"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts AWS secret access key assignments")
    func redactsAWSSecretAccessKey() {
        let input = "aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("wJalrXUtnFEMI"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts AWS secret key with colon separator")
    func redactsAWSSecretKeyColon() {
        let input = "AWS-Secret-Access-Key: mySecretValue123"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("mySecretValue123"))
        #expect(redacted.contains("[REDACTED]"))
    }

    @Test("Redacts X-Amz-Signature in signed URLs")
    func redactsSignedURLSignature() {
        let input = "https://bucket.s3.amazonaws.com/file.mp3?X-Amz-Signature=abc123def456&X-Amz-Credential=AKID/region/s3/aws4_request&X-Amz-Security-Token=FwoGZX"
        let redacted = AuditLogService.redact(input)
        #expect(!redacted.contains("abc123def456"))
        #expect(!redacted.contains("AKID/region/s3/aws4_request"))
        #expect(!redacted.contains("FwoGZX"))
        #expect(redacted.contains("[REDACTED]"))
    }
}

// MARK: - Pure Model Tests

@Suite("AgentAuditEntry Model")
struct AgentAuditEntryModelTests {

    @Test("Entry stores all fields")
    func storesFields() {
        let id = UUID()
        let now = Date()
        let entry = AgentAuditEntry(
            id: id,
            timestamp: now,
            agentName: "assistant",
            toolName: "list_shows",
            scope: .readOnly,
            inputSummary: "query: all",
            outputSummary: "3 shows",
            durationSeconds: 0.5,
            success: true
        )
        #expect(entry.id == id)
        #expect(entry.timestamp == now)
        #expect(entry.agentName == "assistant")
        #expect(entry.toolName == "list_shows")
        #expect(entry.scope == .readOnly)
        #expect(entry.inputSummary == "query: all")
        #expect(entry.outputSummary == "3 shows")
        #expect(entry.durationSeconds == 0.5)
        #expect(entry.success)
    }

    @Test("Entry defaults id and timestamp")
    func defaults() {
        let entry = AgentAuditEntry(
            agentName: "agent",
            toolName: "tool",
            scope: .mutating,
            inputSummary: "",
            outputSummary: "",
            durationSeconds: 0,
            success: false
        )
        #expect(entry.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        #expect(!entry.success)
    }
}

// MARK: - SwiftData Integration Tests

@Suite("AuditLogService SwiftData", .serialized, .tags(.swiftData))
struct AuditLogServiceTests {

    @MainActor
    private func makeService() throws -> (AuditLogService, ModelContext) {
        let container = TestDatabase.container(for: "auditlog")
        try TestDatabase.reset(container)
        let context = container.mainContext
        return (AuditLogService(modelContext: context), context)
    }

    @Test("Log writes entry with redacted input")
    @MainActor
    func logWritesEntry() throws {
        let (service, context) = try makeService()
        service.log(
            agentName: "assistant",
            toolName: "list_shows",
            scope: .readOnly,
            inputSummary: "api_key=secret123",
            outputSummary: "ok",
            durationSeconds: 0.1,
            success: true
        )
        try context.save()

        let entries = try service.entries()
        #expect(entries.count == 1)
        #expect(entries.first?.inputSummary.contains("secret123") == false)
        #expect(entries.first?.inputSummary.contains("[REDACTED]") == true)
    }

    @Test("Log redacts outputSummary containing signed URLs")
    @MainActor
    func logRedactsOutput() throws {
        let (service, context) = try makeService()
        service.log(
            agentName: "assistant",
            toolName: "upload",
            scope: .mutating,
            inputSummary: "file.mp3",
            outputSummary: "url: https://bucket.s3.amazonaws.com/ep.mp3?X-Amz-Signature=deadbeef",
            durationSeconds: 0.2,
            success: true
        )
        try context.save()

        let entries = try service.entries()
        #expect(entries.first?.outputSummary.contains("deadbeef") == false)
        #expect(entries.first?.outputSummary.contains("[REDACTED]") == true)
    }

    @Test("Query filters by agent name")
    @MainActor
    func queryByAgent() throws {
        let (service, context) = try makeService()
        service.log(agentName: "a1", toolName: "t", scope: .readOnly, inputSummary: "", outputSummary: "", durationSeconds: 0, success: true)
        service.log(agentName: "a2", toolName: "t", scope: .readOnly, inputSummary: "", outputSummary: "", durationSeconds: 0, success: true)
        try context.save()

        let results = try service.entries(agentName: "a1")
        #expect(results.count == 1)
        #expect(results.first?.agentName == "a1")
    }

    @Test("Purge removes entries older than 90 days")
    @MainActor
    func purgeExpired() throws {
        let (service, context) = try makeService()
        let old = AgentAuditEntry(
            timestamp: Calendar.current.date(byAdding: .day, value: -91, to: Date())!,
            agentName: "old",
            toolName: "t",
            scope: .readOnly,
            inputSummary: "",
            outputSummary: "",
            durationSeconds: 0,
            success: true
        )
        context.insert(old)
        service.log(agentName: "new", toolName: "t", scope: .readOnly, inputSummary: "", outputSummary: "", durationSeconds: 0, success: true)
        try context.save()

        try service.purgeExpiredEntries()
        try context.save()

        let remaining = try service.entries()
        #expect(remaining.count == 1)
        #expect(remaining.first?.agentName == "new")
    }
}
