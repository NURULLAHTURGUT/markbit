# Contributing to Markbit

Thanks for helping make Markbit better! Bug reports, ideas, translations, documentation and code are all welcome.

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to help

- **Report a bug** — open an [issue](https://github.com/NURULLAHTURGUT/markbit/issues/new/choose) using the bug report form. Steps to reproduce, your Markbit version and your operating system help a lot.
- **Suggest a feature** — use the feature request form and describe the problem you want to solve, not only the solution.
- **Improve a translation** or add a new language — see [Translations](#translations).
- **Test on your platform** — reports from different Windows, macOS and Linux setups are very helpful. Android and iOS build from source but are not released yet.
- **Write code** — issues labelled `good first issue` are a good place to start. For larger changes, please open an issue first so we can agree on the approach before you spend time on it.

Security problems should **not** be reported in public issues — see [SECURITY.md](SECURITY.md).

## Development setup

You need:

- [Flutter 3.47.6](https://docs.flutter.dev/get-started/install) (stable channel)
- The desktop toolchain of your platform: Visual Studio with the *Desktop development with C++* workload on Windows, Xcode on macOS, or `clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev` on Linux

```bash
git clone https://github.com/NURULLAHTURGUT/markbit.git
cd markbit
flutter pub get
flutter run -d windows   # or: -d macos, -d linux
```

The [README](README.md#-build-from-source) explains release builds and the project structure.

## Before you open a pull request

Run the same checks as CI — all of them must pass:

```bash
dart format lib test
flutter analyze
flutter test
```

- **Tests:** add or update tests for every change in behaviour. Pure logic lives in `lib/domain/` and is easy to unit test; widget tests live next to the other files in `test/`.
- **Style:** follow the existing code. Keep comments short and explain *why*, not *what*. Use the design tokens in `lib/core/theme/` (`Sp`, `Rad`, `Fs`, the palette) instead of hard-coded sizes and colours.
- **User-facing text** goes through `context.tr('English text')` (or `trs()` outside widgets), never as a hard-coded string.

## Translations

The English text is the key; each language is a map from English to the translation.

| Language | File(s) |
| --- | --- |
| Turkish | `lib/core/l10n/tr_editor.dart`, `tr_settings.dart`, `tr_misc.dart` |
| German | `lib/core/l10n/de_strings.dart` |
| Spanish | `lib/core/l10n/es_strings.dart` |

- When you add a new English string, add it to **every** language file. A test fails if German or Spanish is missing a key that Turkish has.
- Keep placeholders such as `{n}` or `{name}` exactly as they are.
- To add a language: create `lib/core/l10n/<code>_strings.dart`, then register it in `supportedLocales`, `languageNames` and `_tables` in `lib/core/l10n/app_strings.dart`.

## Pull requests

1. Fork the repository and create a branch from `main`, for example `fix/editor-scroll` or `feature/export-epub`.
2. Keep each pull request focused on one change.
3. Write a clear title and description: what changes, why, and how you tested it. Add screenshots for UI changes.
4. Make sure CI is green. Pull requests are merged with **squash**, so the title becomes the commit message on `main`.

Commit and pull request titles are short and in the imperative mood, for example *"Fix task reminder time zone"* or *"Add EPUB export"*.

## License

Markbit is licensed under the [Apache License 2.0](LICENSE). By contributing, you agree that your contributions are licensed under the same license.
