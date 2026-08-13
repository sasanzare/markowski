---
type: View
title: AIAssistantSidebar
description: The chat-style sidebar for the AI assistant — conversation history, streaming responses, and content blocks.
resource: MarkView/Views/AI/AIAssistantSidebar.swift
tags: [view, ai, sidebar]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Renders `AIService.conversation` as a scrolling list of `AIMessage`s,
each expanded into its `contentBlocks` (`markdown`, `documentReference`,
`editProposal`, `status`, `error` — see
[AIContentBlock](../architecture/ai-assistant.md)). While
`AIService.currentState` is `.streaming`, it renders
`AIService.streamingPreview` incrementally rather than waiting for the
full response, plus `AIService.streamingProgressNote` when the model is
streaming a document rewrite that can't be shown raw.

A `markdown` block is rendered by `StreamingTextView`, which splits the
source into blocks and parses only *inline* syntax within each one.
Handing whole Markdown to `AttributedString(markdown:)` instead collapses
headings, lists, and code onto a single run-on line. The word-by-word
reveal runs only while a response is streaming; a finished answer appears
whole rather than replaying the typewriter.

Each prose block independently resolves its base writing direction from its
first strong character. Persian-first paragraphs and list items use RTL
paragraph layout and the bundled IRANSansX family, while embedded Latin runs
remain ordered by AppKit's Unicode bidi engine. The same direction and font
selection is applied to the user bubble and prompt editor. Fenced code remains
LTR and monospaced; its language tag is retained and a semantic adaptive
palette highlights keywords, strings, numbers, types, functions, and comments
inside a dedicated light/dark code surface.

The sidebar gates on `AIService.missingKeyProvider` — the provider a
request would actually use — not on whichever provider was toggled last.

# Pinned prompt context

`PromptContext` is the one concept behind "ask about this", from either
source — `.document` (the preview or the source editor) or `.reply`
(text selected inside one of Markowski's own answers, which is why chat
Markdown is rendered with `SelectableMarkdownText`).

It is **pinned**: it survives the underlying selection collapsing, and is
cleared only by its own ✕, or replaced by the next selection. This is the
whole point. Clicking into the composer drops the selection in both the
web view and the source editor, so a context derived live from the
current selection disappeared at the exact moment the user went to type
their question. Neither selection source may report a collapse — see
[the rendering pipeline](../architecture/rendering-pipeline.md) and
`SourceView.textViewDidChangeSelection`.

The two sources are *not* interchangeable at send time. A `.document`
context is passed as `sendMessage(selectedText:)`, which instructs the
model to confine an edit to that passage. A `.reply` context is not in
the document at all, so it is quoted into the prompt instead — passing it
as `selectedText` would scope an edit to text that does not exist in the
file.

A `documentReference` block, when tapped, drives
[DocumentNavigator.navigateToLocation](../components/document-navigator.md)
to jump the source/preview to the cited spot. An `editProposal` block
opens [DiffReviewSheet](diff-review-sheet.md) rather than applying the
edit directly.

Composer input, provider/model selection surface, and cancel/stop
affordances for an in-flight request (`AIService.isRequestInFlight`) also
live here; provider and key configuration itself is delegated to
[AISettingsView](ai-settings-view.md).

The composer follows the compact prompt-box pattern used by the reference
design: a multi-line “Ask me anything…” field sits above a footer containing
the model selector, adjacent text/Markdown attachment action, and circular
send button. There is no decorative search icon or divider above the box.
The field starts short, grows smoothly for longer prompts, then keeps the
remaining text scrollable within a 164-point capped height. The editor uses a
native AppKit `NSTextView` inside an `NSScrollView`, so a vertical scrollbar is
available once the content exceeds the viewport. On every edit the caret's
line is brought into view, keeping the latest typed line visible by default;
the user can scroll back to earlier lines and the next edit returns the view
to the caret. Return sends the prompt; Shift+Return inserts a new line. It
intentionally has no audio-input control.
The placeholder is drawn by the native text editor, so it disappears on the same edit that inserts the first character. Assistant markdown is revealed by word-sized updates at a fast cadence, including after a response has been committed; the response row also enters with a short fade/spring transition. Reduce Motion removes the spatial offset and softens the row transition, while the content reveal remains available as response-progress feedback. The sidebar and resize handle enter from the trailing edge together with a spring transition.
The model popover includes a search field and lists all configured-provider
models in one vertical list, so an unconfigured OpenAI provider contributes
no models.

The empty state is branded **Ask Markowski**, matching the app's Markowski
display name while the source project remains `MarkView`. Before the first
message, the supplied full Markowski character, title, supporting copy, and
four starter actions are centered together in the conversation area; only the
settings action remains at the top edge. After the first prompt is submitted,
that empty state is replaced by the conversation and the compact character
plus Markowski title enters in the centered header with a reduce-motion-aware
bounce. Assistant rows do not repeat the character. The starter actions use
distinct document, writing, search, and diagram symbols.
Those four symbols use restrained blue, purple, orange, and green semantic
accents while their labels stay neutral. List markers use top alignment plus a
fixed marker column so bullets and multi-digit ordered markers stay aligned to
the first line of wrapped content.
RTL ordered-list punctuation is emitted on the visual left of its number rather
than left to the bidi algorithm. The assistant accent family is a contrast-
adjusted copper/amber sampled from Markowski: opaque copper user bubbles,
brighter send/focus controls, and softer pinned-selection surfaces. Malformed
provider replies that expose `u0646`-style Unicode escapes are recovered before
display, while the shared provider instruction explicitly forbids that output.

The sidebar uses adaptive macOS semantic surfaces rather than stacked translucent white layers. Its header, conversation canvas, controls, and composer form a clear hierarchy in both appearances without inheriting unpredictable wallpaper colors. The composer is one continuous input surface with no internal divider; in dark appearance it uses `#2E2E2E` and brightens on hover. Model, attachment, suggestion, and send actions use consistent resting, hover, and pressed surfaces so their button affordance remains visible without introducing additional controls. User messages use the system blue accent with white text for a stable, recognizable bubble in light and dark mode. This remains a visual layer only; it does not add controls or change the chat flow.

The inspector is rendered as its own rounded pane beside the document pane, with no hard header separator so the material reads as one continuous surface. Decorative composer fills and borders are non-interactive overlays, preserving hit-testing for the native editor, model selector, attachment action, and send/stop control.

Pinned document context is an intrinsic-height card that shows up to six lines
of the real selection and retains remove and jump-to-source actions. Applied
proposal cards retain the original document snapshot and keep Undo plus Revert
visible for the latest AI change.
