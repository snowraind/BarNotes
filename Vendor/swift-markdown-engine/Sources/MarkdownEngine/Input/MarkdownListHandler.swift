//
//  MarkdownListHandler.swift
//  MarkdownEngine
//
//  Created by Luca Chen on 18.02.26.
//

// Makes list editing feel natural by continuing items, handling indentation,
// and applying spacing/alignment that keeps lists easy to read.
import AppKit

struct MarkdownLists {
    static func performEdit(_ textView: NSTextView, replace range: NSRange, with string: String) {
        let ns = textView.string as NSString
        let loc = min(range.location, ns.length)
        let maxLen = ns.length - loc
        let len = min(range.length, max(0, maxLen))
        let safeRange = NSRange(location: loc, length: len)

        if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator { coord.isProgrammaticEdit = true }
        defer {
            if let coord = textView.delegate as? NativeTextViewWrapper.Coordinator { coord.isProgrammaticEdit = false }
        }

        guard textView.shouldChangeText(in: safeRange, replacementString: string) else { return }
        textView.textStorage?.replaceCharacters(in: safeRange, with: string)
        textView.didChangeText()
    }

    static let listRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*((?:(\d+)\.|[-•])(?:[ \t]+\[[ xX]\])?[ \t]+)"#
    )
    static let dashNoSpaceRegex = try! NSRegularExpression(pattern: #"^\s*-(?!\s)"#)
    static let numberRegex = try! NSRegularExpression(pattern: #"^\s*(\d+)\.$"#)
    static let leadingWhitespaceRegex = try! NSRegularExpression(pattern: #"^\s*"#)
    static let listLineRegex = try! NSRegularExpression(
        pattern: #"^[ \t]*(?:[-•]|\d+\.)(?:[ \t]+\[[ xX]\])?[ \t]"#
    )

    static func indentLevel(from leadingWhitespace: String) -> Int {
        let tabCount = leadingWhitespace.filter { $0 == "\t" }.count
        let spaceCount = leadingWhitespace.filter { $0 == " " }.count
        return tabCount + (spaceCount / 2)
    }

    static func outdentListItems(in textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let selectedRange = textView.selectedRange()
        let safeLocation = min(selectedRange.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: selectedRange.length))
        let original = nsText.substring(with: lineRange) as NSString
        var editedLines: [String] = []
        var removedBeforeSelection = 0
        var removedTotal = 0
        var localOffset = 0
        var changed = false

        original.enumerateSubstrings(
            in: NSRange(location: 0, length: original.length),
            options: [.byLines, .substringNotRequired]
        ) { _, lineSubstringRange, enclosingRange, _ in
            let line = original.substring(with: enclosingRange)
            let bodyLength = line.hasSuffix("\n") ? max(0, line.count - 1) : line.count
            let body = String(line.prefix(bodyLength))
            let newline = String(line.dropFirst(bodyLength))
            let matchRange = NSRange(location: 0, length: (body as NSString).length)

            var removed = 0
            if MarkdownLists.listLineRegex.firstMatch(in: body, range: matchRange) != nil {
                if body.hasPrefix("\t") {
                    removed = 1
                } else if body.hasPrefix("  ") {
                    removed = 2
                } else if body.hasPrefix(" ") {
                    removed = 1
                }
            }

            if removed > 0 {
                changed = true
                editedLines.append(String(body.dropFirst(removed)) + newline)
                let lineStartInDocument = lineRange.location + localOffset
                if lineStartInDocument < selectedRange.location {
                    removedBeforeSelection += min(removed, selectedRange.location - lineStartInDocument)
                }
                removedTotal += removed
            } else {
                editedLines.append(line)
            }

            localOffset += enclosingRange.length
        }

        guard changed else { return false }
        let replacement = editedLines.joined()
        MarkdownLists.performEdit(textView, replace: lineRange, with: replacement)
        let nextLocation = max(lineRange.location, selectedRange.location - removedBeforeSelection)
        let nextLength = max(0, selectedRange.length - max(0, removedTotal - removedBeforeSelection))
        textView.setSelectedRange(NSRange(location: nextLocation, length: nextLength))
        return true
    }

    static func indentSelectedLines(in textView: NSTextView) -> Bool {
        let nsText = textView.string as NSString
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0 else { return false }

        let safeLocation = min(selectedRange.location, nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: selectedRange.length))
        let original = nsText.substring(with: lineRange) as NSString
        var editedLines: [String] = []

        original.enumerateSubstrings(
            in: NSRange(location: 0, length: original.length),
            options: [.byLines, .substringNotRequired]
        ) { _, _, enclosingRange, _ in
            let line = original.substring(with: enclosingRange)
            editedLines.append("\t" + line)
        }

        guard !editedLines.isEmpty else { return false }
        let replacement = editedLines.joined()
        MarkdownLists.performEdit(textView, replace: lineRange, with: replacement)
        textView.setSelectedRange(NSRange(location: lineRange.location, length: (replacement as NSString).length))
        return true
    }

    // MARK: - Paragraph Attributes for List Styling

    static func paragraphAttributes(
        for text: String,
        baseFont: NSFont,
        nsText: NSString,
        fullRange: NSRange,
        listsEnabled: Bool,
        defaultLineHeight: CGFloat,
        defaultParagraphSpacing: CGFloat,
        configuration: MarkdownEditorConfiguration = .default
    ) -> [(range: NSRange, attributes: [NSAttributedString.Key: Any])] {
        var attributesList: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
        guard listsEnabled else { return attributesList }

        let indentPerLevel = configuration.lists.indentPerLevel
        let extraLineHeight = configuration.lists.extraLineHeight
        let spaceWidth = (" " as NSString).size(withAttributes: [.font: baseFont]).width

        func applyListMatches(_ matches: [NSTextCheckingResult]) {
            for match in matches {
                let ps = NSMutableParagraphStyle()
                ps.minimumLineHeight = defaultLineHeight + extraLineHeight
                ps.maximumLineHeight = defaultLineHeight + extraLineHeight
                ps.lineSpacing = 0
                ps.paragraphSpacing = defaultParagraphSpacing
                ps.paragraphSpacingBefore = 0
                let wsRange = match.range(at: 1)
                let markerRange = match.range(at: 2)
                let ws = nsText.substring(with: wsRange)
                let tabCount = ws.filter { $0 == "\t" }.count
                let spaceCount = ws.filter { $0 == " " }.count
                let depthIndent = CGFloat(tabCount) * indentPerLevel + CGFloat(spaceCount) * spaceWidth

                let markerString = nsText.substring(with: markerRange) as NSString
                let markerWidth = markerString.size(withAttributes: [.font: baseFont]).width
                let hasCheckbox = markerString.range(of: "[").location != NSNotFound
                let isChecked = markerString.range(of: "[x]", options: [.caseInsensitive]).location != NSNotFound
                let extraSpacing = (hasCheckbox && !isChecked)
                    ? HeadingHelpers.checkboxExtraSpacing(font: baseFont, configuration: configuration.checkbox)
                    : 0

                ps.tabStops = []
                ps.defaultTabInterval = indentPerLevel
                ps.firstLineHeadIndent = 0
                ps.headIndent = depthIndent + markerWidth + extraSpacing

                attributesList.append((match.range(at: 0), [.paragraphStyle: ps]))
            }
        }

        // Ordered lists
        let orderedListPattern = #"^([ \t]*)(\d+\.(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#
        if let orderedListRegex = try? NSRegularExpression(pattern: orderedListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(orderedListRegex.matches(in: text, options: [], range: fullRange))
        }

        // Bullet lists
        let bulletListPattern = #"^([ \t]*)([-•](?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$"#
        if let bulletListRegex = try? NSRegularExpression(pattern: bulletListPattern, options: [.anchorsMatchLines]) {
            applyListMatches(bulletListRegex.matches(in: text, options: [], range: fullRange))
        }
        return attributesList
    }

    // MARK: - Input Handling

    static func handleInsertion(textView: NSTextView, affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard let replacementString = replacementString else { return true }

        // Fast path: skip the expensive isInsideCodeBlock scan for ordinary typing.
        if replacementString.count == 1,
           let ch = replacementString.first,
           ch != ">" && ch != "[" && ch != "(" && ch != "{" &&
           ch != "\t" && ch != " " && ch != "\n" {
            return true
        }

        let activeConfig = (textView as? NativeTextView)?.configuration ?? .default
        let listsEnabled = activeConfig.lists.helpersEnabled
        let autoClosePairsEnabled = activeConfig.lists.autoClosePairsEnabled

        func insertAutoPair(open openChar: String, close closeChar: String) -> Bool {
            let insertionLocation = affectedCharRange.location
            MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "\(openChar)\(closeChar)")
            textView.setSelectedRange(NSRange(location: insertionLocation + openChar.count, length: 0))
            return false
        }

        let isInCodeBlock = textView.string.contains("`")
            ? MarkdownDetection.isInsideCodeBlock(location: affectedCharRange.location, in: textView.string)
            : false
        if replacementString == ">" && affectedCharRange.length == 0 && !isInCodeBlock {
            let insertionLocation = affectedCharRange.location
            guard insertionLocation > 0 else { return true }
            let nsText = textView.string as NSString
            let previousCharRange = NSRange(location: insertionLocation - 1, length: 1)
            let previousChar = nsText.substring(with: previousCharRange)
            if previousChar == "-" {
                MarkdownLists.performEdit(textView, replace: previousCharRange, with: "→")
                textView.setSelectedRange(NSRange(location: insertionLocation, length: 0))
                return false
            }
        }

        // Autocomplete Obsidian-style node brackets and single square brackets
        if replacementString == "[" {
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            if insertionLocation > 0 {
                let prevChar = nsText.substring(with: NSRange(location: insertionLocation - 1, length: 1))
                if prevChar == "[" {
                    let hasAutoCloseBracket = insertionLocation < nsText.length
                        && nsText.substring(with: NSRange(location: insertionLocation, length: 1)) == "]"
                    if hasAutoCloseBracket {
                        // Collapse auto-paired "[]" into "[[]]" without changing surrounding text.
                        MarkdownLists.performEdit(
                            textView,
                            replace: NSRange(location: insertionLocation - 1, length: 2),
                            with: "[[]]"
                        )
                    } else {
                        // If the char to the right is not "]" (e.g. newline), do not delete it.
                        MarkdownLists.performEdit(textView, replace: affectedCharRange, with: "[]]")
                    }
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }
            guard autoClosePairsEnabled else { return true }
            return insertAutoPair(open: "[", close: "]")
        }

        // Autocomplete parentheses / braces
        if replacementString == "(" || replacementString == "{" {
            guard autoClosePairsEnabled else { return true }
            let closeChar = (replacementString == "(") ? ")" : "}"
            return insertAutoPair(open: replacementString, close: closeChar)
        }

        // TAB: indent list items (skip in code blocks)
        if replacementString == "\t" && !isInCodeBlock {
            guard listsEnabled else { return true }
            if MarkdownLists.indentSelectedLines(in: textView) {
                return false
            }
            let nsText = textView.string as NSString
            let insertionLocation = affectedCharRange.location
            let safeLocTAB = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocTAB, length: 0))
            let currentLine = nsText.substring(with: currentLineRange)
            if MarkdownLists.listRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel {
                        return false
                    }
                }
                MarkdownLists.performEdit(textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            if MarkdownLists.dashNoSpaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) != nil {
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: currentLine, range: NSRange(location: 0, length: currentLine.utf16.count)) {
                    let ws = (currentLine as NSString).substring(with: wsMatch.range)
                    let level = MarkdownLists.indentLevel(from: ws)
                    if level >= MarkdownEditorConfiguration.default.lists.maximumNestingLevel { return false }
                }
                MarkdownLists.performEdit(textView, replace: NSRange(location: currentLineRange.location, length: 0), with: "\t")
                textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                return false
            }
            return true
        }

        // SPACE: keep Markdown markers as typed; styling renders lists without changing source text.
        if replacementString == " " && !isInCodeBlock {
            return true
        }

        // ENTER: HR expansion and list continuation/outdent
        if replacementString == "\n" {
            let nsText = textView.string as NSString
            let safeLocENTER = min(affectedCharRange.location, nsText.length)
            let currentLineRange = nsText.lineRange(for: NSRange(location: safeLocENTER, length: 0))
            let currentLine = nsText.substring(with: currentLineRange).trimmingCharacters(in: .whitespacesAndNewlines)

            if currentLine.range(of: "^```\\w*$", options: .regularExpression) != nil {
                let textBeforeLine = nsText.substring(to: currentLineRange.location)
                let openingCount = textBeforeLine.components(separatedBy: "```").count - 1
                let afterLineStart = currentLineRange.location + currentLineRange.length
                let hasClosingAfter: Bool = {
                    guard afterLineStart < nsText.length else { return false }
                    return nsText.substring(from: afterLineStart).contains("```")
                }()
                let lineEnd = currentLineRange.location + max(0, currentLineRange.length - 1)
                let cursorAtLineEnd = affectedCharRange.location >= lineEnd

                if openingCount.isMultiple(of: 2) && cursorAtLineEnd && !hasClosingAfter {
                    let insertionLocation = affectedCharRange.location
                    let completion = "\n\n```"
                    MarkdownLists.performEdit(textView, replace: affectedCharRange, with: completion)
                    textView.setSelectedRange(NSRange(location: insertionLocation + 1, length: 0))
                    return false
                }
            }

            // Skip list continuation in code blocks
            guard listsEnabled && !isInCodeBlock else { return true }
            let listLine = nsText.substring(with: currentLineRange)
            if let match = MarkdownLists.listRegex.firstMatch(in: listLine, range: NSRange(location: 0, length: listLine.utf16.count)) {
                let leadingWhitespace: String
                if let wsMatch = MarkdownLists.leadingWhitespaceRegex.firstMatch(in: listLine, range: NSRange(location: 0, length: listLine.utf16.count)) {
                    leadingWhitespace = (listLine as NSString).substring(with: wsMatch.range)
                } else {
                    leadingWhitespace = ""
                }
                let markerRaw = (listLine as NSString).substring(with: match.range(at: 1))
                let marker = markerRaw.trimmingCharacters(in: .whitespaces)
                let hasCheckbox = marker.range(of: #"\[[ xX]\]"#, options: .regularExpression) != nil
                let newListItem: String
                if match.range(at: 2).location != NSNotFound,
                   let number = Int((listLine as NSString).substring(with: match.range(at: 2))) {
                    if hasCheckbox {
                        newListItem = "\n" + leadingWhitespace + "\(number + 1). [ ] "
                    } else {
                        newListItem = "\n" + leadingWhitespace + "\(number + 1). "
                    }
                } else {
                    if hasCheckbox {
                        let bulletChar = marker.contains("•") ? "•" : "-"
                        newListItem = "\n" + leadingWhitespace + "\(bulletChar) [ ] "
                    } else {
                        newListItem = "\n" + leadingWhitespace + marker + " "
                    }
                }
                MarkdownLists.performEdit(textView, replace: affectedCharRange, with: newListItem)
                let nextSelection = NSRange(
                    location: affectedCharRange.location + (newListItem as NSString).length,
                    length: 0
                )
                textView.setSelectedRange(nextSelection)
                DispatchQueue.main.async { [weak textView] in
                    textView?.setSelectedRange(nextSelection)
                }
                return false
            }
        }

        return true
    }
}
