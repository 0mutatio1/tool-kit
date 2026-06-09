import Foundation

struct JSONFormatterService {
    enum JSONFormatterError: LocalizedError {
        case invalidJSONString(details: String?)
        case emptyInput
        case encodingFailed
        case repairFailed

        var errorDescription: String? {
            switch self {
            case let .invalidJSONString(details):
                if let details, !details.isEmpty {
                    return "The pasted text is not valid JSON. \(details)"
                }
                return "The pasted text is not valid JSON."
            case .emptyInput:
                return "Paste a JSON string first."
            case .encodingFailed:
                return "The formatted JSON could not be generated."
            case .repairFailed:
                return "The JSON text could not be repaired automatically."
            }
        }
    }

    func format(_ text: String) throws -> String {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.emptyInput
        }

        let object = try parseJSONObject(from: trimmed)
        let formattedData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        )

        guard let formattedText = String(data: formattedData, encoding: .utf8) else {
            throw JSONFormatterError.encodingFailed
        }

        return formattedText
    }

    func compact(_ text: String) throws -> String {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.emptyInput
        }

        let object = try parseJSONObject(from: trimmed)
        let compactData = try JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed]
        )

        guard let compactText = String(data: compactData, encoding: .utf8) else {
            throw JSONFormatterError.encodingFailed
        }

        return compactText
    }

    func validate(_ text: String) throws {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.emptyInput
        }

        _ = try parseJSONObject(from: trimmed)
    }

    func repairAndFormat(_ text: String) throws -> String {
        let trimmed = sanitize(text)
        guard !trimmed.isEmpty else {
            throw JSONFormatterError.emptyInput
        }

        if let formatted = try? format(trimmed) {
            return formatted
        }

        let repaired = quoteUnquotedObjectKeys(
            removeTrailingCommas(
                normalizeSingleQuotedStrings(
                    removeJavaScriptComments(trimmed)
                )
            )
        )

        guard repaired != trimmed else {
            throw JSONFormatterError.repairFailed
        }

        return try format(repaired)
    }

    private func parseJSONObject(from text: String, depth: Int = 0) throws -> Any {
        guard let data = text.data(using: .utf8) else {
            throw JSONFormatterError.encodingFailed
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

            if let stringObject = object as? String, depth < 2 {
                let nested = sanitize(stringObject)
                if nested != text, looksLikeJSON(nested) {
                    return try parseJSONObject(from: nested, depth: depth + 1)
                }
            }

            return object
        } catch {
            throw makeInvalidJSONError(from: error, source: text)
        }
    }

    private func sanitize(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            if lines.count >= 2, lines.first?.hasPrefix("```") == true, lines.last == "```" {
                return lines.dropFirst().dropLast().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    private func removeJavaScriptComments(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        var isInString = false
        var stringDelimiter: Character?
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]
            let nextIndex = text.index(after: index)
            let nextCharacter = nextIndex < text.endIndex ? text[nextIndex] : nil

            if isInString {
                result.append(character)

                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == stringDelimiter {
                    isInString = false
                    stringDelimiter = nil
                }

                index = nextIndex
                continue
            }

            if character == "\"" || character == "'" {
                isInString = true
                stringDelimiter = character
                result.append(character)
                index = nextIndex
                continue
            }

            if character == "/", nextCharacter == "/" {
                index = nextIndex
                while index < text.endIndex, text[index] != "\n" {
                    index = text.index(after: index)
                }
                continue
            }

            if character == "/", nextCharacter == "*" {
                index = text.index(after: nextIndex)
                while index < text.endIndex {
                    let followingIndex = text.index(after: index)
                    if text[index] == "*", followingIndex < text.endIndex, text[followingIndex] == "/" {
                        index = text.index(after: followingIndex)
                        break
                    }
                    index = followingIndex
                }
                continue
            }

            result.append(character)
            index = nextIndex
        }

        return result
    }

    private func removeTrailingCommas(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        var isInString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if character == "\"", !isEscaped {
                isInString.toggle()
            }

            if character == "\\", isInString {
                isEscaped.toggle()
            } else {
                isEscaped = false
            }

            if character == ",", !isInString {
                var lookahead = text.index(after: index)
                while lookahead < text.endIndex, text[lookahead].isWhitespace {
                    lookahead = text.index(after: lookahead)
                }

                if lookahead < text.endIndex, (text[lookahead] == "}" || text[lookahead] == "]") {
                    index = text.index(after: index)
                    continue
                }
            }

            result.append(character)
            index = text.index(after: index)
        }

        return result
    }

    private func normalizeSingleQuotedStrings(_ text: String) -> String {
        var result = ""
        var index = text.startIndex
        var isInDoubleQuotedString = false
        var isInSingleQuotedString = false
        var isEscaped = false

        while index < text.endIndex {
            let character = text[index]

            if isInSingleQuotedString {
                if isEscaped {
                    result.append(character)
                    isEscaped = false
                } else if character == "\\" {
                    result.append(character)
                    isEscaped = true
                } else if character == "'" {
                    result.append("\"")
                    isInSingleQuotedString = false
                } else if character == "\"" {
                    result.append("\\\"")
                } else {
                    result.append(character)
                }

                index = text.index(after: index)
                continue
            }

            if character == "\"", !isEscaped {
                isInDoubleQuotedString.toggle()
            }

            if character == "'", !isInDoubleQuotedString {
                result.append("\"")
                isInSingleQuotedString = true
            } else {
                result.append(character)
            }

            if character == "\\", isInDoubleQuotedString {
                isEscaped.toggle()
            } else {
                isEscaped = false
            }

            index = text.index(after: index)
        }

        return result
    }

    private func quoteUnquotedObjectKeys(_ text: String) -> String {
        let pattern = #"(?m)([\{,]\s*)([A-Za-z_$][A-Za-z0-9_$-]*)(\s*:)"#

        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(
            in: text,
            range: range,
            withTemplate: "$1\"$2\"$3"
        )
    }

    private func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else {
            return false
        }

        return (first == "{" && last == "}") ||
            (first == "[" && last == "]") ||
            (first == "\"" && last == "\"")
    }

    private func makeInvalidJSONError(from error: Error, source: String) -> JSONFormatterError {
        let nsError = error as NSError
        if let index = nsError.userInfo["NSJSONSerializationErrorIndex"] as? Int,
           index >= 0,
           let location = lineAndColumn(in: source, at: index) {
            return .invalidJSONString(details: "Line \(location.line), column \(location.column).")
        }

        if !nsError.localizedDescription.isEmpty {
            return .invalidJSONString(details: nsError.localizedDescription)
        }

        return .invalidJSONString(details: nil)
    }

    private func lineAndColumn(in text: String, at index: Int) -> (line: Int, column: Int)? {
        guard index <= text.utf16.count else {
            return nil
        }

        let prefix = (text as NSString).substring(to: index)
        let lines = prefix.components(separatedBy: .newlines)
        let line = max(lines.count, 1)
        let column = (lines.last?.count ?? 0) + 1
        return (line, column)
    }
}
