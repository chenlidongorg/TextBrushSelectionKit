#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
import NaturalLanguage
import SwiftUI

public enum TextBrushSelectionKitStrings {
    public static var title: String {
        textBrushLocalized("text_brush_selection")
    }

    public static func string(_ key: String) -> String {
        textBrushLocalized(key)
    }
}

@available(iOS 13.0, macOS 11.0, *)
public struct TextBrushSelectionView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let allTokens: [TextBrushToken]
    private let keywordTokens: [TextBrushToken]
    private let coordinateSpaceName = "TextBrushSelectionCoordinateSpace"

    @State private var mode: TextBrushSelectionMode = .full
    @State private var selectedIDs: Set<Int> = []
    @State private var tokenFrames: [Int: CGRect] = [:]
    @State private var dragIsHorizontalSelection: Bool?
    @State private var dragSelectionTarget: Bool?
    @State private var dragVisitedIDs: Set<Int> = []
    @State private var copiedFeedback = false
    @State private var showShareSheet = false
    @State private var shareText = ""

    public init(text: String) {
        let allTokens = TextBrushTokenizer.tokens(from: text)
        self.allTokens = allTokens
        self.keywordTokens = TextBrushKeywordExtractor.keywordTokens(from: text, fallbackTokens: allTokens)
    }

    public var body: some View {
        ZStack {
            backgroundColor.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                modeSelector

                if visibleTokens.isEmpty {
                    emptyContent
                } else {
                    tokenScrollView
                }

                bottomBar
            }

            if copiedFeedback {
                copiedToast
                    .transition(.opacity.combined(with: .scale))
            }
        }
#if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            TextBrushSelectionActivityView(text: shareText)
        }
#endif
    }

    private var tokenScrollView: some View {
        GeometryReader { proxy in
            let rows = TextBrushRowBuilder.rows(
                from: visibleTokens,
                maxWidth: max(proxy.size.width - 36, 1),
                spacing: 5
            )

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(rows) { row in
                        HStack(spacing: 5) {
                            ForEach(row.tokens) { token in
                                tokenCell(token)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
                .coordinateSpace(name: coordinateSpaceName)
                .onPreferenceChange(TextBrushTokenFramePreferenceKey.self) { frames in
                    tokenFrames = frames
                }
#if os(iOS)
                .background(
                    TextBrushHorizontalPanBridge(
                        onChanged: { location in
                            dragIsHorizontalSelection = true
                            applyDragSelection(at: location)
                        },
                        onEnded: resetDragSelectionState
                    )
                )
#else
                .simultaneousGesture(selectionDragGesture)
#endif
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 4) {
            ForEach(TextBrushSelectionMode.allCases) { option in
                Button(action: {
                    guard mode != option else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        mode = option
                        selectedIDs.removeAll()
                        tokenFrames.removeAll()
                    }
                }) {
                    Text(textBrushLocalized(option.localizationKey))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(mode == option ? Color.white : primaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(mode == option ? selectedBlockColor : Color.clear)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selectorBackgroundColor))
        .padding(.horizontal, 18)
        .padding(.top, 90)
        .padding(.bottom, 6)
    }

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.cursor")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(secondaryTextColor)

            Text(textBrushLocalized("text_brush_empty"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(secondaryTextColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var bottomBar: some View {
        HStack(spacing: 38) {
            Spacer(minLength: 0)

            bottomButton(
                systemName: isAllSelected ? "checkmark.square.fill" : "checklist",
                title: textBrushLocalized(isAllSelected ? "text_brush_deselect_all" : "text_brush_select_all"),
                isEnabled: !visibleTokens.isEmpty,
                action: toggleAllSelection
            )

            bottomButton(
                systemName: "doc.on.doc",
                title: textBrushLocalized("text_brush_copy"),
                isEnabled: hasSelection,
                action: copySelection
            )

            bottomButton(
                systemName: "square.and.arrow.up",
                title: textBrushLocalized("text_brush_share"),
                isEnabled: hasSelection,
                action: shareSelection
            )

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 22)
        .background(bottomBarColor)
    }

    private func tokenCell(_ token: TextBrushToken) -> some View {
        let isSelected = selectedIDs.contains(token.id)

        return Text(token.text)
            .font(.system(size: tokenFontSize(for: token), weight: .semibold, design: .rounded))
            .foregroundColor(isSelected ? selectedTextColor : primaryTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, horizontalPadding(for: token))
            .frame(minWidth: minWidth(for: token), minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isSelected ? selectedBlockColor : blockColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(isSelected ? selectedStrokeColor : blockStrokeColor, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                toggleToken(token.id)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: TextBrushTokenFramePreferenceKey.self,
                        value: [token.id: proxy.frame(in: .named(coordinateSpaceName))]
                    )
                }
            )
    }

    private func bottomButton(systemName: String, title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: {
            guard isEnabled else { return }
            action()
        }) {
            VStack(spacing: 6) {
                Image(systemName: systemName)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 32, height: 26)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(isEnabled ? primaryTextColor : disabledTextColor)
            .frame(width: 72, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var selectionDragGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(coordinateSpaceName))
            .onChanged { value in
                if dragIsHorizontalSelection == nil {
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)
                    guard horizontalDistance > 12 || verticalDistance > 12 else { return }
                    dragIsHorizontalSelection = horizontalDistance > verticalDistance * 1.4
                }

                guard dragIsHorizontalSelection == true else { return }
                applyDragSelection(at: value.location)
            }
            .onEnded { _ in
                resetDragSelectionState()
            }
    }

    private func resetDragSelectionState() {
        dragIsHorizontalSelection = nil
        dragSelectionTarget = nil
        dragVisitedIDs.removeAll()
    }

    private func applyDragSelection(at location: CGPoint) {
        guard let tokenID = tokenFrames.first(where: { $0.value.insetBy(dx: -5, dy: -5).contains(location) })?.key else {
            return
        }

        if dragSelectionTarget == nil {
            dragSelectionTarget = !selectedIDs.contains(tokenID)
        }

        guard !dragVisitedIDs.contains(tokenID), let target = dragSelectionTarget else {
            return
        }

        dragVisitedIDs.insert(tokenID)
        if target {
            selectedIDs.insert(tokenID)
        } else {
            selectedIDs.remove(tokenID)
        }
    }

    private func toggleToken(_ id: Int) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func toggleAllSelection() {
        if isAllSelected {
            selectedIDs.removeAll()
        } else {
            selectedIDs = Set(visibleTokens.map(\.id))
        }
    }

    private func copySelection() {
        let text = selectedText
        guard !text.isEmpty else { return }
        TextBrushClipboard.copy(text)
        showCopiedFeedback()
    }

    private func shareSelection() {
        let text = selectedText
        guard !text.isEmpty else { return }
#if os(iOS)
        shareText = text
        showShareSheet = true
#else
        copySelection()
#endif
    }

    private func showCopiedFeedback() {
        withAnimation(.easeInOut(duration: 0.16)) {
            copiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.18)) {
                copiedFeedback = false
            }
        }
    }

    private var selectedText: String {
        TextBrushCopyBuilder.text(from: visibleTokens.filter { selectedIDs.contains($0.id) })
    }

    private var hasSelection: Bool {
        !selectedIDs.isEmpty
    }

    private var isAllSelected: Bool {
        !visibleTokens.isEmpty && selectedIDs.count == visibleTokens.count
    }

    private var visibleTokens: [TextBrushToken] {
        switch mode {
        case .full:
            return allTokens
        case .keywords:
            return keywordTokens
        }
    }

    private var copiedToast: some View {
        Text(textBrushLocalized("text_brush_copied"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(toastTextColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(toastBackgroundColor))
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.16), radius: 12, x: 0, y: 6)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.12) : Color(red: 0.96, green: 0.96, blue: 0.95)
    }

    private var bottomBarColor: Color {
        colorScheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.11).opacity(0.96) : Color.white.opacity(0.96)
    }

    private var selectorBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06)
    }

    private var blockColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }

    private var blockStrokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.04)
    }

    private var selectedBlockColor: Color {
        Color.accentColor
    }

    private var selectedStrokeColor: Color {
        Color.accentColor.opacity(colorScheme == .dark ? 0.82 : 0.72)
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.86) : Color.black.opacity(0.82)
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.50)
    }

    private var disabledTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.28) : Color.black.opacity(0.26)
    }

    private var selectedTextColor: Color {
        Color.white
    }

    private var toastTextColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var toastBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.90) : Color.black.opacity(0.82)
    }

    private func tokenFontSize(for token: TextBrushToken) -> CGFloat {
        token.kind == .word && token.text.count > 14 ? 17 : 20
    }

    private func horizontalPadding(for token: TextBrushToken) -> CGFloat {
        token.kind == .word ? 12 : 10
    }

    private func minWidth(for token: TextBrushToken) -> CGFloat {
        token.kind == .word ? 42 : 36
    }
}

private enum TextBrushSelectionMode: String, CaseIterable, Identifiable {
    case full
    case keywords

    var id: String { rawValue }

    var localizationKey: String {
        switch self {
        case .full: return "text_brush_mode_full"
        case .keywords: return "text_brush_mode_keywords"
        }
    }
}

private struct TextBrushTokenFramePreferenceKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TextBrushToken: Identifiable, Hashable {
    enum Kind {
        case word
        case cjk
        case punctuation
        case symbol
    }

    let id: Int
    let text: String
    let leadingWhitespace: String
    let kind: Kind
}

private struct TextBrushTokenRow: Identifiable {
    let id: Int
    let tokens: [TextBrushToken]
}

private enum TextBrushRowBuilder {
    static func rows(from tokens: [TextBrushToken], maxWidth: CGFloat, spacing: CGFloat) -> [TextBrushTokenRow] {
        var rows: [TextBrushTokenRow] = []
        var currentTokens: [TextBrushToken] = []
        var currentWidth: CGFloat = 0

        func appendCurrentRow() {
            guard let firstID = currentTokens.first?.id else { return }
            rows.append(TextBrushTokenRow(id: firstID, tokens: currentTokens))
            currentTokens.removeAll()
            currentWidth = 0
        }

        for token in tokens {
            let tokenWidth = min(estimatedWidth(for: token), maxWidth)
            let nextWidth = currentTokens.isEmpty ? tokenWidth : currentWidth + spacing + tokenWidth

            if !currentTokens.isEmpty && nextWidth > maxWidth {
                appendCurrentRow()
            }

            currentTokens.append(token)
            currentWidth = currentTokens.count == 1 ? tokenWidth : currentWidth + spacing + tokenWidth
        }

        appendCurrentRow()
        return rows
    }

    private static func estimatedWidth(for token: TextBrushToken) -> CGFloat {
        let scalarCount = max(token.text.unicodeScalars.count, 1)

        switch token.kind {
        case .word:
            let fontSize: CGFloat = token.text.count > 14 ? 17 : 20
            return max(42, CGFloat(scalarCount) * fontSize * 0.58 + 24)
        case .cjk:
            return max(36, CGFloat(scalarCount) * 22 + 20)
        case .punctuation, .symbol:
            return max(36, CGFloat(scalarCount) * 16 + 20)
        }
    }
}

private enum TextBrushTokenizer {
    static func tokens(from text: String) -> [TextBrushToken] {
        var tokens: [TextBrushToken] = []
        var pendingWhitespace = ""
        var word = ""
        var wordLeadingWhitespace = ""
        var punctuation = ""
        var punctuationLeadingWhitespace = ""

        func appendToken(_ text: String, leadingWhitespace: String, kind: TextBrushToken.Kind) {
            guard !text.isEmpty else { return }
            tokens.append(TextBrushToken(id: tokens.count, text: text, leadingWhitespace: leadingWhitespace, kind: kind))
        }

        func flushWord() {
            appendToken(word, leadingWhitespace: wordLeadingWhitespace, kind: .word)
            word = ""
            wordLeadingWhitespace = ""
        }

        func flushPunctuation() {
            appendToken(punctuation, leadingWhitespace: punctuationLeadingWhitespace, kind: .punctuation)
            punctuation = ""
            punctuationLeadingWhitespace = ""
        }

        for character in text {
            if isWhitespace(character) {
                flushWord()
                flushPunctuation()
                pendingWhitespace.append(character)
                continue
            }

            if isCJKLike(character) {
                flushWord()
                flushPunctuation()
                appendToken(String(character), leadingWhitespace: pendingWhitespace, kind: .cjk)
                pendingWhitespace = ""
                continue
            }

            if isWordCharacter(character) || isWordJoiner(character, currentWord: word) {
                flushPunctuation()
                if word.isEmpty {
                    wordLeadingWhitespace = pendingWhitespace
                    pendingWhitespace = ""
                }
                word.append(character)
                continue
            }

            flushWord()

            if isPunctuation(character) {
                if punctuation.isEmpty {
                    punctuationLeadingWhitespace = pendingWhitespace
                    pendingWhitespace = ""
                }
                punctuation.append(character)
            } else {
                flushPunctuation()
                appendToken(String(character), leadingWhitespace: pendingWhitespace, kind: .symbol)
                pendingWhitespace = ""
            }
        }

        flushWord()
        flushPunctuation()

        return tokens
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.nonBaseCharacters.contains(scalar)
        }
    }

    private static func isWordJoiner(_ character: Character, currentWord: String) -> Bool {
        guard !currentWord.isEmpty else { return false }
        return character == "'" || character == "’" || character == "-" || character == "‑"
    }

    private static func isPunctuation(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.punctuationCharacters.contains($0) }
    }

    fileprivate static func isCJKLike(_ character: Character) -> Bool {
        character.unicodeScalars.contains { scalar in
            isCJKLikeValue(scalar.value)
        }
    }

    fileprivate static func isCJKLikeValue(_ value: UInt32) -> Bool {
        isCJK(value) || isKana(value) || isHangul(value)
    }

    fileprivate static func isCJK(_ value: UInt32) -> Bool {
        (0x4E00...0x9FFF).contains(value) || (0x3400...0x4DBF).contains(value)
    }

    fileprivate static func isKana(_ value: UInt32) -> Bool {
        (0x3040...0x30FF).contains(value)
    }

    fileprivate static func isHangul(_ value: UInt32) -> Bool {
        (0xAC00...0xD7AF).contains(value)
    }
}

private enum TextBrushKeywordExtractor {
    static func keywordTokens(from text: String, fallbackTokens: [TextBrushToken]) -> [TextBrushToken] {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return [] }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(normalizedText)
        let language = recognizer.dominantLanguage
        let candidates = keywordCandidates(from: normalizedText, language: language)
        let uniqueCandidates = unique(candidates).filter { isUsefulKeyword($0) }

        if uniqueCandidates.isEmpty {
            return fallbackKeywords(from: fallbackTokens)
        }

        return uniqueCandidates.enumerated().map { index, keyword in
            TextBrushToken(
                id: index,
                text: keyword,
                leadingWhitespace: index == 0 ? "" : " ",
                kind: keyword.unicodeScalars.contains { TextBrushTokenizer.isCJKLikeValue($0.value) } ? .cjk : .word
            )
        }
    }

    private static func keywordCandidates(from text: String, language: NLLanguage?) -> [String] {
        var candidates: [String] = []
        let tagger = NLTagger(tagSchemes: [.lexicalClass, .nameType])
        tagger.string = text
        if let language = language {
            tagger.setLanguage(language, range: text.startIndex..<text.endIndex)
        }

        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, tokenRange in
            if tag != nil {
                candidates.append(String(text[tokenRange]))
            }
            return true
        }

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, tokenRange in
            let token = String(text[tokenRange])
            if tag == .noun || tag == .verb || tag == .adjective || tag == .personalName || tag == .placeName || tag == .organizationName {
                candidates.append(token)
            }
            return true
        }

        return candidates
    }

    private static func fallbackKeywords(from tokens: [TextBrushToken]) -> [TextBrushToken] {
        let candidates = unique(
            tokens.compactMap { token -> String? in
                guard token.kind == .word || token.kind == .cjk else { return nil }
                return token.text
            }
        )
        .filter { isUsefulKeyword($0) }

        return candidates.enumerated().map { index, keyword in
            TextBrushToken(
                id: index,
                text: keyword,
                leadingWhitespace: index == 0 ? "" : " ",
                kind: keyword.unicodeScalars.contains { TextBrushTokenizer.isCJKLikeValue($0.value) } ? .cjk : .word
            )
        }
    }

    private static func unique(_ strings: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for string in strings {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }

        return result
    }

    private static func isUsefulKeyword(_ keyword: String) -> Bool {
        let scalarCount = keyword.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
        if keyword.unicodeScalars.contains(where: { TextBrushTokenizer.isCJKLikeValue($0.value) }) {
            return scalarCount >= 1
        }

        return scalarCount >= 2
    }
}

private enum TextBrushCopyBuilder {
    static func text(from tokens: [TextBrushToken]) -> String {
        var output = ""

        for token in tokens.sorted(by: { $0.id < $1.id }) {
            if output.isEmpty {
                output += token.text
            } else {
                output += token.leadingWhitespace
                output += token.text
            }
        }

        return output
    }
}

private enum TextBrushClipboard {
    static func copy(_ text: String) {
#if os(iOS)
        UIPasteboard.general.string = text
#elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#endif
    }
}

#if os(iOS)
private struct TextBrushHorizontalPanBridge: UIViewRepresentable {
    let onChanged: (CGPoint) -> Void
    let onEnded: () -> Void

    func makeUIView(context: Context) -> TextBrushPanHostView {
        let view = TextBrushPanHostView()
        view.backgroundColor = .clear
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateUIView(_ uiView: TextBrushPanHostView, context: Context) {
        uiView.onChanged = onChanged
        uiView.onEnded = onEnded
        DispatchQueue.main.async {
            uiView.installIfNeeded()
        }
    }
}

private final class TextBrushPanHostView: UIView, UIGestureRecognizerDelegate {
    var onChanged: ((CGPoint) -> Void)?
    var onEnded: (() -> Void)?

    private weak var installedScrollView: UIScrollView?
    private var panRecognizer: UIPanGestureRecognizer?

    deinit {
        if let panRecognizer = panRecognizer {
            installedScrollView?.removeGestureRecognizer(panRecognizer)
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installIfNeeded()
    }

    func installIfNeeded() {
        guard let scrollView = nearestScrollView() else { return }
        guard installedScrollView !== scrollView else { return }

        if let panRecognizer = panRecognizer {
            installedScrollView?.removeGestureRecognizer(panRecognizer)
        }

        let recognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        recognizer.delegate = self
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        scrollView.addGestureRecognizer(recognizer)

        installedScrollView = scrollView
        panRecognizer = recognizer
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onChanged?(recognizer.location(in: self))
        case .ended, .cancelled, .failed:
            onEnded?()
        default:
            break
        }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let panRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = panRecognizer.velocity(in: self)
        let horizontalVelocity = abs(velocity.x)
        let verticalVelocity = abs(velocity.y)
        return horizontalVelocity > 40 && horizontalVelocity > verticalVelocity * 1.35
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    private func nearestScrollView() -> UIScrollView? {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                return scrollView
            }
            candidate = view.superview
        }
        return nil
    }
}

private final class TextBrushPlainTextActivityItem: NSObject, UIActivityItemSource {
    private let text: NSString

    init(text: String) {
        self.text = text as NSString
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        text
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        textBrushLocalized("text_brush_selection")
    }

    func activityViewController(_ activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?) -> String {
        "public.utf8-plain-text"
    }
}

private struct TextBrushSelectionActivityView: UIViewControllerRepresentable {
    let text: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [TextBrushPlainTextActivityItem(text: text)], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

private func textBrushLocalized(_ key: String) -> String {
    NSLocalizedString(key, tableName: nil, bundle: .module, value: key, comment: "")
}
