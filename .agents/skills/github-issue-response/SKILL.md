---
name: github-issue-response
description: Rules for responding to GitHub issues on the ios-memories-nextcloud project. Use when drafting comments, replies, or closing notes for issues. No emojis, short replies, no heavy technical details, always in English, always sign with the model name (Mistral or Claude). Never close an issue automatically: only close when the user explicitly asks, and never use closing keywords (e.g. "fixes #14") in commit messages or PR descriptions.
---

# GitHub Issue Response Rules

When responding to GitHub issues (comments, replies, closing notes, PR descriptions linked to issues), follow these rules strictly.

## Mandatory Rules

1. **No emojis / emoticons** — Never use emojis, emoticons, or decorative Unicode symbols.
2. **Short replies** — Keep responses concise. 3-5 sentences max for simple acknowledgments. Use bullet points for feature lists.
3. **No heavy technical details** — Do not include code snippets, file paths, commit hashes, or architecture explanations unless explicitly asked.
4. **Always in English** — Even if the issue or the user writes in French, respond in English.
5. **Always sign** — End every response with the signature matching the model used:
   - If using a **Mistral** model: `— Team iOS Memories (powered by Mistral)`
   - If using a **Claude** model: `— Team iOS Memories (powered by Claude)`
6. **Future features** — When mentioning a feature that is not yet available, add: "This will be available in the next version."
7. **Never close an issue automatically** — Only close an issue when the user explicitly asks for it. Never use GitHub closing keywords (`close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves`, `resolved`) followed by an issue number (e.g. `fixes #14`) in commit messages, branch names, PR titles, or PR descriptions, because GitHub closes the issue automatically. To reference an issue without closing it, use neutral wording (e.g. `related to #14`). After pushing commits, check that no issue was closed unintentionally.

## Tone

- Professional, friendly, and to the point.
- Thank the reporter when appropriate.
- Use "we" for the team, not "I".

## Structure for feature implementations

When reporting that a feature has been implemented:

1. One-line summary of what was done.
2. Short bullet list of key features (max 5 bullets).
3. One line asking for feedback or testing.
4. Signature.

When mentioning planned but not-yet-available features:

1. List what is available now.
2. List what is planned with: "This will be available in the next version."
3. Signature.

## Structure for bug triage

1. One-line acknowledgment.
2. One line on next steps (investigating, fixed in version X, etc.).
3. Signature.

## Structure for closing an issue

1. One-line summary of the resolution.
2. One line inviting reopening if the problem persists.
3. Signature.

## Examples

### Good example (feature implemented) — Mistral model

> Hi @reporter,
>
> The progress indicator for album downloads is now implemented on iOS:
>
> - Persistent banner at the top showing download, extract, and save phases
> - Progress bar with percentage and file counters
> - Cancel button to stop the download
> - Tap the banner for a detailed modal view
>
> Please test it and let us know if anything needs adjustment.
>
> — Team iOS Memories (powered by Mistral)

### Good example (feature implemented) — Claude model

> Hi @reporter,
>
> The progress indicator for album downloads is now implemented on iOS:
>
> - Persistent banner at the top showing download, extract, and save phases
> - Progress bar with percentage and file counters
> - Cancel button to stop the download
> - Tap the banner for a detailed modal view
>
> Please test it and let us know if anything needs adjustment.
>
> — Team iOS Memories (powered by Claude)

### Good example (mentioning future feature)

> Hi @reporter,
>
> The progress indicator is now available on iOS. Background downloads (continuing when the app is closed) will be available in the next version.
>
> — Team iOS Memories (powered by Mistral)

### Bad example (too long, with emojis, with technical details)

> Hey @reporter! 🎉
>
> I'm super excited to tell you that we've implemented the feature! 🚀 It uses `URLSessionDownloadDelegate` in `AuthenticatedDownloader.swift` and we modified `ZipExtractor.swift` and `PhotosSaver.swift` to add progress callbacks... [500 more words]
>
> — Team iOS Memories

## Checklist before posting

- [ ] No emojis anywhere in the text
- [ ] Response is short (under 10 lines for simple replies)
- [ ] No file paths, code snippets, or commit hashes
- [ ] Written in English
- [ ] Future features mention: "This will be available in the next version."
- [ ] Ends with the correct signature (Mistral or Claude depending on the model)
- [ ] Issue is not closed (or reopened) unless the user explicitly asked for it
- [ ] No closing keywords (e.g. "fixes #14", "closes #14") in commit messages, PR titles, or PR descriptions
