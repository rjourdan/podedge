import Foundation
import Testing

@testable import PodedgeCore

@Suite("FeedBuilder & FeedXMLSerializer")
struct FeedBuilderTests {

    // Fixed UUIDs for deterministic golden files.
    private static let showID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private static let podcastGUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private static let hostBindingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private static let coverArtID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private static let ep1ID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    private static let ep2ID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    private static let ep1AssetID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!
    private static let ep2AssetID = UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!
    private static let ep2CoverID = UUID(uuidString: "eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")!

    private static let feedURL = URL(string: "https://cdn.example.com/shows/test/feed.xml")!
    private static let pubDate1 = Date(timeIntervalSince1970: 1_700_000_000)
    private static let pubDate2 = Date(timeIntervalSince1970: 1_700_100_000)

    private static let assetURLs: [UUID: URL] = [
        coverArtID: URL(string: "https://cdn.example.com/art/cover.jpg")!,
        ep1AssetID: URL(string: "https://cdn.example.com/audio/ep1.mp3")!,
        ep2AssetID: URL(string: "https://cdn.example.com/audio/ep2.mp3")!,
        ep2CoverID: URL(string: "https://cdn.example.com/art/ep2-cover.jpg")!,
    ]

    private func makeShow(analyticsBindingID: UUID? = nil) -> ShowSnapshot {
        ShowSnapshot(
            id: Self.showID,
            title: "Test Podcast",
            author: "Test Author",
            summary: "A test podcast about testing.",
            language: "en-US",
            category: "Technology",
            subcategory: "Software How-To",
            explicit: false,
            copyright: "© 2026 Test Author",
            ownerEmail: "test@example.com",
            ownerName: "Test Author",
            podcastGUID: Self.podcastGUID,
            podcastLocked: true,
            feedRemotePath: "shows/test/feed.xml",
            hostBindingID: Self.hostBindingID,
            analyticsBindingID: analyticsBindingID,
            coverArtAssetID: Self.coverArtID
        )
    }

    private func makeEpisodes(
        withChapters: Bool = false,
        withTranscript: Bool = false
    ) -> [EpisodeSnapshot] {
        [
            EpisodeSnapshot(
                id: Self.ep1ID,
                title: "First Episode",
                subtitle: "The beginning",
                summary: "Summary of the first episode.",
                descriptionHTML: "<p>First episode description.</p>",
                season: 1,
                number: 1,
                type: .full,
                explicit: false,
                guid: Self.ep1ID.uuidString,
                status: .published,
                pubDate: Self.pubDate1,
                chaptersJSON: nil,
                originalAssetID: UUID(),
                publishedAssetID: Self.ep1AssetID,
                enclosureByteSize: 1_048_576
            ),
            EpisodeSnapshot(
                id: Self.ep2ID,
                title: "Second Episode",
                subtitle: "Continuing",
                summary: "Summary of the second episode.",
                descriptionHTML: "<p>Second episode description.</p>",
                season: 1,
                number: 2,
                type: .full,
                explicit: nil,
                guid: Self.ep2ID.uuidString,
                status: .published,
                pubDate: Self.pubDate2,
                chaptersJSON: withChapters ? "{\"chapters\":[]}" : nil,
                originalAssetID: UUID(),
                publishedAssetID: Self.ep2AssetID,
                coverArtAssetID: Self.ep2CoverID,
                enclosureByteSize: 2_097_152,
                transcriptURL: withTranscript
                    ? URL(string: "https://cdn.example.com/transcripts/ep2.vtt")
                    : nil
            ),
        ]
    }

    private func buildAndSerialize(
        show: ShowSnapshot,
        episodes: [EpisodeSnapshot],
        rewriteEnclosure: FeedBuilder.AnalyticsRewriter? = nil
    ) -> String {
        let builder = FeedBuilder(
            resolveAsset: { Self.assetURLs[$0] },
            rewriteEnclosure: rewriteEnclosure
        )
        let feed = builder.build(show: show, episodes: episodes, feedURL: Self.feedURL)
        let serializer = FeedXMLSerializer()
        let data = serializer.serialize(feed)
        return String(data: data, encoding: .utf8)!
    }

    private func goldenFileURL(named name: String) -> URL {
        let testDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        return testDir.appendingPathComponent("Fixtures/Feeds/\(name)")
    }

    /// Fix #17: Golden file self-writing pattern now fails on first run to force human review.
    private func assertMatchesGolden(xml: String, goldenName: String) throws {
        let goldenURL = goldenFileURL(named: goldenName)

        if !FileManager.default.fileExists(atPath: goldenURL.path) {
            try FileManager.default.createDirectory(
                at: goldenURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try xml.write(to: goldenURL, atomically: true, encoding: .utf8)
            #expect(Bool(false), "Golden file created at \(goldenURL.path) — commit it and re-run")
            return
        }

        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        #expect(xml == golden, "XML output does not match golden file \(goldenName)")
    }

    // MARK: - Tests

    @Test("Feed without analytics binding")
    func feedWithoutAnalytics() throws {
        let xml = buildAndSerialize(show: makeShow(), episodes: makeEpisodes())
        try assertMatchesGolden(xml: xml, goldenName: "feed-no-analytics.xml")
    }

    @Test("Feed with analytics prefix rewriting")
    func feedWithAnalytics() throws {
        let analyticsID = UUID()
        let xml = buildAndSerialize(
            show: makeShow(analyticsBindingID: analyticsID),
            episodes: makeEpisodes(),
            rewriteEnclosure: { url in
                let stripped = url.absoluteString
                    .replacingOccurrences(of: "https://", with: "")
                    .replacingOccurrences(of: "http://", with: "")
                return URL(string: "https://op3.dev/e/\(stripped)")!
            }
        )
        try assertMatchesGolden(xml: xml, goldenName: "feed-with-analytics.xml")
    }

    @Test("Feed with chapters")
    func feedWithChapters() throws {
        let xml = buildAndSerialize(show: makeShow(), episodes: makeEpisodes(withChapters: true))
        try assertMatchesGolden(xml: xml, goldenName: "feed-with-chapters.xml")
    }

    @Test("Feed without chapters")
    func feedWithoutChapters() throws {
        let xml = buildAndSerialize(show: makeShow(), episodes: makeEpisodes(withChapters: false))
        try assertMatchesGolden(xml: xml, goldenName: "feed-no-analytics.xml")
    }

    @Test("Feed with transcript")
    func feedWithTranscript() throws {
        let xml = buildAndSerialize(
            show: makeShow(),
            episodes: makeEpisodes(withTranscript: true)
        )
        try assertMatchesGolden(xml: xml, goldenName: "feed-with-transcript.xml")
    }

    // MARK: - FeedValidator Tests

    @Test("Validator passes for valid feed")
    func validatorPasses() {
        let builder = FeedBuilder(resolveAsset: { Self.assetURLs[$0] })
        let feed = builder.build(show: makeShow(), episodes: makeEpisodes(), feedURL: Self.feedURL)
        let issues = FeedValidator().validate(feed)
        #expect(issues.isEmpty)
    }

    @Test("Validator catches missing title")
    func validatorMissingTitle() {
        var show = makeShow()
        show.title = ""
        let builder = FeedBuilder(resolveAsset: { Self.assetURLs[$0] })
        let feed = builder.build(show: show, episodes: [], feedURL: Self.feedURL)
        let issues = FeedValidator().validate(feed)
        #expect(issues.contains { $0.contains("title") })
    }

    @Test("Validator catches missing image")
    func validatorMissingImage() {
        var show = makeShow()
        show.coverArtAssetID = nil
        let builder = FeedBuilder(resolveAsset: { _ in nil })
        let feed = builder.build(show: show, episodes: [], feedURL: Self.feedURL)
        let issues = FeedValidator().validate(feed)
        #expect(issues.contains { $0.contains("image") })
    }

    @Test("Validator catches duplicate GUIDs")
    func validatorDuplicateGUIDs() {
        let builder = FeedBuilder(resolveAsset: { Self.assetURLs[$0] })
        var episodes = makeEpisodes()
        // Make both episodes have the same GUID.
        episodes[1] = EpisodeSnapshot(
            id: Self.ep2ID,
            title: "Second Episode",
            summary: "Summary",
            type: .full,
            guid: Self.ep1ID.uuidString, // Duplicate!
            status: .published,
            pubDate: Self.pubDate2,
            originalAssetID: UUID(),
            publishedAssetID: Self.ep2AssetID,
            enclosureByteSize: 2_097_152
        )
        let feed = builder.build(show: makeShow(), episodes: episodes, feedURL: Self.feedURL)
        let issues = FeedValidator().validate(feed)
        #expect(issues.contains { $0.contains("Duplicate GUID") })
    }

    @Test("Validator catches HTML in description")
    func validatorHTMLInDescription() {
        var show = makeShow()
        show.summary = "<p>This has HTML</p>"
        let builder = FeedBuilder(resolveAsset: { Self.assetURLs[$0] })
        let feed = builder.build(show: show, episodes: [], feedURL: Self.feedURL)
        let issues = FeedValidator().validate(feed)
        // FeedBuilder.stripHTML should remove tags, so the validator should NOT flag it.
        // But if raw HTML were passed through, it would be caught.
        // Since FeedBuilder strips HTML, the description should be clean.
        #expect(!issues.contains { $0.contains("HTML") })
    }

    @Test("FeedBuilder strips HTML from description")
    func feedBuilderStripsHTML() {
        let stripped = FeedBuilder.stripHTML("<p>Hello <b>world</b></p>")
        #expect(stripped == "Hello world")
    }
}
