import Foundation

// MARK: - ICalImporter

struct ICalImporter {

    struct ICalEvent {
        let uid: String
        let summary: String
        let start: Date
        let end: Date
        let description: String
        let organizer: String
    }

    /// Parse raw .ics text into ICalEvent array
    static func parse(icsContent: String, platform: String) -> [ICalEvent] {
        var events: [ICalEvent] = []
        let lines = normalizeLines(icsContent)

        var inEvent = false
        var uid = ""
        var summary = ""
        var start: Date? = nil
        var end: Date? = nil
        var desc = ""
        var organizer = ""

        for line in lines {
            if line == "BEGIN:VEVENT" {
                inEvent = true
                uid = ""; summary = ""; start = nil; end = nil; desc = ""; organizer = ""
                continue
            }
            if line == "END:VEVENT" {
                if inEvent, let s = start, let e = end {
                    events.append(ICalEvent(
                        uid: uid.isEmpty ? UUID().uuidString : uid,
                        summary: summary,
                        start: s,
                        end: e,
                        description: desc,
                        organizer: organizer
                    ))
                }
                inEvent = false
                continue
            }
            guard inEvent else { continue }

            let (key, value) = splitProperty(line)

            switch key {
            case "UID":
                uid = value
            case "SUMMARY":
                summary = unescapeText(value)
            case "DTSTART", "DTSTART;VALUE=DATE":
                start = parseDate(value)
            case "DTEND", "DTEND;VALUE=DATE":
                end = parseDate(value)
            case "DESCRIPTION":
                desc = unescapeText(value)
            case "ORGANIZER":
                organizer = value.replacingOccurrences(of: "mailto:", with: "", options: .caseInsensitive)
            default:
                // Handle parameterized keys like DTSTART;TZID=Asia/Tokyo
                if key.hasPrefix("DTSTART") {
                    start = parseDate(value)
                } else if key.hasPrefix("DTEND") {
                    end = parseDate(value)
                }
            }
        }

        return events
    }

    /// Convert ICalEvent array into Booking objects
    static func importToBookings(_ events: [ICalEvent], platform: String) -> [Booking] {
        return events.map { event in
            let guestName: String
            let lowerSummary = event.summary.lowercased()
            if lowerSummary.contains("blocked") || lowerSummary.contains("unavailable") || lowerSummary.isEmpty {
                guestName = platform == "airbnb" ? "Airbnb予約 (ブロック)" : "\(platformLabel(platform))予約"
            } else {
                guestName = event.summary
            }

            return Booking(
                id: event.uid,
                guestName: guestName,
                guestEmail: event.organizer,
                platform: platform,
                checkIn: event.start,
                checkOut: event.end,
                notes: event.description
            )
        }
    }

    // MARK: - Private Helpers

    /// Unfold continuation lines (RFC 5545 line folding: CRLF + space/tab)
    private static func normalizeLines(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // Unfold: lines starting with space or tab are continuation
        var result: [String] = []
        for line in normalized.components(separatedBy: "\n") {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), let last = result.indices.last {
                result[last] += line.dropFirst()
            } else {
                result.append(line)
            }
        }
        return result
    }

    private static func splitProperty(_ line: String) -> (String, String) {
        guard let colonIdx = line.firstIndex(of: ":") else { return (line, "") }
        let key = String(line[line.startIndex..<colonIdx]).uppercased()
        let value = String(line[line.index(after: colonIdx)...])
        return (key, value)
    }

    private static func parseDate(_ value: String) -> Date? {
        let cleanValue = value.trimmingCharacters(in: .whitespaces)
        let formatters: [DateFormatter] = {
            let utc = DateFormatter()
            utc.locale = Locale(identifier: "en_US_POSIX")

            let f1 = DateFormatter()
            f1.locale = Locale(identifier: "en_US_POSIX")
            f1.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            f1.timeZone = TimeZone(identifier: "UTC")

            let f2 = DateFormatter()
            f2.locale = Locale(identifier: "en_US_POSIX")
            f2.dateFormat = "yyyyMMdd'T'HHmmss"
            f2.timeZone = TimeZone.current

            let f3 = DateFormatter()
            f3.locale = Locale(identifier: "en_US_POSIX")
            f3.dateFormat = "yyyyMMdd"
            f3.timeZone = TimeZone(identifier: "UTC")

            return [f1, f2, f3]
        }()

        for f in formatters {
            if let d = f.date(from: cleanValue) { return d }
        }
        return nil
    }

    private static func unescapeText(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func platformLabel(_ platform: String) -> String {
        switch platform {
        case "airbnb": return "Airbnb"
        case "jalan": return "じゃらん"
        default: return "その他"
        }
    }
}
