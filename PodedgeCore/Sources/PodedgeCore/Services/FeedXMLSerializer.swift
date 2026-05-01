import Foundation

/// Serializes an ``RSSFeed`` to podcast-compliant RSS 2.0 XML using `XMLDocument`.
public struct FeedXMLSerializer: Sendable {

    /// RFC 2822 date formatter for RSS `<pubDate>` elements.
    private static let rfc2822: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    public init() {}

    /// Serializes the feed to a UTF-8 encoded XML `Data`.
    ///
    /// - Parameter feed: The RSS feed to serialize.
    /// - Returns: Pretty-printed XML data.
    public func serialize(_ feed: RSSFeed) -> Data {
        let root = XMLElement(name: "rss")
        root.addAttribute(attribute("version", value: "2.0"))
        root.addAttribute(attribute("xmlns:itunes", value: "http://www.itunes.com/dtds/podcast-1.0.dtd"))
        root.addAttribute(attribute("xmlns:content", value: "http://purl.org/rss/1.0/modules/content/"))
        root.addAttribute(attribute("xmlns:atom", value: "http://www.w3.org/2005/Atom"))
        root.addAttribute(attribute("xmlns:podcast", value: "https://podcastindex.org/namespace/1.0"))

        let channel = XMLElement(name: "channel")
        root.addChild(channel)

        let ch = feed.channel
        channel.addChild(element("title", value: ch.title))
        channel.addChild(element("link", value: ch.link.absoluteString))
        channel.addChild(element("description", value: ch.description))
        channel.addChild(element("language", value: ch.language))

        if let copyright = ch.copyright {
            channel.addChild(element("copyright", value: copyright))
        }

        // Atom self link
        if let feedURL = ch.feedURL {
            let atomLink = XMLElement(name: "atom:link")
            atomLink.addAttribute(attribute("href", value: feedURL.absoluteString))
            atomLink.addAttribute(attribute("rel", value: "self"))
            atomLink.addAttribute(attribute("type", value: "application/rss+xml"))
            channel.addChild(atomLink)
        }

        // iTunes tags
        channel.addChild(element("itunes:author", value: ch.author))
        channel.addChild(element("itunes:explicit", value: ch.explicit ? "true" : "false"))
        channel.addChild(element("itunes:summary", value: ch.description))

        let owner = XMLElement(name: "itunes:owner")
        owner.addChild(element("itunes:name", value: ch.ownerName))
        owner.addChild(element("itunes:email", value: ch.ownerEmail))
        channel.addChild(owner)

        let cat = XMLElement(name: "itunes:category")
        cat.addAttribute(attribute("text", value: ch.category))
        if let sub = ch.subcategory {
            let subCat = XMLElement(name: "itunes:category")
            subCat.addAttribute(attribute("text", value: sub))
            cat.addChild(subCat)
        }
        channel.addChild(cat)

        if let imageURL = ch.imageURL {
            let img = XMLElement(name: "itunes:image")
            img.addAttribute(attribute("href", value: imageURL.absoluteString))
            channel.addChild(img)
        }

        // Podcasting 2.0
        channel.addChild(element("podcast:guid", value: ch.podcastGUID.uuidString.lowercased()))
        let locked = XMLElement(name: "podcast:locked")
        locked.stringValue = ch.podcastLocked ? "yes" : "no"
        locked.addAttribute(attribute("owner", value: ch.ownerEmail))
        channel.addChild(locked)

        // Items
        for item in feed.items {
            channel.addChild(serializeItem(item))
        }

        let doc = XMLDocument(rootElement: root)
        doc.version = "1.0"
        doc.characterEncoding = "UTF-8"
        return doc.xmlData(options: [.nodePrettyPrint])
    }

    // MARK: - Private

    private func serializeItem(_ item: RSSItem) -> XMLElement {
        let el = XMLElement(name: "item")
        el.addChild(element("title", value: item.title))

        // Fix #4: <guid> must include isPermaLink="false" attribute.
        let guidEl = XMLElement(name: "guid")
        guidEl.stringValue = item.guid
        guidEl.addAttribute(attribute("isPermaLink", value: "false"))
        el.addChild(guidEl)

        el.addChild(element("description", value: item.description))
        el.addChild(element("pubDate", value: Self.rfc2822.string(from: item.pubDate)))

        if let html = item.contentEncoded {
            let encoded = XMLElement(name: "content:encoded")
            encoded.setStringValue(html, resolvingEntities: false)
            el.addChild(encoded)
        }

        let enc = XMLElement(name: "enclosure")
        enc.addAttribute(attribute("url", value: item.enclosureURL.absoluteString))
        enc.addAttribute(attribute("length", value: String(item.enclosureLength)))
        enc.addAttribute(attribute("type", value: item.enclosureType))
        el.addChild(enc)

        el.addChild(element("itunes:episodeType", value: item.episodeType.rawValue))

        if let dur = item.duration {
            let totalSeconds = Int(dur)
            let h = totalSeconds / 3600
            let m = (totalSeconds % 3600) / 60
            let s = totalSeconds % 60
            let formatted = h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
            el.addChild(element("itunes:duration", value: formatted))
        }

        if let season = item.season {
            el.addChild(element("itunes:season", value: String(season)))
        }
        if let episode = item.episode {
            el.addChild(element("itunes:episode", value: String(episode)))
        }
        if let explicit = item.explicit {
            el.addChild(element("itunes:explicit", value: explicit ? "true" : "false"))
        }
        if let subtitle = item.subtitle {
            el.addChild(element("itunes:subtitle", value: subtitle))
        }
        if let imageURL = item.imageURL {
            let img = XMLElement(name: "itunes:image")
            img.addAttribute(attribute("href", value: imageURL.absoluteString))
            el.addChild(img)
        }
        if let chaptersURL = item.chaptersURL {
            let chapters = XMLElement(name: "podcast:chapters")
            chapters.addAttribute(attribute("url", value: chaptersURL.absoluteString))
            chapters.addAttribute(attribute("type", value: "application/json+chapters"))
            el.addChild(chapters)
        }

        // Fix #5: Emit <podcast:transcript> when a transcript URL is present.
        if let transcriptURL = item.transcriptURL {
            let transcript = XMLElement(name: "podcast:transcript")
            transcript.addAttribute(attribute("url", value: transcriptURL.absoluteString))
            transcript.addAttribute(attribute("type", value: "text/vtt"))
            el.addChild(transcript)
        }

        return el
    }

    private func element(_ name: String, value: String) -> XMLElement {
        let el = XMLElement(name: name)
        el.stringValue = value
        return el
    }

    /// Fix #21: Helper to create XML attributes without force-casting.
    private func attribute(_ name: String, value: String) -> XMLNode {
        XMLNode.attribute(withName: name, stringValue: value) as! XMLNode
    }
}
