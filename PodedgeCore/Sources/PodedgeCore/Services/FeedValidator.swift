import Foundation

/// Validates an ``RSSFeed`` against podcast RSS requirements.
///
/// Returns an array of human-readable validation issues. An empty array
/// means the feed is valid.
public struct FeedValidator: Sendable {

    public init() {}

    /// Validates the feed and returns any issues found.
    ///
    /// - Parameter feed: The RSS feed to validate.
    /// - Returns: An array of validation issue descriptions. Empty if valid.
    public func validate(_ feed: RSSFeed) -> [String] {
        var issues: [String] = []
        let ch = feed.channel

        if ch.title.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Channel title is required.")
        }
        if ch.author.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Channel author is required.")
        }
        if ch.description.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Channel description is required.")
        }
        if ch.ownerEmail.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("Owner email is required.")
        }
        if ch.category.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append("At least one iTunes category is required.")
        }
        if ch.imageURL == nil {
            issues.append("Channel image URL is required for directory listing.")
        }

        // Fix #15: Validate that description fields do not contain HTML.
        if ch.description.range(of: "<[a-zA-Z]", options: .regularExpression) != nil {
            issues.append("Channel description appears to contain HTML. Use plain text.")
        }

        var seenGUIDs = Set<String>()
        for (index, item) in feed.items.enumerated() {
            let prefix = "Item[\(index)] (\(item.guid)):"
            if item.title.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("\(prefix) title is required.")
            }
            if item.guid.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("\(prefix) guid is required.")
            }
            if item.enclosureURL.absoluteString.isEmpty {
                issues.append("\(prefix) enclosure URL is required.")
            }
            if item.description.range(of: "<[a-zA-Z]", options: .regularExpression) != nil {
                issues.append("\(prefix) description appears to contain HTML. Use plain text.")
            }
            seenGUIDs.insert(item.guid)
        }

        // Fix #6: Check GUID uniqueness.
        if seenGUIDs.count != feed.items.count {
            var duplicateTracker = Set<String>()
            for item in feed.items {
                if !duplicateTracker.insert(item.guid).inserted {
                    issues.append("Duplicate GUID: \(item.guid)")
                }
            }
        }

        return issues
    }
}
