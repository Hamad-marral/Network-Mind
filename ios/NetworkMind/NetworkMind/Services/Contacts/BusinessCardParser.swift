import Foundation

/// Fields extracted from OCR'd business-card text.
struct ParsedBusinessCard: Equatable, Sendable {
    var name: String = ""
    var title: String = ""
    var company: String = ""
    var emails: [String] = []
    var phones: [String] = []
    var websites: [String] = []
}

/// Heuristic parser for business-card text lines (top-to-bottom order).
///
/// Strategy: pull out machine-recognizable data first (emails, phones, URLs), then classify
/// the remaining short lines by keywords: job-title words → title, legal/industry suffixes →
/// company, a 2–4 word capitalized line → name. Falls back to the email domain for company.
enum BusinessCardParser {
    private static let titleKeywords: [String] = [
        "ceo", "cto", "cfo", "coo", "cmo", "cio", "cpo", "chief", "founder", "co-founder", "cofounder",
        "president", "vice president", "vp", "director", "head", "manager", "lead", "engineer",
        "developer", "designer", "consultant", "partner", "officer", "executive", "analyst",
        "specialist", "associate", "advisor", "adviser", "owner", "principal", "architect",
        "scientist", "researcher", "professor", "investor", "chairman", "chairperson", "md",
        "managing", "sales", "marketing", "product", "operations", "intern", "coordinator",
        "representative", "strategist", "recruiter", "attorney", "lawyer", "doctor", "secretary",
    ]

    private static let companyKeywords: [String] = [
        "inc", "inc.", "llc", "ltd", "ltd.", "limited", "corp", "corp.", "corporation", "co.",
        "company", "group", "gmbh", "pvt", "pvt.", "plc", "llp", "s.a.", "ag", "technologies",
        "technology", "tech", "solutions", "systems", "labs", "holdings", "ventures", "capital",
        "partners", "studio", "studios", "agency", "consulting", "bank", "industries", "enterprises",
        "international", "global", "networks", "software", "digital", "media", "foundation",
        "university", "institute", "associates",
    ]

    private static let legalSuffixes: [String] = [
        "inc", "inc.", "llc", "ltd", "ltd.", "limited", "corp", "corp.", "corporation",
        "gmbh", "pvt", "pvt.", "plc", "llp",
    ]

    private static let genericEmailDomains: Set<String> = [
        "gmail", "yahoo", "hotmail", "outlook", "icloud", "me", "live", "aol", "proton", "protonmail", "msn",
    ]

    private static let emailRegex = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#, options: [.caseInsensitive]
    )
    private static let urlRegex = try! NSRegularExpression(
        pattern: #"\b((https?://)?(www\.)?[a-z0-9\-]+(\.[a-z0-9\-]+)*\.[a-z]{2,}(/\S*)?)\b"#, options: [.caseInsensitive]
    )
    private static let phoneDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)

    static func parse(lines rawLines: [String]) -> ParsedBusinessCard {
        var card = ParsedBusinessCard()
        let lines = rawLines
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var remaining: [String] = []
        for line in lines {
            let emails = matches(of: emailRegex, in: line)
            let phones = phoneNumbers(in: line)
            card.emails.append(contentsOf: emails.map { $0.lowercased() })
            card.phones.append(contentsOf: phones)

            if !emails.isEmpty || !phones.isEmpty { continue }
            let urls = matches(of: urlRegex, in: line).filter(looksLikeWebsite)
            if !urls.isEmpty {
                card.websites.append(contentsOf: urls.map { $0.lowercased() })
                continue
            }
            if isAddressLike(line) { continue }
            remaining.append(line)
        }
        card.emails = unique(card.emails)
        card.phones = unique(card.phones)
        card.websites = unique(card.websites)

        // Titles and companies first (keyword-driven), then name from what is left.
        var unclassified: [String] = []
        for line in remaining {
            if card.company.isEmpty, containsKeyword(line, legalSuffixes) {
                card.company = line  // "Product Labs Inc" is a company even though "product" is a title word
            } else if card.title.isEmpty, containsKeyword(line, titleKeywords) {
                card.title = line
            } else if card.company.isEmpty, containsKeyword(line, companyKeywords) {
                card.company = line
            } else {
                unclassified.append(line)
            }
        }

        if let nameIndex = unclassified.firstIndex(where: looksLikeName) {
            card.name = unclassified.remove(at: nameIndex)
        }
        if card.company.isEmpty, let domain = companyFromEmailDomain(card.emails.first ?? card.websites.first) {
            // Prefer an all-caps/brand line that matches the domain, otherwise the domain itself.
            if let brandIndex = unclassified.firstIndex(where: { $0.lowercased().replacingOccurrences(of: " ", with: "").contains(domain.lowercased()) }) {
                card.company = unclassified.remove(at: brandIndex)
            } else {
                card.company = domain
            }
        }
        if card.name.isEmpty, let first = unclassified.first(where: { !$0.contains(where: \.isNumber) }) {
            card.name = first
        }
        return card
    }

    // MARK: Helpers

    private static func matches(of regex: NSRegularExpression, in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func phoneNumbers(in text: String) -> [String] {
        guard let detector = phoneDetector else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap { result in
            guard let number = result.phoneNumber else { return nil }
            // Require at least 7 digits to avoid matching years, suite numbers, etc.
            return number.filter(\.isNumber).count >= 7 ? number : nil
        }
    }

    private static func looksLikeWebsite(_ candidate: String) -> Bool {
        let lower = candidate.lowercased()
        return lower.hasPrefix("www.") || lower.hasPrefix("http") ||
            [".com", ".io", ".co", ".net", ".org", ".pk", ".ai", ".dev", ".app"].contains { lower.contains($0) }
    }

    private static func isAddressLike(_ line: String) -> Bool {
        let lower = line.lowercased()
        let digitCount = line.filter(\.isNumber).count
        let addressWords = ["street", "st.", "road", "rd.", "avenue", "ave", "suite", "floor", "block",
                            "sector", "plaza", "building", "p.o. box", "po box", "blvd", "lane", "phase"]
        return (digitCount >= 2 && addressWords.contains { lower.contains($0) }) || digitCount >= 5
    }

    private static func words(_ line: String) -> [String] {
        line.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-")).inverted)
            .filter { !$0.isEmpty }
    }

    private static func containsKeyword(_ line: String, _ keywords: [String]) -> Bool {
        let tokens = words(line)
        let lower = " " + tokens.joined(separator: " ") + " "
        return keywords.contains { keyword in
            keyword.contains(" ") ? lower.contains(" \(keyword) ") : tokens.contains(keyword)
        }
    }

    private static func looksLikeName(_ line: String) -> Bool {
        guard !line.contains(where: \.isNumber) else { return false }
        let parts = line.split(separator: " ")
        guard (2...4).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            guard let first = part.first else { return false }
            return first.isUppercase && part.allSatisfy { $0.isLetter || $0 == "." || $0 == "-" || $0 == "'" }
        }
    }

    private static func companyFromEmailDomain(_ value: String?) -> String? {
        guard let value else { return nil }
        let host: Substring
        if let at = value.lastIndex(of: "@") {
            host = value[value.index(after: at)...]
        } else {
            host = Substring(value.replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .replacingOccurrences(of: "www.", with: "")
                .split(separator: "/").first ?? "")
        }
        guard let label = host.split(separator: ".").first.map(String.init),
              !label.isEmpty, !genericEmailDomains.contains(label.lowercased()) else { return nil }
        return label.prefix(1).uppercased() + label.dropFirst()
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
