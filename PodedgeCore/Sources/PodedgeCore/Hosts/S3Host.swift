import Foundation
import CommonCrypto
import CryptoKit
import os

/// S3-compatible podcast host using AWS Signature Version 4 for authentication.
///
/// Supports any S3-compatible backend (AWS S3, Cloudflare R2, MinIO, etc.)
/// by accepting a custom endpoint URL in the credential.
public struct S3Host: PodcastHost, Sendable {

    private let bucket: String
    private let region: String
    private let prefix: String
    private let publicBaseURL: URL
    private let accessKeyID: String
    private let secretAccessKey: String
    private let endpoint: URL?
    private let session: URLSession
    private let logger = PodedgeLogger.upload

    /// Creates an S3 host.
    ///
    /// - Parameters:
    ///   - bucket: The S3 bucket name.
    ///   - region: The AWS region, e.g. `"us-east-1"`.
    ///   - prefix: Optional key prefix (path) within the bucket.
    ///   - publicBaseURL: The base URL for public access to uploaded files.
    ///   - credential: AWS credentials (access key, secret, optional custom endpoint).
    ///   - session: URL session to use for requests. Defaults to `.shared`.
    public init(
        bucket: String,
        region: String,
        prefix: String = "",
        publicBaseURL: URL,
        credential: HostCredential,
        session: URLSession = .shared
    ) {
        self.bucket = bucket
        self.region = region
        self.prefix = prefix
        self.publicBaseURL = publicBaseURL
        self.accessKeyID = credential.accessKeyID
        self.secretAccessKey = credential.secretAccessKey
        self.endpoint = credential.endpoint
        self.session = session
    }

    // MARK: - PodcastHost

    public func put(
        localURL: URL,
        remotePath: String,
        contentType: String,
        progress: @Sendable (Double) -> Void
    ) async throws -> URL {
        // Fix #3: HEAD-before-PUT idempotency check.
        // For non-multipart S3 uploads, the ETag is the hex-encoded MD5 of the object.
        // If the remote object already exists and its ETag matches the local file's MD5,
        // skip the upload entirely.
        let headResult = try await head(remotePath: remotePath)
        if headResult.exists, let remoteETag = headResult.eTag {
            let localMD5 = try md5Hex(fileAt: localURL)
            let normalizedETag = remoteETag.replacingOccurrences(of: "\"", with: "")
            if normalizedETag == localMD5 {
                return publicURL(for: remotePath)
            }
        }

        let key = fullKey(for: remotePath)
        let url = endpointURL(for: key)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")

        // Fix #2: Stream file from disk instead of loading into memory.
        // Use UNSIGNED-PAYLOAD sentinel so we don't need to hash the file body for SigV4.
        // TODO: For files >5 GB, implement S3 multipart upload.
        let signed = sign(request: request, payloadHash: "UNSIGNED-PAYLOAD", method: "PUT", key: key)
        progress(0.0)
        let (_, response) = try await session.upload(for: signed, fromFile: localURL)
        progress(1.0)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PodedgeError.uploadFailed(reason: "S3 PUT returned status \(code)")
        }

        return publicURL(for: remotePath)
    }

    public func delete(remotePath: String) async throws {
        let key = fullKey(for: remotePath)
        let url = endpointURL(for: key)

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let signed = sign(request: request, payloadHash: SigV4.sha256Hex(Data()), method: "DELETE", key: key)
        let (_, response) = try await session.data(for: signed)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) || http.statusCode == 204 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw PodedgeError.uploadFailed(reason: "S3 DELETE returned status \(code)")
        }
    }

    public func publicURL(for remotePath: String) -> URL {
        publicBaseURL.appendingPathComponent(remotePath)
    }

    public func head(remotePath: String) async throws -> HostHeadResult {
        let key = fullKey(for: remotePath)
        let url = endpointURL(for: key)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        let signed = sign(request: request, payloadHash: SigV4.sha256Hex(Data()), method: "HEAD", key: key)
        let (_, response) = try await session.data(for: signed)

        guard let http = response as? HTTPURLResponse else {
            throw PodedgeError.hostUnreachable(reason: "No HTTP response from S3 HEAD")
        }

        if http.statusCode == 404 {
            return HostHeadResult(exists: false)
        }

        guard (200...299).contains(http.statusCode) else {
            throw PodedgeError.hostUnreachable(reason: "S3 HEAD returned status \(http.statusCode)")
        }

        let contentLength = (http.value(forHTTPHeaderField: "Content-Length")).flatMap(Int64.init)
        let eTag = http.value(forHTTPHeaderField: "ETag")

        return HostHeadResult(exists: true, contentLength: contentLength, eTag: eTag)
    }

    // MARK: - Private Helpers

    /// Computes the MD5 hex digest of a file on disk by streaming in chunks.
    ///
    /// MD5 is used here solely for S3 ETag comparison, not for security.
    private func md5Hex(fileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        var hasher = Insecure.MD5()
        let chunkSize = 1_048_576 // 1 MB
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: chunkSize)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - SigV4 Signing

    private func fullKey(for remotePath: String) -> String {
        prefix.isEmpty ? remotePath : "\(prefix)/\(remotePath)"
    }

    private func endpointURL(for key: String) -> URL {
        let base = endpoint ?? URL(string: "https://\(bucket).s3.\(region).amazonaws.com")!
        return base.appendingPathComponent(key)
    }

    /// Signs a request using AWS Signature Version 4.
    ///
    /// - Parameters:
    ///   - request: The URL request to sign.
    ///   - payloadHash: SHA-256 hex hash of the body, or `"UNSIGNED-PAYLOAD"` for streaming uploads.
    ///   - method: HTTP method string.
    ///   - key: The S3 object key.
    /// - Returns: A new request with SigV4 authorization headers.
    private func sign(request: URLRequest, payloadHash: String, method: String, key: String) -> URLRequest {
        var req = request
        let now = Date()
        let dateStamp = SigV4.dateStamp(now)
        let amzDate = SigV4.amzDate(now)
        let host = req.url!.host!

        req.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        req.setValue(host, forHTTPHeaderField: "Host")
        req.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        // Fix #13: Build signedHeaders and canonicalHeaders from a sorted dictionary
        // to prevent future header additions from silently breaking signing.
        let headersToSign: [String: String] = [
            "host": host,
            "x-amz-content-sha256": payloadHash,
            "x-amz-date": amzDate,
        ]
        let sortedKeys = headersToSign.keys.sorted()
        let signedHeaders = sortedKeys.joined(separator: ";")
        let canonicalHeaders = sortedKeys.map { "\($0):\(headersToSign[$0]!)\n" }.joined()

        // Fix #12: Use path(percentEncoded: false) to get the raw path, then apply
        // S3's URI encoding. This avoids double-encoding from the deprecated .path property.
        let rawPath = req.url!.path(percentEncoded: false)
        let query = req.url!.query ?? ""
        let canonicalRequest = [
            method,
            SigV4.uriEncode(rawPath),
            query,
            canonicalHeaders,
            signedHeaders,
            payloadHash,
        ].joined(separator: "\n")

        let scope = "\(dateStamp)/\(region)/s3/aws4_request"
        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            scope,
            SigV4.sha256Hex(canonicalRequest.data(using: .utf8)!),
        ].joined(separator: "\n")

        let signingKey = SigV4.signingKey(
            secret: secretAccessKey,
            dateStamp: dateStamp,
            region: region,
            service: "s3"
        )
        let signature = SigV4.hmacSHA256Hex(key: signingKey, data: stringToSign.data(using: .utf8)!)

        let auth = "AWS4-HMAC-SHA256 Credential=\(accessKeyID)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        return req
    }
}

// MARK: - SigV4 Helpers

/// Low-level AWS Signature Version 4 cryptographic helpers.
enum SigV4 {

    static func dateStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    static func amzDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.string(from: date)
    }

    static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA256(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    static func hmacSHA256(key: Data, data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        key.withUnsafeBytes { keyPtr in
            data.withUnsafeBytes { dataPtr in
                CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA256), keyPtr.baseAddress, key.count, dataPtr.baseAddress, data.count, &hash)
            }
        }
        return Data(hash)
    }

    static func hmacSHA256Hex(key: Data, data: Data) -> String {
        hmacSHA256(key: key, data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func signingKey(secret: String, dateStamp: String, region: String, service: String) -> Data {
        let kDate = hmacSHA256(key: "AWS4\(secret)".data(using: .utf8)!, data: dateStamp.data(using: .utf8)!)
        let kRegion = hmacSHA256(key: kDate, data: region.data(using: .utf8)!)
        let kService = hmacSHA256(key: kRegion, data: service.data(using: .utf8)!)
        return hmacSHA256(key: kService, data: "aws4_request".data(using: .utf8)!)
    }

    static func uriEncode(_ path: String) -> String {
        // S3 requires each path segment to be percent-encoded individually.
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { segment in
                segment.addingPercentEncoding(withAllowedCharacters: .s3Allowed) ?? String(segment)
            }
            .joined(separator: "/")
    }
}

private extension CharacterSet {
    /// Characters allowed in S3 URI path segments (unreserved per RFC 3986).
    static let s3Allowed: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()
}
