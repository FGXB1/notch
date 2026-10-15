import Foundation

/// Video-call services recognised in event links and notes, checked in this order.
public enum MeetingService: String, CaseIterable, Sendable {
    case zoom
    case meet
    case teams
    case webex
    case facetime

    public var name: String {
        switch self {
        case .zoom: "Zoom"
        case .meet: "Google Meet"
        case .teams: "Microsoft Teams"
        case .webex: "Webex"
        case .facetime: "FaceTime"
        }
    }

    /// Apps that can open `MeetingLink.nativeURL` directly, skipping the browser's "Open app?" step.
    public var appBundleIdentifiers: [String] {
        switch self {
        case .zoom: ["us.zoom.xos"]
        case .teams: ["com.microsoft.teams2", "com.microsoft.teams"]
        case .meet, .webex, .facetime: []
        }
    }

    /// Recognises join links only, not the help pages and dial-in links that invitations also contain.
    static func classify(_ url: URL) -> MeetingService? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path()
        func within(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if within("zoom.us") || within("zoomgov.com") {
            return ["/j/", "/my/", "/w/", "/s/", "/wc/"].contains { path.hasPrefix($0) } ? .zoom : nil
        }
        if host == "meet.google.com" {
            return path.wholeMatch(of: #/\/(lookup\/)?[a-z0-9_-]{3,}\/?/#.ignoresCase()) != nil ? .meet : nil
        }
        if within("teams.microsoft.com") || within("teams.live.com") {
            return path.hasPrefix("/l/meetup-join") || path.hasPrefix("/meet/") ? .teams : nil
        }
        if within("webex.com") {
            return host != "help.webex.com" && path.count > 1 ? .webex : nil
        }
        if host == "facetime.apple.com" {
            return path.hasPrefix("/join") ? .facetime : nil
        }
        return nil
    }
}

public struct MeetingLink: Equatable, Hashable, Sendable {
    public var service: MeetingService
    public var url: URL

    public init(service: MeetingService, url: URL) {
        self.service = service
        self.url = url
    }

    /// First join link in `texts`, searched in order (pass the URL field, then location, then notes).
    public static func detect(in texts: [String?]) -> MeetingLink? {
        for text in texts.compactMap(\.self) {
            for url in urls(in: text) {
                let target = unwrapped(url)
                if let service = MeetingService.classify(target) {
                    return MeetingLink(service: service, url: target)
                }
            }
        }
        return nil
    }

    /// The service's own URL scheme, when it has one that joins directly.
    public var nativeURL: URL? {
        switch service {
        case .zoom:
            // https://host.zoom.us/j/123?pwd=x → zoommtg://host.zoom.us/join?action=join&confno=123&pwd=x
            let parts = url.pathComponents
            guard parts.count >= 3, ["j", "w"].contains(parts[1]), let host = url.host() else { return nil }
            var components = URLComponents()
            components.scheme = "zoommtg"
            components.host = host
            components.path = "/join"
            var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[2])]
            if let password = queryValue("pwd", in: url) {
                items.append(URLQueryItem(name: "pwd", value: password))
            }
            components.queryItems = items
            return components.url
        case .teams:
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
            let query = components.percentEncodedQuery.map { "?" + $0 } ?? ""
            return URL(string: "msteams:" + components.percentEncodedPath + query)
        case .meet, .webex, .facetime:
            return nil
        }
    }

    // MARK: Parsing

    static func urls(in text: String) -> [URL] {
        // Calendar invites often carry HTML descriptions.
        let text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text.matches(of: #/https?:\/\/[^\s<>"'()\[\]{}]+/#.ignoresCase()).compactMap { match in
            var string = String(match.output)
            while let last = string.last, ".,;:!?".contains(last) {
                string.removeLast()
            }
            return URL(string: string)
        }
    }

    /// Outlook Safe Links and Google redirects wrap the real link in a query parameter.
    static func unwrapped(_ url: URL) -> URL {
        guard let host = url.host()?.lowercased() else { return url }
        let wrapped: String? = if host.hasSuffix("safelinks.protection.outlook.com") {
            queryValue("url", in: url)
        } else if host.hasSuffix("google.com"), url.path() == "/url" {
            queryValue("q", in: url)
        } else {
            nil
        }
        return wrapped.flatMap(URL.init(string:)) ?? url
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        Self.queryValue(name, in: url)
    }
}
