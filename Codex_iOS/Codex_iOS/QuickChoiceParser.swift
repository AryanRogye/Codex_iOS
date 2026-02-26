import Foundation

struct QuickChoiceOption: Equatable {
    let label: String
    let insertionText: String
}

enum QuickChoiceParser {
    private static let maxOptionCount = 12
    private static let maxCandidateLength = 140

    static func options(from content: String) -> [QuickChoiceOption] {
        let lines = content.components(separatedBy: .newlines)

        let listCandidates = uniqueOptions(
            lines.compactMap { line in
                guard let raw = parseListCandidate(from: line) else {
                    return nil
                }
                return sanitizeCandidate(raw)
            }
        )

        if listCandidates.isEmpty == false {
            let containsDirectory = listCandidates.contains(where: isDirectoryLike)
            let limited = Array(listCandidates.prefix(maxOptionCount))

            if containsDirectory {
                return limited.map(makeOption(from:))
            }
            if (2...4).contains(limited.count) {
                return limited.map(makeOption(from:))
            }
        }

        let pathCandidates = uniqueOptions(
            lines.compactMap { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard isDirectoryLike(trimmed) else {
                    return nil
                }
                return sanitizeCandidate(trimmed)
            }
        )

        if pathCandidates.isEmpty == false {
            return Array(pathCandidates.prefix(maxOptionCount)).map(makeOption(from:))
        }

        let lower = content.lowercased()
        if lower.contains("yes/no") || lower.contains("yes or no") || lower.contains("respond with yes or no") {
            return [
                QuickChoiceOption(label: "Yes", insertionText: "Yes"),
                QuickChoiceOption(label: "No", insertionText: "No"),
            ]
        }
        if lower.contains("approve or reject") || lower.contains("approve/reject") {
            return [
                QuickChoiceOption(label: "Approve", insertionText: "Approve"),
                QuickChoiceOption(label: "Reject", insertionText: "Reject"),
            ]
        }

        return []
    }

    private static func makeOption(from label: String) -> QuickChoiceOption {
        QuickChoiceOption(label: label, insertionText: insertionText(for: label))
    }

    private static func insertionText(for label: String) -> String {
        if label.lowercased().hasPrefix("cd ") {
            return label
        }
        if isDirectoryLike(label) {
            return "cd \(label)"
        }
        return label
    }

    private static func parseListCandidate(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        if let marker = trimmed.first, marker == "-" || marker == "*" || marker == "+" {
            let afterMarker = trimmed.index(after: trimmed.startIndex)
            guard afterMarker < trimmed.endIndex, trimmed[afterMarker] == " " else {
                return nil
            }

            let contentStart = trimmed.index(after: afterMarker)
            return String(trimmed[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return parseOrderedCandidate(from: trimmed)
    }

    private static func parseOrderedCandidate(from line: String) -> String? {
        let characters = Array(line)
        var digitCount = 0

        while digitCount < characters.count, characters[digitCount].isNumber {
            digitCount += 1
        }

        guard digitCount > 0 else {
            return nil
        }
        guard digitCount + 1 < characters.count else {
            return nil
        }
        guard (characters[digitCount] == "." || characters[digitCount] == ")"),
              characters[digitCount + 1] == " " else {
            return nil
        }

        let contentStart = line.index(line.startIndex, offsetBy: digitCount + 2)
        return String(line[contentStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sanitizeCandidate(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else {
            return nil
        }

        if candidate.hasPrefix("["),
           let closeBracket = candidate.firstIndex(of: "]"),
           closeBracket < candidate.index(before: candidate.endIndex) {
            let after = candidate.index(after: closeBracket)
            candidate = String(candidate[after...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        candidate = candidate
            .replacingOccurrences(of: #"[`*]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if candidate.lowercased().hasSuffix("(dir)") || candidate.lowercased().hasSuffix("(directory)") {
            if let openParen = candidate.lastIndex(of: "(") {
                candidate = String(candidate[..<openParen]).trimmingCharacters(in: .whitespacesAndNewlines)
                if candidate.hasSuffix("/") == false, candidate.isEmpty == false {
                    candidate.append("/")
                }
            }
        }

        if (candidate.hasPrefix("\"") && candidate.hasSuffix("\""))
            || (candidate.hasPrefix("'") && candidate.hasSuffix("'")) {
            candidate = String(candidate.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard candidate.isEmpty == false else {
            return nil
        }
        guard candidate.count <= maxCandidateLength else {
            return nil
        }

        return candidate
    }

    private static func isDirectoryLike(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard candidate.isEmpty == false else {
            return false
        }

        if candidate == "." || candidate == ".." {
            return true
        }
        if candidate.hasSuffix("/") {
            return true
        }
        if candidate.hasPrefix("./") || candidate.hasPrefix("../") || candidate.hasPrefix("/") || candidate.hasPrefix("~/") {
            return true
        }

        return false
    }

    private static func uniqueOptions(_ input: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []

        for item in input {
            let normalized = item.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            output.append(item)
        }

        return output
    }
}
