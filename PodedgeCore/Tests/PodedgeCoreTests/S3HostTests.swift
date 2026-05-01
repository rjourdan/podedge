import Foundation
import CryptoKit
import Testing

@testable import PodedgeCore

/// Thread-safe array for collecting values from `@Sendable` closures.
final class LockedArray<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [T] = []
    var values: [T] { lock.withLock { _values } }
    func append(_ value: T) { lock.withLock { _values.append(value) } }
}

@Suite("S3Host", .serialized)
struct S3HostTests {

    /// Clears stubs from the previous test in this suite. Called automatically
    /// by Swift Testing before each `@Test` (new struct instance per test).
    /// Uses scoped removal instead of `reset()` to avoid interfering with
    /// stub-using suites that run in parallel.
    init() {
        StubURLProtocol.removeStubs(withPathContaining: "s3host-")
    }

    private func makeHost(session: URLSession = makeStubSession()) -> S3Host {
        S3Host(
            bucket: "test-bucket",
            region: "us-east-1",
            prefix: "podcasts",
            publicBaseURL: URL(string: "https://cdn.example.com/podcasts")!,
            credential: HostCredential(
                accessKeyID: "AKIAIOSFODNN7EXAMPLE",
                secretAccessKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
            ),
            session: session
        )
    }

    @Test("publicURL builds correct URL from remote path")
    func publicURL() {
        let host = makeHost()
        let url = host.publicURL(for: "episodes/ep1.mp3")
        #expect(url.absoluteString == "https://cdn.example.com/podcasts/episodes/ep1.mp3")
    }

    @Test("PUT uploads file and returns public URL")
    func putUploads() async throws {
        // Stub returns 200 for HEAD (no matching ETag) and for PUT.
        StubURLProtocol.stub(path: "s3host-put-ok.mp3", response: .init(statusCode: 200))

        let host = makeHost()
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("s3host-put-ok.mp3")
        try Data("fake audio".utf8).write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let progressValues = LockedArray<Double>()
        let url = try await host.put(
            localURL: tmpFile,
            remotePath: "episodes/s3host-put-ok.mp3",
            contentType: "audio/mpeg",
            progress: { progressValues.append($0) }
        )

        #expect(url.absoluteString == "https://cdn.example.com/podcasts/episodes/s3host-put-ok.mp3")
        #expect(progressValues.values.contains(0.0))
        #expect(progressValues.values.contains(1.0))
    }

    @Test("PUT throws on non-2xx response")
    func putThrowsOnError() async throws {
        StubURLProtocol.stub(path: "s3host-put-fail.mp3", response: .init(statusCode: 403))

        let host = makeHost()
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("s3host-put-fail.mp3")
        try Data("fake".utf8).write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        await #expect(throws: PodedgeError.self) {
            try await host.put(
                localURL: tmpFile,
                remotePath: "episodes/s3host-put-fail.mp3",
                contentType: "audio/mpeg",
                progress: { _ in }
            )
        }
    }

    @Test("PUT skips upload when HEAD returns matching ETag (idempotency)")
    func putSkipsWhenETagMatches() async throws {
        let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent("s3host-idempotent.mp3")
        let content = Data("idempotent content".utf8)
        try content.write(to: tmpFile)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        // Compute MD5 of the content to simulate a matching S3 ETag.
        let md5 = Insecure.MD5.hash(data: content)
        let md5Hex = md5.map { String(format: "%02x", $0) }.joined()

        StubURLProtocol.stub(
            path: "s3host-idempotent.mp3",
            response: .init(
                statusCode: 200,
                headers: ["ETag": "\"\(md5Hex)\"", "Content-Length": "\(content.count)"]
            )
        )

        let host = makeHost()
        let url = try await host.put(
            localURL: tmpFile,
            remotePath: "episodes/s3host-idempotent.mp3",
            contentType: "audio/mpeg",
            progress: { _ in }
        )

        #expect(url.absoluteString == "https://cdn.example.com/podcasts/episodes/s3host-idempotent.mp3")
    }

    @Test("DELETE succeeds on 204")
    func deleteSucceeds() async throws {
        StubURLProtocol.stub(path: "s3host-delete.mp3", response: .init(statusCode: 204))

        let host = makeHost()
        try await host.delete(remotePath: "episodes/s3host-delete.mp3")
    }

    @Test("HEAD returns exists=true with metadata")
    func headExists() async throws {
        StubURLProtocol.stub(
            path: "s3host-head-exists.mp3",
            response: .init(
                statusCode: 200,
                headers: ["Content-Length": "12345", "ETag": "\"abc123\""]
            )
        )

        let host = makeHost()
        let result = try await host.head(remotePath: "episodes/s3host-head-exists.mp3")

        #expect(result.exists)
        #expect(result.contentLength == 12345)
        #expect(result.eTag == "\"abc123\"")
    }

    @Test("HEAD returns exists=false on 404")
    func headNotFound() async throws {
        StubURLProtocol.stub(path: "s3host-head-missing.mp3", response: .init(statusCode: 404))

        let host = makeHost()
        let result = try await host.head(remotePath: "episodes/s3host-head-missing.mp3")

        #expect(!result.exists)
    }

    @Test("SigV4 date formatting")
    func sigV4DateFormatting() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let stamp = SigV4.dateStamp(date)
        #expect(stamp == "20231114")
        let amz = SigV4.amzDate(date)
        #expect(amz.hasPrefix("20231114T"))
        #expect(amz.hasSuffix("Z"))
        #expect(amz.count == 16)
    }

    @Test("SigV4 SHA-256 hash")
    func sigV4SHA256() {
        let hash = SigV4.sha256Hex(Data())
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test("SigV4 signing key derivation produces 32 bytes")
    func sigV4SigningKey() {
        let key = SigV4.signingKey(secret: "secret", dateStamp: "20231114", region: "us-east-1", service: "s3")
        #expect(key.count == 32)
    }

    @Test("SigV4 uriEncode handles spaces and Unicode")
    func sigV4URIEncode() {
        let encoded = SigV4.uriEncode("/podcasts/my episode.mp3")
        #expect(encoded == "/podcasts/my%20episode.mp3")

        let unicode = SigV4.uriEncode("/podcasts/café.mp3")
        #expect(unicode.contains("caf%C3%A9"))
    }

    @Test("SigV4 signing key matches AWS test vector")
    func sigV4AWSTestVector() {
        // AWS test vector from:
        // https://docs.aws.amazon.com/general/latest/gr/sigv4-calculate-signature.html
        let key = SigV4.signingKey(
            secret: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY",
            dateStamp: "20150830",
            region: "us-east-1",
            service: "iam"
        )
        let hex = key.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "c4afb1cc5771d871763a393e44b703571b55cc28424d1a5e86da6ed3c154a4b9")
    }
}
