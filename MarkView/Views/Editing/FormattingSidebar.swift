import AppKit
import SwiftUI

/// Everything the formatting panel can ask the document to do. Keeping it as a
/// value means the panel stays a dumb view and the document owns all mutation.
enum FormatCommand: Equatable {
    case heading(Int)
    case inline(String)
    case linePrefix(String)
    case orderedList
    case link
    case image
    case codeFence
    case horizontalRule
    case table(rows: Int, columns: Int)
    case direction(MarkdownFormatter.BlockDirection)

    case tableAddRow
    case tableAddColumn
    case tableDeleteRow
    case tableDeleteColumn
    case tableAlign(TableColumnAlignment)
    case tableCellAlign(TableColumnAlignment?)
    case tableCellVerticalAlign(TableVerticalAlignment?)
    case tableMergeRight
    case tableMergeDown
    case tableUnmerge

    case persianFixAll
    case persianNormalizeLetters
    case persianZWNJ
    case persianDigits(persian: Bool)
    case persianPunctuation
    case persianTidyWhitespace
    case pinDirection(rightToLeft: Bool)
}

struct FormattingSidebar: View {
    /// Non-nil when the caret sits inside a table — a live grid in the canvas,
    /// or a Markdown table in Source mode. The panel doesn't care which.
    let tableContext: TableEditingContext?
    let hasSelection: Bool
    /// A transient explanation for a command that couldn't do anything.
    var notice: String?
    let selectionContainsPersian: Bool
    /// What is actually wrong with the Persian text in scope, recomputed by the
    /// document view whenever the text or the selection changes.
    var persianIssues: [PersianIssue] = []
    var persianDigitCounts: (latin: Int, persian: Int) = (0, 0)
    let onCommand: (FormatCommand) -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)

            if let notice {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5, weight: .medium))
                    Text(notice)
                        .font(.system(size: 10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.05))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    styleSection
                    formatSection
                    listSection
                    insertSection
                    directionSection
                    tableSection
                    persianSection
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.automatic)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: tableContext)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: notice)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "textformat")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Format")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hide the formatting panel")
            .accessibilityLabel("Hide formatting panel")
        }
        .frame(height: 52)
        .padding(.horizontal, 14)
    }

    // MARK: - Sections

    private var styleSection: some View {
        section("Text style") {
            VStack(spacing: 5) {
                styleRow("Title", subtitle: "H1", size: 16, weight: .bold,
                         styleHelp: "Make the current line a top-level heading (# )") { onCommand(.heading(1)) }
                styleRow("Heading", subtitle: "H2", size: 14.5, weight: .semibold,
                         styleHelp: "Make the current line a second-level heading (## )") { onCommand(.heading(2)) }
                styleRow("Subheading", subtitle: "H3", size: 13, weight: .semibold,
                         styleHelp: "Make the current line a third-level heading (### )") { onCommand(.heading(3)) }
                styleRow("Body", subtitle: "¶", size: 12.5, weight: .regular,
                         styleHelp: "Remove heading marks and return the line to body text") { onCommand(.heading(0)) }
            }
        }
    }

    private var formatSection: some View {
        section("Format") {
            HStack(spacing: 6) {
                iconButton("bold", help: "Bold — wraps the selection in **, or unwraps it if it already is") { onCommand(.inline("**")) }
                iconButton("italic", help: "Italic — wraps the selection in *, or unwraps it") { onCommand(.inline("*")) }
                iconButton("strikethrough", help: "Strikethrough — wraps the selection in ~~, or unwraps it") { onCommand(.inline("~~")) }
                iconButton("chevron.left.forwardslash.chevron.right", help: "Inline code — wraps the selection in backticks") { onCommand(.inline("`")) }
                iconButton("highlighter", help: "Highlight — wraps the selection in ==, rendered as marked text") { onCommand(.inline("==")) }
            }
        }
    }

    private var listSection: some View {
        section("Lists") {
            HStack(spacing: 6) {
                iconButton("list.bullet", help: "Bulleted list — turns every selected line into a “- ” item, or back into plain lines") { onCommand(.linePrefix("- ")) }
                iconButton("list.number", help: "Numbered list — numbers the selected lines 1., 2., 3. …, or removes the numbering") { onCommand(.orderedList) }
                iconButton("checklist", help: "Task list — turns the selected lines into “- [ ] ” checkboxes") { onCommand(.linePrefix("- [ ] ")) }
                iconButton("text.quote", help: "Block quote — prefixes the selected lines with “> ”") { onCommand(.linePrefix("> ")) }
            }
        }
    }

    private var insertSection: some View {
        section("Insert") {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    iconButton("link", help: "Link — turns the selection into [text](url) and selects the URL so you can type it") { onCommand(.link) }
                    iconButton("photo", help: "Image — choose a picture to place in the document") { onCommand(.image) }
                    iconButton("curlybraces", help: "Code block — puts the selection inside a fenced ``` block") { onCommand(.codeFence) }
                    iconButton("minus", help: "Horizontal rule — inserts a --- divider on its own line") { onCommand(.horizontalRule) }
                    iconButton("tablecells", help: "Table — inserts a 3-column Markdown table below this block") {
                        onCommand(.table(rows: 2, columns: 3))
                    }
                }
            }
        }
    }

    private var directionSection: some View {
        section("Paragraph direction") {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    labelledButton("Right to left", systemImage: "text.alignright",
                                   help: "Wrap this block in a right-to-left container — use it for Persian or Arabic paragraphs") {
                        onCommand(.direction(.rightToLeft))
                    }
                    labelledButton("Left to right", systemImage: "text.alignleft",
                                   help: "Wrap this block in a left-to-right container — use it for Latin text inside an RTL document") {
                        onCommand(.direction(.leftToRight))
                    }
                }
                Text("Wraps the block in a `dir` container — Markdown has no alignment syntax of its own.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var tableSection: some View {
        section("Table") {
            if let tableContext {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Row \(tableContext.caretRow + 1) of \(tableContext.rowCount) · Column \(tableContext.caretColumn + 1) of \(tableContext.columnCount)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        iconButton("rectangle.grid.1x2", help: "Add a row below the one the caret is in") { onCommand(.tableAddRow) }
                        iconButton("rectangle.split.3x1", help: "Add a column after the one the caret is in") { onCommand(.tableAddColumn) }
                        iconButton("trash", help: "Delete the row the caret is in — the header row can’t be deleted") { onCommand(.tableDeleteRow) }
                            .disabled(!tableContext.canDeleteRow)
                        iconButton("trash.slash", help: "Delete the column the caret is in") { onCommand(.tableDeleteColumn) }
                            .disabled(!tableContext.canDeleteColumn)
                    }

                    Text("Column alignment")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.top, 1)

                    HStack(spacing: 6) {
                        alignButton("text.alignleft", alignment: .left, current: tableContext)
                        alignButton("text.aligncenter", alignment: .center, current: tableContext)
                        alignButton("text.alignright", alignment: .right, current: tableContext)
                        alignButton("minus", alignment: .none, current: tableContext)
                    }

                    if tableContext.supportsCellFeatures {
                        cellControls(tableContext)
                    }
                }
                .transition(.opacity)
            } else {
                Text("Put the caret inside a table to edit its rows, columns, and alignment.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The Persian panel, as a report rather than a toolbox.
    ///
    /// It used to be six buttons named after the operations they performed —
    /// "ی و ک", "نیم‌فاصله" — which required already knowing what each did *and*
    /// that your text had that problem. Since every one of these problems is
    /// invisible on screen, the only way to find out was to click all of them
    /// and hope. So the panel now does the looking: it says what is wrong, how
    /// many times, and what the fix turns it into.
    @ViewBuilder
    private var persianSection: some View {
        if selectionContainsPersian || !persianIssues.isEmpty {
            section(hasSelection ? "Persian text · selection" : "Persian text · document") {
                VStack(alignment: .leading, spacing: 8) {
                    if persianIssues.isEmpty {
                        cleanPersianState
                    } else {
                        labelledButton(
                            persianIssues.count == 1
                                ? "Fix 1 issue"
                                : "Fix all \(persianIssues.count) issues",
                            systemImage: "wand.and.stars",
                            help: "Apply every fix below at once. Code blocks are left alone."
                        ) {
                            onCommand(.persianFixAll)
                        }

                        ForEach(persianIssues) { issue in
                            persianIssueRow(issue)
                        }
                    }

                    Divider().opacity(0.4)
                    persianDigitControls
                    persianDirectionControls
                }
            }
        }
    }

    private var cleanPersianState: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
            Text(hasSelection
                 ? "This selection looks clean — letters, half-spaces, and punctuation are all correct."
                 : "This document looks clean — letters, half-spaces, and punctuation are all correct.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func persianIssueRow(_ issue: PersianIssue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: issue.kind.symbolName)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .frame(width: 13)
                Text(issue.kind.title)
                    .font(.system(size: 11, weight: .medium))
                Text("\(issue.count)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.orange.opacity(0.18)))
                    .foregroundStyle(.orange)
                Spacer(minLength: 4)
                Button("Fix") { onCommand(issue.kind.command) }
                    .buttonStyle(FormatButtonStyle())
                    .font(.system(size: 10.5, weight: .medium))
                    .help(issue.kind.explanation)
            }

            // The worked example is what makes an invisible change checkable.
            if let example = issue.example {
                HStack(spacing: 4) {
                    Text(example.before)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 7.5))
                        .foregroundStyle(.tertiary)
                    Text(example.after)
                        .foregroundStyle(.primary)
                }
                .font(.system(size: 10.5))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 19)
            }
        }
        .padding(.vertical, 1)
    }

    /// Digits are a house-style choice, not a mistake, so they sit apart from
    /// the issues and show which way the text currently leans.
    @ViewBuilder
    private var persianDigitControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("Digits")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if persianDigitCounts.latin > 0 || persianDigitCounts.persian > 0 {
                    Text("\(persianDigitCounts.persian) Persian · \(persianDigitCounts.latin) Latin")
                        .font(.system(size: 9.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(spacing: 6) {
                labelledButton("۱۲۳", systemImage: "number",
                               help: "Convert Latin digits to Persian digits (123 → ۱۲۳). Code is left alone.") {
                    onCommand(.persianDigits(persian: true))
                }
                .disabled(persianDigitCounts.latin == 0)

                labelledButton("123", systemImage: "number",
                               help: "Convert Persian and Arabic digits to Latin digits (۱۲۳ → 123). Code is left alone.") {
                    onCommand(.persianDigits(persian: false))
                }
                .disabled(persianDigitCounts.persian == 0)
            }
        }
    }

    /// Direction pinning only means anything for a specific run of text, so it
    /// appears only when there is a selection to pin — rather than sitting
    /// there permanently doing nothing.
    @ViewBuilder
    private var persianDirectionControls: some View {
        if hasSelection {
            VStack(alignment: .leading, spacing: 5) {
                Text("Hold this selection's direction")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    labelledButton("Pin RTL", systemImage: "arrow.left",
                                   help: "Stops numbers or Latin words jumping to the wrong side of a Persian line") {
                        onCommand(.pinDirection(rightToLeft: true))
                    }
                    labelledButton("Pin LTR", systemImage: "arrow.right",
                                   help: "Holds this run on the left inside a Persian line") {
                        onCommand(.pinDirection(rightToLeft: false))
                    }
                }
            }
        } else {
            Text("Select a number or a Latin word to stop it jumping to the wrong side of a Persian line.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Building blocks

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.5)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Icon buttons share the panel's width rather than each taking a fixed
    /// 30pt. A fixed width left a ragged gap down the right-hand side of every
    /// row — and a different gap per row, since the rows hold different
    /// numbers of buttons.
    private func iconButton(_ systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 27)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private func labelledButton(
        _ title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .medium))
                Text(title)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 27)
            .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle())
        .help(help)
        .accessibilityHint(help)
    }

    private func styleRow(
        _ title: String,
        subtitle: String,
        size: CGFloat,
        weight: Font.Weight,
        styleHelp: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: size, weight: weight))
                Spacer()
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle())
        .help(styleHelp)
    }

    /// Controls that act on the one cell the caret is in, rather than its whole
    /// column. Markdown's table syntax has no way to say any of this, so a
    /// table using them is saved as HTML instead — which the note explains, so
    /// the change of format is never a surprise.
    @ViewBuilder
    private func cellControls(_ context: TableEditingContext) -> some View {
        Text("This cell")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.top, 4)

        HStack(spacing: 6) {
            cellAlignButton("text.alignleft", alignment: .left, current: context.cellAlignment)
            cellAlignButton("text.aligncenter", alignment: .center, current: context.cellAlignment)
            cellAlignButton("text.alignright", alignment: .right, current: context.cellAlignment)
            cellAlignButton("arrow.uturn.backward", alignment: nil, current: context.cellAlignment)
        }

        HStack(spacing: 6) {
            verticalAlignButton("arrow.up.to.line", alignment: .top, current: context.cellVerticalAlignment)
            verticalAlignButton("arrow.down.and.line.horizontal.and.arrow.up",
                                alignment: .middle, current: context.cellVerticalAlignment)
            verticalAlignButton("arrow.down.to.line", alignment: .bottom, current: context.cellVerticalAlignment)
            verticalAlignButton("arrow.uturn.backward", alignment: nil, current: context.cellVerticalAlignment)
        }

        Text("Merge")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .padding(.top, 4)

        HStack(spacing: 6) {
            iconButton("arrow.right.to.line",
                       help: "Merge this cell with the one to its right") { onCommand(.tableMergeRight) }
                .disabled(!context.canMergeRight)
            iconButton("arrow.down.to.line",
                       help: "Merge this cell with the one below it") { onCommand(.tableMergeDown) }
                .disabled(!context.canMergeDown)
            iconButton("square.split.2x2",
                       help: "Split this merged cell back into separate cells") { onCommand(.tableUnmerge) }
                .disabled(!context.isMerged)
        }

        Text("Merging and per-cell alignment can’t be written in Markdown table syntax, so this table is saved as HTML.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 1)
    }

    private func cellAlignButton(
        _ systemImage: String,
        alignment: TableColumnAlignment?,
        current: TableColumnAlignment?
    ) -> some View {
        Button {
            onCommand(.tableCellAlign(alignment))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle(isActive: current == alignment && alignment != nil))
        .help(alignment == nil
              ? "Use the column’s alignment for this cell again"
              : "Align just this cell \(alignment!.rawValue)")
    }

    private func verticalAlignButton(
        _ systemImage: String,
        alignment: TableVerticalAlignment?,
        current: TableVerticalAlignment?
    ) -> some View {
        Button {
            onCommand(.tableCellVerticalAlign(alignment))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle(isActive: current == alignment && alignment != nil))
        .help(alignment == nil
              ? "Back to the default vertical position"
              : "Sit this cell’s content at the \(alignment!.rawValue) of its row")
    }

    private func alignmentHelp(_ alignment: TableColumnAlignment) -> String {
        switch alignment {
        case .left: return "Align this column left (:---)"
        case .center: return "Centre this column (:---:)"
        case .right: return "Align this column right (---:)"
        case .none: return "Clear this column’s alignment (---)"
        }
    }

    private func alignButton(
        _ systemImage: String,
        alignment: TableColumnAlignment,
        current: TableEditingContext
    ) -> some View {
        let isActive = current.currentAlignment == alignment

        return Button {
            onCommand(.tableAlign(alignment))
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(FormatButtonStyle(isActive: isActive))
        .help(alignmentHelp(alignment))
    }
}

/// `@State` inside a `ButtonStyle` is never installed — the style is not a
/// `View`, so the property has no storage and never updates. The hover state
/// has to live in a real view, which is what `Body` is for.
private struct FormatButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        FormatButtonBody(configuration: configuration, isActive: isActive)
    }

}

private struct FormatButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(border, lineWidth: isActive || isHovered ? 0.9 : 0.7)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .onHover { hovering in
                guard isEnabled else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.11), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isActive)
    }

    private var foreground: Color {
        guard isEnabled else { return .secondary }
        if isActive { return .accentColor }
        return isHovered ? .primary : .primary.opacity(0.86)
    }

    private var border: Color {
        if isActive { return .accentColor.opacity(0.45) }
        return .primary.opacity(isHovered ? 0.22 : 0.11)
    }

    private var background: Color {
        if isActive { return .accentColor.opacity(configuration.isPressed ? 0.28 : 0.17) }
        if configuration.isPressed { return .primary.opacity(0.15) }
        return .primary.opacity(isHovered ? 0.105 : 0.055)
    }
}
