/// The kind of podcast hosting backend.
public enum HostKind: String, Codable, Sendable {
    /// Amazon S3 or S3-compatible object storage.
    case s3
    // v1.1+: .r2, .b2, .sftp, .webdav
}
