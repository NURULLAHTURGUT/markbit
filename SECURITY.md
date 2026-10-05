# Security Policy

## Supported versions

Security fixes are made for the latest release of Markbit. Please update to the newest version before reporting a problem.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report vulnerabilities privately through GitHub:
[**Report a vulnerability**](https://github.com/NURULLAHTURGUT/markbit/security/advisories/new)
(repository → *Security* tab → *Report a vulnerability*).

Please include:

- what the problem is and what an attacker could do with it,
- steps to reproduce (a sample note, file or backup helps),
- the Markbit version and your operating system.

You can expect a first response within a week. Once a fix is released, the report will be credited unless you prefer to stay anonymous.

## How Markbit handles your data

Knowing the design helps to judge what counts as a vulnerability.

### Running code

Markbit runs code from your notes **on your own computer** with the compilers and interpreters on your `PATH`, under your user account and without a sandbox.

- Code never runs by itself: only when you press **Run** (or `Ctrl+Enter`) on a block.
- Imported notes (Obsidian, Notion, Evernote, Joplin, Markdown) and restored backups do not run anything when they are opened.
- **Only run code you trust**, especially in notes you received from others.

Code running without an explicit Run action would be a security bug.

### Network access

Markbit has no telemetry and works offline. It only connects to the network for features you turn on:

| Feature | What is sent | Where |
| --- | --- | --- |
| AI assistant | Your message, the open note and any notes or files you add as context | The AI provider you configure |
| Remote code execution (off by default) | The code you run and its input | The Piston server you configure |
| HTML export with math or diagrams | Nothing from your notes; the exported page loads KaTeX / Mermaid | jsDelivr CDN, when the page is opened |
| Web images in notes (`![](https://…)`) | A normal image request when the preview shows the image | The image's site |
| Links in notes | Nothing until you click them | The linked site |

### Secrets and stored data

- API keys are kept in the operating system's secure storage and are never written to notes, exports or backups.
- Notes are stored as plain JSON files in the app's data folder. **Locked notes** are encrypted with your password; other notes are not encrypted at rest, so protect your device account.
- Backups (`.markbit`) contain your notes, chats and settings in readable form — store them as carefully as the notes themselves.
