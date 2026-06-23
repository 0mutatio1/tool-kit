import Foundation

struct TextDiffService {
    struct Result: Sendable {
        let rows: [TextDiffRow]
        let summary: TextDiffSummary
    }

    private enum Operation {
        case equal(String, Int, Int)
        case delete(String, Int)
        case insert(String, Int)
    }

    func diff(left: String, right: String) -> Result {
        let leftLines = splitLines(left)
        let rightLines = splitLines(right)
        let operations = operations(leftLines: leftLines, rightLines: rightLines)
        let rows = rows(from: operations)
        return Result(rows: rows, summary: summary(for: rows))
    }

    private func splitLines(_ text: String) -> [String] {
        guard !text.isEmpty else {
            return []
        }
        return text.components(separatedBy: .newlines)
    }

    private func operations(leftLines: [String], rightLines: [String]) -> [Operation] {
        let leftCount = leftLines.count
        let rightCount = rightLines.count
        var table = Array(
            repeating: Array(repeating: 0, count: rightCount + 1),
            count: leftCount + 1
        )

        if leftCount > 0 && rightCount > 0 {
            for leftIndex in stride(from: leftCount - 1, through: 0, by: -1) {
                for rightIndex in stride(from: rightCount - 1, through: 0, by: -1) {
                    if leftLines[leftIndex] == rightLines[rightIndex] {
                        table[leftIndex][rightIndex] = table[leftIndex + 1][rightIndex + 1] + 1
                    } else {
                        table[leftIndex][rightIndex] = max(
                            table[leftIndex + 1][rightIndex],
                            table[leftIndex][rightIndex + 1]
                        )
                    }
                }
            }
        }

        var result: [Operation] = []
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < leftCount && rightIndex < rightCount {
            if leftLines[leftIndex] == rightLines[rightIndex] {
                result.append(.equal(leftLines[leftIndex], leftIndex + 1, rightIndex + 1))
                leftIndex += 1
                rightIndex += 1
            } else if table[leftIndex + 1][rightIndex] >= table[leftIndex][rightIndex + 1] {
                result.append(.delete(leftLines[leftIndex], leftIndex + 1))
                leftIndex += 1
            } else {
                result.append(.insert(rightLines[rightIndex], rightIndex + 1))
                rightIndex += 1
            }
        }

        while leftIndex < leftCount {
            result.append(.delete(leftLines[leftIndex], leftIndex + 1))
            leftIndex += 1
        }
        while rightIndex < rightCount {
            result.append(.insert(rightLines[rightIndex], rightIndex + 1))
            rightIndex += 1
        }

        return result
    }

    private func rows(from operations: [Operation]) -> [TextDiffRow] {
        var rows: [TextDiffRow] = []
        var index = 0

        while index < operations.count {
            switch operations[index] {
            case .equal(let text, let leftLine, let rightLine):
                rows.append(TextDiffRow(
                    kind: .equal,
                    leftLineNumber: leftLine,
                    rightLineNumber: rightLine,
                    left: parts(for: text, highlightAll: false),
                    right: parts(for: text, highlightAll: false)
                ))
                index += 1

            case .delete:
                var deleted: [(String, Int)] = []
                while index < operations.count, case .delete(let text, let line) = operations[index] {
                    deleted.append((text, line))
                    index += 1
                }

                var inserted: [(String, Int)] = []
                while index < operations.count, case .insert(let text, let line) = operations[index] {
                    inserted.append((text, line))
                    index += 1
                }

                rows.append(contentsOf: mergedRows(deleted: deleted, inserted: inserted))

            case .insert:
                var inserted: [(String, Int)] = []
                while index < operations.count, case .insert(let text, let line) = operations[index] {
                    inserted.append((text, line))
                    index += 1
                }
                rows.append(contentsOf: mergedRows(deleted: [], inserted: inserted))
            }
        }

        return rows
    }

    private func mergedRows(
        deleted: [(text: String, line: Int)],
        inserted: [(text: String, line: Int)]
    ) -> [TextDiffRow] {
        let pairCount = min(deleted.count, inserted.count)
        var rows: [TextDiffRow] = []

        for offset in 0..<pairCount {
            let left = deleted[offset]
            let right = inserted[offset]
            let highlighted = changedParts(left: left.text, right: right.text)
            rows.append(TextDiffRow(
                kind: .changed,
                leftLineNumber: left.line,
                rightLineNumber: right.line,
                left: highlighted.left,
                right: highlighted.right
            ))
        }

        if deleted.count > pairCount {
            rows.append(contentsOf: deleted[pairCount...].map { item in
                TextDiffRow(
                    kind: .deleted,
                    leftLineNumber: item.line,
                    rightLineNumber: nil,
                    left: parts(for: item.text, highlightAll: true),
                    right: nil
                )
            })
        }

        if inserted.count > pairCount {
            rows.append(contentsOf: inserted[pairCount...].map { item in
                TextDiffRow(
                    kind: .inserted,
                    leftLineNumber: nil,
                    rightLineNumber: item.line,
                    left: nil,
                    right: parts(for: item.text, highlightAll: true)
                )
            })
        }

        return rows
    }

    private func changedParts(
        left: String,
        right: String
    ) -> (left: TextDiffRow.Parts, right: TextDiffRow.Parts) {
        let leftCharacters = Array(left)
        let rightCharacters = Array(right)

        var prefixCount = 0
        while prefixCount < leftCharacters.count,
              prefixCount < rightCharacters.count,
              leftCharacters[prefixCount] == rightCharacters[prefixCount] {
            prefixCount += 1
        }

        var suffixCount = 0
        while suffixCount + prefixCount < leftCharacters.count,
              suffixCount + prefixCount < rightCharacters.count,
              leftCharacters[leftCharacters.count - suffixCount - 1] == rightCharacters[rightCharacters.count - suffixCount - 1] {
            suffixCount += 1
        }

        return (
            parts(for: left, prefixCount: prefixCount, suffixCount: suffixCount),
            parts(for: right, prefixCount: prefixCount, suffixCount: suffixCount)
        )
    }

    private func parts(for text: String, highlightAll: Bool) -> TextDiffRow.Parts {
        guard highlightAll else {
            return TextDiffRow.Parts(prefix: text, highlighted: "", suffix: "")
        }
        return TextDiffRow.Parts(prefix: "", highlighted: text, suffix: "")
    }

    private func parts(for text: String, prefixCount: Int, suffixCount: Int) -> TextDiffRow.Parts {
        let characters = Array(text)
        let prefix = String(characters.prefix(prefixCount))
        let highlightedEnd = max(prefixCount, characters.count - suffixCount)
        let highlighted = String(characters[prefixCount..<highlightedEnd])
        let suffix = String(characters.suffix(suffixCount))
        return TextDiffRow.Parts(prefix: prefix, highlighted: highlighted, suffix: suffix)
    }

    private func summary(for rows: [TextDiffRow]) -> TextDiffSummary {
        TextDiffSummary(
            added: rows.filter { $0.kind == .inserted }.count,
            deleted: rows.filter { $0.kind == .deleted }.count,
            changed: rows.filter { $0.kind == .changed }.count,
            unchanged: rows.filter { $0.kind == .equal }.count
        )
    }
}
