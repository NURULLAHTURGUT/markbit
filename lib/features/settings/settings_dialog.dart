import '../../application/collections.dart';
import '../../core/l10n/app_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/providers.dart';
import '../../application/auto_backup.dart';
import '../../application/data_reset.dart';
import '../../application/persistence_coordinator.dart';
import '../../application/ai_notifier.dart';
import '../../application/ui_providers.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/util/platform_info.dart';
import '../../data/export_service.dart';
import 'dart:convert';
import 'dart:io';
import '../../data/backup_service.dart';
import '../../data/repository/chat_store.dart';
import '../../data/repository/library_repository.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/note.dart';
import '../../domain/ai/ai_client.dart';
import '../../domain/languages.dart';
import '../../core/widgets/app_dialog.dart';
import '../../core/widgets/app_icon_button.dart';
import '../dialogs/dialogs.dart';
import '../dialogs/import_dialog.dart';
import 'shortcuts_tab.dart';

Future<void> showSettingsDialog(BuildContext context, {int initialTab = 0}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(Sp.lg),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 620),
        child: SettingsView(initialTab: initialTab),
      ),
    ),
  );
}

const _tabs = <(String, IconData)>[
  ('Appearance', Icons.palette_outlined),
  ('Editor', Icons.edit_note_rounded),
  ('AI assistant', Icons.auto_awesome_outlined),
  ('Code execution', Icons.terminal_rounded),
  ('Data', Icons.folder_outlined),
  ('Keyboard shortcuts', Icons.keyboard_outlined),
];

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = switch (_tab) {
      0 => const _AppearanceTab(),
      1 => const _EditorTab(),
      2 => const _AiTab(),
      3 => const _ExecutionTab(),
      4 => const _DataTab(),
      _ => const ShortcutsTab(),
    };

    return LayoutBuilder(
      builder: (context, cons) {
        final wide = cons.maxWidth >= 620;
        final nav = wide
            ? SizedBox(
                width: 210,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Sp.lg,
                        Sp.lg + Sp.xs,
                        Sp.lg,
                        Sp.md,
                      ),
                      child: Text(
                        context.tr('Settings'),
                        style: const TextStyle(
                          fontSize: Fs.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    for (var i = 0; i < _tabs.length; i++)
                      _NavItem(
                        label: context.tr(_tabs[i].$1),
                        icon: _tabs[i].$2,
                        selected: _tab == i,
                        onTap: () => setState(() => _tab = i),
                      ),
                  ],
                ),
              )
            : SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.all(Sp.sm),
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: Sp.sm),
                        child: ChoiceChip(
                          label: Text(context.tr(_tabs[i].$1)),
                          selected: _tab == i,
                          onSelected: (_) => setState(() => _tab = i),
                        ),
                      ),
                  ],
                ),
              );

        final body = Expanded(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.xl, Sp.xl, Sp.xl),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: content,
                  ),
                ),
              ),
              Positioned(
                top: Sp.xs,
                right: Sp.xs,
                child: AppIconButton(
                  icon: Icons.close_rounded,
                  tooltip: context.tr('Close'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ],
          ),
        );

        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(color: p.sidebarBg, child: nav),
                  VerticalDivider(width: 1, color: p.border),
                  body,
                ],
              )
            : Column(
                children: [
                  nav,
                  Divider(height: 1, color: p.border),
                  body,
                ],
              );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 1),
      child: Material(
        color: selected ? p.selection : Colors.transparent,
        borderRadius: BorderRadius.circular(Rad.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.md,
              vertical: Sp.sm + 1,
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? p.accent : p.textMuted),
                const SizedBox(width: Sp.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? p.text : p.textMuted,
                      fontSize: Fs.label,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

class _Heading extends StatelessWidget {
  const _Heading(this.title, [this.subtitle]);
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg, right: 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: Fs.heading + 2,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              subtitle!,
              style: TextStyle(
                color: p.textMuted,
                fontSize: Fs.small,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child, {this.help});
  final String label;
  final Widget child;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: Sp.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: Fs.small,
            ),
          ),
          const SizedBox(height: Sp.sm),
          child,
          if (help != null) ...[
            const SizedBox(height: Sp.sm - 2),
            Text(
              help!,
              style: TextStyle(
                color: p.textFaint,
                fontSize: Fs.caption,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- appearance

class _AppearanceTab extends ConsumerWidget {
  const _AppearanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final p = context.palette;
    Widget card(String id, String name, AppPalette? palette) {
      final selected = settings.themeId == id;
      return Semantics(
        button: true,
        selected: selected,
        label: context.tr('{name} theme', {'name': context.tr(name)}),
        child: InkWell(
          borderRadius: BorderRadius.circular(Rad.lg),
          onTap: () => ref
              .read(settingsProvider.notifier)
              .update((s) => s.copyWith(themeId: id)),
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 164,
            padding: const EdgeInsets.all(Sp.sm),
            decoration: BoxDecoration(
              color: selected ? p.accent.withValues(alpha: .06) : null,
              borderRadius: BorderRadius.circular(Rad.lg),
              border: Border.all(
                color: selected ? p.accent : p.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Rad.md),
                  child: SizedBox(
                    height: 76,
                    child: palette == null
                        // "System" previews both variants, split diagonally.
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              _ThemePreview(Palettes.light),
                              ClipPath(
                                clipper: _DiagonalClipper(),
                                child: _ThemePreview(Palettes.dark),
                              ),
                            ],
                          )
                        : _ThemePreview(palette),
                  ),
                ),
                const SizedBox(height: Sp.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? p.text : p.textMuted,
                          fontWeight: FontWeight.w600,
                          fontSize: Fs.small,
                        ),
                      ),
                    ),
                    if (selected)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: p.accent,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(context.tr('Appearance')),
        _Labeled(
          context.tr('Language'),
          SizedBox(
            width: 260,
            child: _SettingsDropdown<String>(
              value: settings.language,
              items: {
                'system': context.tr('System'),
                ...AppStrings.languageNames,
              },
              onChanged: (value) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(language: value)),
            ),
          ),
        ),
        _Labeled(
          context.tr('Interface size — {n}%', {
            'n': (settings.uiScale * 100).round(),
          }),
          Row(
            children: [
              Expanded(
                child: Slider(
                  min: .8,
                  max: 1.5,
                  divisions: 14,
                  value: settings.uiScale.clamp(.8, 1.5),
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .update((s) => s.copyWith(uiScale: v)),
                ),
              ),
              TextButton(
                onPressed: settings.uiScale == 1
                    ? null
                    : () => ref
                          .read(settingsProvider.notifier)
                          .update((s) => s.copyWith(uiScale: 1)),
                child: Text(context.tr('Reset')),
              ),
            ],
          ),
          help: context.tr(
            'Scales the whole interface, including icons and spacing. Shortcuts: Ctrl+= and Ctrl+-. Your system text size is applied as well.',
          ),
        ),
        const SizedBox(height: Sp.sm),
        _Labeled(
          context.tr('Theme'),
          Wrap(
            spacing: Sp.md,
            runSpacing: Sp.md,
            children: [
              card('system', context.tr('System'), null),
              for (final pal in Palettes.all) card(pal.id, pal.name, pal),
            ],
          ),
          help: context.tr(
            'Pick a theme. "System" follows your OS light/dark setting.',
          ),
        ),
      ],
    );
  }
}

/// A miniature of the app (sidebar, note list, editor) drawn in [palette],
/// so theme cards show how the theme will actually look.
class _ThemePreview extends StatelessWidget {
  const _ThemePreview(this.palette);
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final pal = palette;
    Widget line(Color color, double width, {double height = 4}) => Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(Rad.pill),
      ),
    );
    final backdrop = pal.isGlass
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: pal.isDark
                ? const [Color(0xFF29333D), Color(0xFF17232E)]
                : const [Color(0xFFDCECF5), Color(0xFFC2D4E8)],
          )
        : null;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: backdrop,
        color: backdrop == null ? pal.editorBg : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 30,
            color: pal.sidebarBg,
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(pal.accent, 16),
                line(pal.textFaint.withValues(alpha: .6), 18),
                line(pal.textFaint.withValues(alpha: .6), 14),
                line(pal.textFaint.withValues(alpha: .6), 17),
              ],
            ),
          ),
          Container(
            width: 42,
            color: pal.listBg,
            padding: const EdgeInsets.fromLTRB(5, 8, 5, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 18,
                  margin: const EdgeInsets.only(bottom: 5),
                  decoration: BoxDecoration(
                    color: pal.selection,
                    borderRadius: BorderRadius.circular(Rad.xs),
                  ),
                ),
                line(pal.text.withValues(alpha: .55), 26),
                line(pal.textFaint.withValues(alpha: .5), 30),
                line(pal.text.withValues(alpha: .55), 22),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: pal.isGlass ? null : pal.editorBg,
              padding: const EdgeInsets.fromLTRB(7, 9, 6, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  line(pal.text, 34, height: 6),
                  line(pal.textMuted.withValues(alpha: .6), 48),
                  line(pal.textMuted.withValues(alpha: .6), 40),
                  Row(
                    children: [
                      line(pal.synKeyword, 12),
                      const SizedBox(width: 3),
                      line(pal.synString, 18),
                    ],
                  ),
                  const Spacer(),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      width: 20,
                      height: 9,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: pal.accent,
                        borderRadius: BorderRadius.circular(Rad.xs),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..moveTo(size.width * .62, 0)
    ..lineTo(size.width, 0)
    ..lineTo(size.width, size.height)
    ..lineTo(size.width * .38, size.height)
    ..close();

  @override
  bool shouldReclip(_DiagonalClipper oldClipper) => false;
}

/// Compact filled dropdown shared by settings pages, so every selector has
/// the same size, fill and border as the text fields around it.
class _SettingsDropdown<T> extends StatelessWidget {
  const _SettingsDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isDense: true,
      dropdownColor: p.surface.withValues(alpha: 1),
      borderRadius: BorderRadius.circular(Rad.md),
      elevation: 4,
      icon: Icon(Icons.expand_more_rounded, size: 18, color: p.textMuted),
      style: TextStyle(
        fontFamily: AppTheme.uiFont,
        color: p.text,
        fontSize: Fs.body,
        fontWeight: FontWeight.w500,
      ),
      decoration: const InputDecoration(
        contentPadding: EdgeInsets.symmetric(
          horizontal: Sp.md,
          vertical: Sp.sm + 2,
        ),
      ),
      items: [
        for (final e in items.entries)
          DropdownMenuItem(value: e.key, child: Text(e.value)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

// ------------------------------------------------------------------- editor

class _EditorTab extends ConsumerWidget {
  const _EditorTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(context.tr('Editor')),
        _Labeled(
          context.tr('Font size — {n} px', {'n': s.editorFontSize.round()}),
          Slider(
            min: 11,
            max: 22,
            divisions: 11,
            value: s.editorFontSize.clamp(11, 22),
            onChanged: (v) => n.update((x) => x.copyWith(editorFontSize: v)),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Line numbers')),
          value: s.lineNumbers,
          onChanged: (v) => n.update((x) => x.copyWith(lineNumbers: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Markdown suggestions')),
          subtitle: Text(
            context.tr(
              'Tab accepts, Esc dismisses. Ctrl+Space shows alternatives. Works offline.',
            ),
          ),
          value: s.markdownSuggestions,
          onChanged: (v) => n.update((x) => x.copyWith(markdownSuggestions: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(context.tr('Task reminders as system notifications')),
          subtitle: Text(
            context.tr(
              'Reminders arrive even when Markbit is minimised or closed. When off, they appear inside the app while it is open.',
            ),
          ),
          value: s.systemNotifications,
          onChanged: (v) => n.update((x) => x.copyWith(systemNotifications: v)),
        ),
        const SizedBox(height: Sp.md),
        _Labeled(
          context.tr('Default view for notes'),
          SegmentedButton<ViewMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ViewMode.edit,
                label: Text(context.tr('Editor')),
              ),
              ButtonSegment(
                value: ViewMode.split,
                label: Text(context.tr('Split')),
              ),
              ButtonSegment(
                value: ViewMode.preview,
                label: Text(context.tr('Preview')),
              ),
            ],
            selected: {s.defaultViewMode},
            onSelectionChanged: (v) {
              n.update((x) => x.copyWith(defaultViewMode: v.first));
              ref.read(viewModeProvider.notifier).set(v.first);
            },
          ),
        ),
        _Labeled(
          context.tr('Sort notes by'),
          Row(
            children: [
              SizedBox(
                width: 220,
                child: _SettingsDropdown<SortField>(
                  value: s.sortField,
                  items: {
                    SortField.updated: context.tr('Last updated'),
                    SortField.created: context.tr('Date created'),
                    SortField.title: context.tr('Title'),
                  },
                  onChanged: (v) => n.update((x) => x.copyWith(sortField: v)),
                ),
              ),
              const SizedBox(width: Sp.md),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                    label: Text(context.tr('Ascending')),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                    label: Text(context.tr('Descending')),
                  ),
                ],
                selected: {s.sortAscending},
                onSelectionChanged: (v) =>
                    n.update((x) => x.copyWith(sortAscending: v.first)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------- ai

class _AiTab extends ConsumerStatefulWidget {
  const _AiTab();

  @override
  ConsumerState<_AiTab> createState() => _AiTabState();
}

class _AiTabState extends ConsumerState<_AiTab> {
  late final TextEditingController _url;
  late final TextEditingController _model;
  late final TextEditingController _key;
  late final TextEditingController _prompt;
  bool _showKey = false;
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  // OpenAI-compatible chat endpoints verified against provider documentation.
  static const _presets = <(String, String)>[
    ('OpenAI', 'https://api.openai.com/v1'),
    ('OpenRouter', 'https://openrouter.ai/api/v1'),
    ('Groq', 'https://api.groq.com/openai/v1'),
    ('Gemini', 'https://generativelanguage.googleapis.com/v1beta/openai'),
    ('DeepSeek', 'https://api.deepseek.com/v1'),
    ('Mistral', 'https://api.mistral.ai/v1'),
    ('xAI', 'https://api.x.ai/v1'),
    ('Together AI', 'https://api.together.xyz/v1'),
    ('Fireworks', 'https://api.fireworks.ai/inference/v1'),
    ('NVIDIA NIM', 'https://integrate.api.nvidia.com/v1'),
    ('Ollama', 'http://localhost:11434/v1'),
    ('Ollama Cloud', 'https://ollama.com/v1'),
    ('LM Studio', 'http://localhost:1234/v1'),
  ];
  bool _loadingModels = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _url = TextEditingController(text: s.aiBaseUrl);
    _model = TextEditingController(text: s.aiModel);
    _key = TextEditingController(
      text: ref.read(settingsStoreProvider).aiApiKeyFor(s.aiBaseUrl),
    );
    _prompt = TextEditingController(text: s.aiSystemPrompt);
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _switchEndpoint(String url) {
    final store = ref.read(settingsStoreProvider);
    final old = ref.read(settingsProvider);
    if (old.aiBaseUrl != url) {
      final oldModel = _model.text;
      ref
          .read(persistenceProvider)
          .write(
            'ai-model:${old.aiBaseUrl}',
            () => store.setAiModelFor(old.aiBaseUrl, oldModel),
          );
    }
    _key.text = store.aiApiKeyFor(url);
    _showKey = false;
    _testResult = null;
    _model.text = store.aiModelFor(url);
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(aiBaseUrl: url, aiModel: _model.text));
    ref.invalidate(aiModelsProvider);
    setState(() {});
  }

  static bool _sameEndpoint(String a, String b) {
    String norm(String v) => v.trim().replaceFirst(RegExp(r'/+$'), '');
    return norm(a).toLowerCase() == norm(b).toLowerCase();
  }

  void _apply(String url) {
    _url.text = url;
    _switchEndpoint(url);
  }

  Future<void> _chooseModel() async {
    final url = _url.text.trim();
    setState(() => _loadingModels = true);
    try {
      final models = await AiClient(
        baseUrl: url,
        model: _model.text,
        apiKey: _key.text.trim(),
      ).models();
      if (!mounted || _url.text.trim() != url) return;
      var query = '';
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AppDialog(
            icon: Icons.auto_awesome_outlined,
            title: context.tr('Choose model'),
            width: 480,
            height: 540,
            scrollable: false,
            bodyPadding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, Sp.md),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  autofocus: true,
                  onChanged: (v) => update(() => query = v.toLowerCase()),
                  decoration: InputDecoration(
                    hintText: context.tr('Search models'),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: context.palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(height: Sp.sm),
                Expanded(
                  child: ListView(
                    children: [
                      for (final m in models.where(
                        (m) =>
                            '${m.id} ${m.name}'.toLowerCase().contains(query),
                      ))
                        DialogListItem(
                          title: Text(m.name),
                          subtitle: Text(m.id),
                          selected: m.id == _model.text,
                          onTap: () => Navigator.pop(context, m.id),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            actions: const [DialogCancelButton()],
          ),
        ),
      );
      if (chosen != null && mounted && _url.text.trim() == url) {
        _model.text = chosen;
        _saveModel(chosen);
      }
    } catch (e) {
      if (mounted && _url.text.trim() == url) {
        setState(() {
          _testOk = false;
          _testResult = context.tr(
            'Could not load models. You can enter a model ID below.',
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  void _saveModel(String value) {
    final store = ref.read(settingsStoreProvider);
    final url = _url.text.trim();
    ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(aiModel: value.trim()));
    ref
        .read(persistenceProvider)
        .write('ai-model:$url', () => store.setAiModelFor(url, value.trim()));
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final client = AiClient(
      baseUrl: _url.text,
      model: _model.text,
      apiKey: _key.text.trim(),
    );
    try {
      final buf = StringBuffer();
      await for (final d in client.streamChat(const [
        ChatMessage(ChatRole.user, 'Reply with the single word: OK'),
      ])) {
        buf.write(d);
        if (buf.length > 40) break;
      }
      _testOk = true;
      _testResult = context.tr('Connected. Model replied: {reply}', {
        'reply': buf.toString().trim(),
      });
    } catch (e) {
      _testOk = false;
      _testResult = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = ref.read(settingsProvider.notifier);
    final store = ref.read(settingsStoreProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          context.tr('AI assistant'),
          context.tr(
            'Connect any OpenAI-compatible API. Your key is stored on this device and only sent to the URL below.',
          ),
        ),
        _Labeled(
          context.tr('Provider presets'),
          Wrap(
            spacing: Sp.sm,
            runSpacing: Sp.sm,
            children: [
              for (final pr in _presets)
                ChoiceChip(
                  label: Text(pr.$1),
                  selected: _sameEndpoint(_url.text, pr.$2),
                  onSelected: (_) => _apply(pr.$2),
                ),
            ],
          ),
        ),
        _Labeled(
          context.tr('API base URL'),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            onChanged: (v) => _switchEndpoint(v.trim()),
          ),
          help: context.tr('Requests go to {base URL}/chat/completions.'),
        ),
        _Labeled(
          context.tr('Model'),
          TextField(
            controller: _model,
            onChanged: _saveModel,
            decoration: InputDecoration(
              hintText: context.tr('Choose a current model or enter its ID'),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _loadingModels ? null : _chooseModel,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(
              context.tr(
                _loadingModels ? 'Loading models...' : 'Fetch current models',
              ),
            ),
          ),
        ),
        _Labeled(
          context.tr('API key'),
          TextField(
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) => ref
                .read(persistenceProvider)
                .write(
                  'ai-key:${_url.text.trim()}',
                  (() {
                    final endpoint = _url.text.trim();
                    final value = v.trim();
                    return () async {
                      await store.setAiApiKey(value, baseUrl: endpoint);
                      if (mounted) ref.invalidate(aiModelsProvider);
                    };
                  })(),
                ),
            decoration: InputDecoration(
              hintText: context.tr('Leave empty for local models'),
              suffixIcon: IconButton(
                tooltip: _showKey
                    ? context.tr('Hide key')
                    : context.tr('Show key'),
                icon: Icon(
                  _showKey
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _showKey = !_showKey),
              ),
            ),
          ),
        ),
        Text(
          context.tr(
            'Each provider has its own key. Custom API URLs are supported. Model lists are fetched from the selected provider.',
          ),
          style: TextStyle(color: p.textMuted, fontSize: Fs.small),
        ),
        const SizedBox(height: Sp.md),
        _Labeled(
          context.tr('System prompt'),
          TextField(
            controller: _prompt,
            minLines: 3,
            maxLines: 6,
            onChanged: (v) => n.update((s) => s.copyWith(aiSystemPrompt: v)),
          ),
        ),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.bolt_rounded, size: 18),
              label: Text(context.tr('Test connection')),
            ),
          ],
        ),
        if (_testResult != null)
          Padding(
            padding: const EdgeInsets.only(top: Sp.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _testOk ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 18,
                  color: _testOk ? p.success : p.danger,
                ),
                const SizedBox(width: Sp.sm),
                Expanded(
                  child: SelectableText(
                    _testResult!,
                    style: const TextStyle(fontSize: Fs.small),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- execution

class _ExecutionTab extends ConsumerStatefulWidget {
  const _ExecutionTab();

  @override
  ConsumerState<_ExecutionTab> createState() => _ExecutionTabState();
}

class _ExecutionTabState extends ConsumerState<_ExecutionTab> {
  late final TextEditingController _endpoint;
  late final TextEditingController _key;
  Map<String, String?>? _detected;
  bool _detecting = false;

  @override
  void initState() {
    super.initState();
    _endpoint = TextEditingController(
      text: ref.read(settingsProvider).remoteEndpoint,
    );
    _key = TextEditingController(
      text: ref.read(settingsStoreProvider).remoteExecKey,
    );
  }

  @override
  void dispose() {
    _endpoint.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    setState(() => _detecting = true);
    final local = ref.read(localExecutorProvider)..clearCache();
    final results = <String, String?>{};
    await Future.wait(
      Languages.runnable.where((l) => l.toolchains.isNotEmpty).map((l) async {
        results[l.id] = (await local.detect(l))?.label;
      }),
    );
    if (mounted) {
      setState(() {
        _detected = results;
        _detecting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    final canLocal = PlatformInfo.canRunLocalProcesses;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          context.tr('Code execution'),
          context.tr(
            'Run code blocks and code notes with toolchains installed on this computer, or through a remote Piston-compatible API.',
          ),
        ),
        _Labeled(
          context.tr('Run code using'),
          SegmentedButton<ExecutionMode>(
            showSelectedIcon: false,
            segments: [
              for (final m in ExecutionMode.values)
                ButtonSegment(value: m, label: Text(context.tr(m.label))),
            ],
            selected: {s.executionMode},
            onSelectionChanged: (v) =>
                n.update((x) => x.copyWith(executionMode: v.first)),
          ),
          help: canLocal
              ? context.tr(
                  'Automatic uses local tools when available and falls back to the remote API.',
                )
              : context.tr(
                  'This platform cannot start local compilers, so the remote API is used.',
                ),
        ),
        _Labeled(
          context.tr('Timeout — {n} s', {'n': s.runTimeoutSeconds}),
          Slider(
            min: 5,
            max: 120,
            divisions: 23,
            value: s.runTimeoutSeconds.toDouble().clamp(5, 120),
            onChanged: (v) =>
                n.update((x) => x.copyWith(runTimeoutSeconds: v.round())),
          ),
        ),
        _Labeled(
          context.tr('Remote API endpoint'),
          TextField(
            controller: _endpoint,
            keyboardType: TextInputType.url,
            onChanged: (v) =>
                n.update((x) => x.copyWith(remoteEndpoint: v.trim())),
          ),
          help: context.tr(
            'Piston API base, e.g. https://emkc.org/api/v2/piston or your own self-hosted instance. The public instance may require authorization — self-hosting is recommended.',
          ),
        ),
        _Labeled(
          context.tr('Remote API key / token (optional)'),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (v) {
              final store = ref.read(settingsStoreProvider);
              ref
                  .read(persistenceProvider)
                  .write('remote-key', () => store.setRemoteExecKey(v.trim()));
            },
          ),
          help: context.tr('Sent as the Authorization header.'),
        ),
        if (canLocal) ...[
          SectionTitle(context.tr('Local toolchains')),
          OutlinedButton.icon(
            onPressed: _detecting ? null : _detect,
            icon: _detecting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search_rounded, size: 18),
            label: Text(
              _detected == null
                  ? context.tr('Detect installed toolchains')
                  : context.tr('Detect again'),
            ),
          ),
          if (_detected != null)
            Padding(
              padding: const EdgeInsets.only(top: Sp.md),
              child: Wrap(
                spacing: Sp.sm,
                runSpacing: Sp.sm,
                children: [
                  for (final l in Languages.runnable.where(
                    (l) => l.toolchains.isNotEmpty,
                  ))
                    Chip(
                      avatar: Icon(
                        _detected![l.id] != null
                            ? Icons.check_circle_rounded
                            : Icons.remove_circle_outline_rounded,
                        size: 16,
                        color: _detected![l.id] != null
                            ? p.success
                            : p.textFaint,
                      ),
                      label: Text(
                        _detected![l.id] == null
                            ? context.tr('{name}: not found', {'name': l.name})
                            : '${l.name}: ${_detected![l.id]}',
                      ),
                      backgroundColor: p.codeBg,
                      side: BorderSide(color: p.border),
                      labelStyle: const TextStyle(fontSize: Fs.caption),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------------- data

class _DataTab extends ConsumerStatefulWidget {
  const _DataTab();

  @override
  ConsumerState<_DataTab> createState() => _DataTabState();
}

class _DataTabState extends ConsumerState<_DataTab> {
  bool _busy = false;

  Future<void> _backup() async {
    setState(() => _busy = true);
    try {
      await ref.read(persistenceProvider).flush();
      final raw = await BackupService.encode(
        ref.read(libraryProvider),
        ref.read(settingsProvider),
        ref.read(chatStoreProvider),
        ref.read(sharedPrefsProvider),
        history: ref.read(libraryRepositoryProvider) is FileLibraryRepository
            ? (ref.read(libraryRepositoryProvider) as FileLibraryRepository)
                  .history
            : null,
      );
      final bytes = Uint8List.fromList(utf8.encode(raw));
      final path = await FilePicker.saveFile(
        dialogTitle: trs('Full backup'),
        fileName:
            'Markbit-${DateTime.now().toIso8601String().substring(0, 10)}.markbit',
        bytes: bytes,
      );
      if (path != null && PlatformInfo.isDesktop) {
        final tmp = File('$path.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(path);
      }
      if (path != null && mounted) {
        showToast(context, context.tr('Backup completed.'));
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr('Export failed: {error}', {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['markbit'],
    );
    if (picked == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final file = picked.files.single;
      if (file.size > 512 * 1024 * 1024) {
        throw const FormatException('Backup exceeds 512 MB');
      }
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      final current = ref.read(libraryProvider);
      final restored = BackupService.decode(
        utf8.decode(bytes),
        current.inbox.id,
      );
      if (!mounted) return;
      final confirmed = await confirmAction(
        context,
        title: context.tr('Restore backup?'),
        message: context.tr(
          'Notes and chats will be added. Existing notes and API keys are kept. Settings will be restored.',
        ),
        confirmLabel: context.tr('Restore'),
      );
      if (!confirmed || !mounted) return;
      await ref.read(persistenceProvider).flush();
      final repository = ref.read(libraryRepositoryProvider);
      final snapshot = restored.library;
      final notes = <Note>[];
      for (final note in snapshot.notes) {
        notes.add(
          repository is FileLibraryRepository
              ? note.copyWith(
                  coverImage: await repository.storeCover(note.coverImage),
                )
              : note,
        );
      }
      if (!mounted) return;
      ref
          .read(libraryProvider.notifier)
          .importSnapshot(
            LibrarySnapshot(
              notes: notes,
              notebooks: snapshot.notebooks,
              tags: snapshot.tags,
              templates: snapshot.templates,
              isFresh: false,
            ),
          );
      final store = ref.read(chatStoreProvider);
      if (repository is FileLibraryRepository) {
        for (final entry in restored.history.entries) {
          await repository.history.restore(entry.key, entry.value);
        }
      }
      final persistence = ref.read(persistenceProvider);
      for (final entry in restored.chats.entries) {
        await persistence.write(
          'chat:${entry.key}',
          () => store.write(entry.key, entry.value),
        );
      }
      ref.read(settingsProvider.notifier).update((_) => restored.settings);
      final prefs = ref.read(sharedPrefsProvider);
      for (final entry in restored.preferences.entries) {
        await persistence.write('preference:${entry.key}', () async {
          final value = entry.value;
          final success = switch (value) {
            bool v => await prefs.setBool(entry.key, v),
            int v => await prefs.setInt(entry.key, v),
            double v => await prefs.setDouble(entry.key, v),
            String v => await prefs.setString(entry.key, v),
            _ => false,
          };
          if (!success) {
            throw const FormatException('Invalid backup preference');
          }
        });
      }
      ref.invalidate(aiPanelWidthProvider);
      await persistence.flush();
      ref.invalidate(collectionsProvider);
      if (mounted) showToast(context, context.tr('Backup restored.'));
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr('Import failed: {error}', {'error': '$e'}),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    setState(() => _busy = true);
    try {
      await ref.read(libraryProvider.notifier).reloadFromDisk();
      final chats = ref.read(chatStoreProvider);
      if (chats is FileChatStore) {
        await chats.migrate(ref.read(sharedPrefsProvider));
        final repository = ref.read(libraryRepositoryProvider);
        if (repository is FileLibraryRepository) {
          for (final warning in chats.migrationWarnings) {
            repository.reportRecoveryIssue(warning);
          }
        }
        final open = ref.read(openNoteIdProvider);
        if (open != null) ref.invalidate(aiProvider(open));
      }
    } catch (e) {
      if (mounted) showToast(context, '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export({bool html = false}) async {
    final dir = await FilePicker.getDirectoryPath(
      dialogTitle: context.tr('Export notes to folder'),
    );
    if (dir == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(persistenceProvider).flush();
      final count = await ExportService.exportAll(
        ref.read(libraryProvider),
        dir,
        html: html,
      );
      if (mounted) {
        showToast(context, context.tr('Exported {n} notes', {'n': count}));
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          context.tr('Export failed: {error}', {'error': '$e'}),
        );
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _import() async {
    await showImportSourcePicker(context);
  }

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAllDialog(onBackup: _backup),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final restart = ref.read(appRestartProvider);
    List<String> failed;
    try {
      failed = await deleteAllData(ref);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(
          context,
          context.tr('Could not delete all data: {error}', {'error': '$e'}),
        );
      }
      return;
    }
    if (failed.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          icon: Icons.warning_amber_rounded,
          iconColor: context.palette.warning,
          title: context.tr('Some files could not be deleted'),
          subtitle: context.tr(
            'Close other programs using them and delete them by hand. Markbit will restart now.',
          ),
          width: 520,
          content: SelectableText(failed.join('\n')),
          actions: const [DialogCancelButton(label: 'OK')],
        ),
      );
    }
    // The in-memory library must never be saved again: start over.
    await restart();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final repo = ref.watch(libraryRepositoryProvider);
    final lib = ref.watch(libraryProvider);
    final trashed = lib.notes.values.where((n) => n.trashed).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(
          context.tr('Data'),
          context.tr('Notes are stored as plain JSON files on this device.'),
        ),
        _Labeled(
          context.tr('Library location'),
          Container(
            padding: const EdgeInsets.fromLTRB(Sp.md, Sp.xs, Sp.xs, Sp.xs),
            decoration: BoxDecoration(
              color: p.codeBg,
              borderRadius: BorderRadius.circular(Rad.md),
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    repo.location,
                    maxLines: 1,
                    style: TextStyle(color: p.textMuted, fontSize: Fs.small),
                  ),
                ),
                AppIconButton(
                  icon: Icons.copy_rounded,
                  tooltip: context.tr('Copy path'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: repo.location));
                    if (context.mounted) {
                      showToast(context, context.tr('Copied to clipboard'));
                    }
                  },
                ),
                if (PlatformInfo.canRunLocalProcesses)
                  AppIconButton(
                    icon: Icons.folder_open_outlined,
                    tooltip: context.tr('Open folder'),
                    onPressed: () => launchUrl(Uri.file(repo.location)),
                  ),
              ],
            ),
          ),
        ),
        _Labeled(
          context.tr('Full backup'),
          Wrap(
            spacing: Sp.md,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _backup,
                icon: const Icon(Icons.backup_outlined),
                label: Text(context.tr('Create backup')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(context.tr('Restore backup')),
              ),
            ],
          ),
          help: context.tr(
            'Includes notes, covers, notebooks, tags, templates, chats and settings. API keys are excluded.',
          ),
        ),
        ListenableBuilder(
          listenable: ref.watch(autoBackupProvider),
          builder: (context, _) {
            final backup = ref.read(autoBackupProvider);
            return _Labeled(
              context.tr('Automatic backup'),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      context.tr('Daily backup'),
                      style: const TextStyle(fontSize: Fs.body),
                    ),
                    value: backup.enabled,
                    onChanged: backup.busy
                        ? null
                        : (value) async {
                            try {
                              if (value && backup.folder == null) {
                                final folder =
                                    await FilePicker.getDirectoryPath(
                                      dialogTitle: context.tr('Backup folder'),
                                    );
                                if (folder == null) return;
                                await backup.configure(folder: folder);
                              }
                              await backup.configure(enabled: value);
                            } catch (e) {
                              if (context.mounted) showToast(context, '$e');
                            }
                          },
                  ),
                  Wrap(
                    spacing: Sp.sm,
                    runSpacing: Sp.sm,
                    children: [
                      OutlinedButton.icon(
                        onPressed: backup.busy
                            ? null
                            : () async {
                                final folder =
                                    await FilePicker.getDirectoryPath(
                                      dialogTitle: context.tr('Backup folder'),
                                    );
                                if (folder != null) {
                                  try {
                                    await backup.configure(folder: folder);
                                  } catch (e) {
                                    if (context.mounted) {
                                      showToast(context, '$e');
                                    }
                                  }
                                }
                              },
                        icon: const Icon(Icons.folder_outlined),
                        label: Text(context.tr('Choose backup folder')),
                      ),
                      if (backup.enabled)
                        OutlinedButton(
                          onPressed: backup.busy
                              ? null
                              : () => backup.check(force: true),
                          child: Text(context.tr('Back up now')),
                        ),
                    ],
                  ),
                  if (backup.folder != null)
                    Padding(
                      padding: const EdgeInsets.only(top: Sp.sm),
                      child: SelectableText(
                        backup.folder!,
                        style: TextStyle(
                          color: p.textMuted,
                          fontSize: Fs.small,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(child: Text(context.tr('Backups to keep'))),
                      IconButton(
                        onPressed: backup.keep > 1 && !backup.busy
                            ? () => backup.configure(keep: backup.keep - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${backup.keep}'),
                      IconButton(
                        onPressed: backup.keep < 30 && !backup.busy
                            ? () => backup.configure(keep: backup.keep + 1)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  if (backup.last != null)
                    Text(
                      context.tr('Last backup: {time}', {
                        'time':
                            '${MaterialLocalizations.of(context).formatFullDate(backup.last!)} ${TimeOfDay.fromDateTime(backup.last!).format(context)}',
                      }),
                    ),
                  if (backup.error != null)
                    Text(backup.error!, style: TextStyle(color: p.danger)),
                ],
              ),
              help: context.tr(
                'Runs while Markbit is open. Missed backups run at the next launch. Only automatic Markbit backups are removed.',
              ),
            );
          },
        ),
        if (repo is FileLibraryRepository)
          ValueListenableBuilder<List<String>>(
            valueListenable: repo.loadWarnings,
            builder: (context, warnings, _) => warnings.isEmpty
                ? const SizedBox.shrink()
                : _Labeled(
                    context.tr('Data recovery'),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final warning in warnings)
                          SelectableText(
                            warning,
                            style: TextStyle(color: p.danger),
                          ),
                        OutlinedButton(
                          onPressed: _busy ? null : _recover,
                          child: Text(context.tr('Retry recovery')),
                        ),
                      ],
                    ),
                    help: context.tr(
                      'Original damaged files are preserved. Valid backup files are recovered automatically.',
                    ),
                  ),
          ),
        _Labeled(
          context.tr('Markdown export / import'),
          Wrap(
            spacing: Sp.md,
            runSpacing: Sp.md,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: Text(context.tr('Export all notes\u2026')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _export(html: true),
                icon: const Icon(Icons.html_outlined, size: 18),
                label: Text(context.tr('Export all as web pages…')),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(context.tr('Import\u2026')),
              ),
            ],
          ),
          help: context.tr(
            'Export creates one .md (or source) file per note, organised by notebook. Import reads .md, .txt and source files, using sub-folders as notebooks.',
          ),
        ),
        _Labeled(
          context.tr('Versions kept per note'),
          SizedBox(
            width: 260,
            child: _SettingsDropdown<int>(
              value: ref.watch(settingsProvider.select((s) => s.historyLimit)),
              items: {
                for (final n in const [25, 50, 100, 250, 500])
                  n: context.tr('{n} versions', {'n': n}),
              },
              onChanged: (n) => ref
                  .read(settingsProvider.notifier)
                  .update((s) => s.copyWith(historyLimit: n)),
            ),
          ),
          help: context.tr(
            'A version is saved at most once a minute while you edit. Older versions beyond the limit are removed.',
          ),
        ),
        _Labeled(
          context.tr('Delete notes in the trash automatically'),
          SizedBox(
            width: 260,
            child: _SettingsDropdown<int>(
              value: ref.watch(
                settingsProvider.select((s) => s.trashRetentionDays),
              ),
              items: {
                7: context.tr('After {n} days', {'n': 7}),
                14: context.tr('After {n} days', {'n': 14}),
                30: context.tr('After {n} days', {'n': 30}),
                60: context.tr('After {n} days', {'n': 60}),
                90: context.tr('After {n} days', {'n': 90}),
                0: context.tr('Never'),
              },
              onChanged: (days) {
                ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(trashRetentionDays: days));
                ref.read(libraryProvider.notifier).purgeExpiredTrash(days);
              },
            ),
          ),
          help: context.tr(
            'Counted from the day a note is moved to the trash. Restored notes are kept.',
          ),
        ),
        _Labeled(
          context.tr('Trash'),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: p.danger),
            onPressed: trashed == 0
                ? null
                : () async {
                    final ok = await confirmAction(
                      context,
                      title: context.tr('Empty trash?'),
                      message: context.tr(
                        '{n} note(s) will be deleted permanently.',
                        {'n': trashed},
                      ),
                      confirmLabel: context.tr('Empty trash'),
                    );
                    if (ok) ref.read(libraryProvider.notifier).emptyTrash();
                  },
            icon: const Icon(Icons.delete_forever_outlined, size: 18),
            label: Text(context.tr('Empty trash ({n})', {'n': trashed})),
          ),
        ),
        // Only the main window may reset the library.
        if (ref.watch(noteWindowProvider) == null)
          _Labeled(
            context.tr('Delete all data'),
            FilledButton.icon(
              key: const ValueKey('delete-all-data'),
              style: FilledButton.styleFrom(
                backgroundColor: p.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : _deleteAll,
              icon: const Icon(Icons.warning_amber_rounded, size: 18),
              label: Text(context.tr('Delete all data\u2026')),
            ),
            help: context.tr(
              'Removes all notes, notebooks, tags, templates, versions, AI chats, settings and API keys from this device, then restarts Markbit. Backups saved in other folders are kept.',
            ),
          ),
      ],
    );
  }
}

/// Explains what "Delete all data" removes and asks for an explicit
/// acknowledgement. Pops `true` to go ahead.
class _DeleteAllDialog extends StatefulWidget {
  const _DeleteAllDialog({required this.onBackup});
  final Future<void> Function() onBackup;

  @override
  State<_DeleteAllDialog> createState() => _DeleteAllDialogState();
}

class _DeleteAllDialogState extends State<_DeleteAllDialog> {
  bool _understood = false;
  bool _backingUp = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return AppDialog(
      icon: Icons.warning_amber_rounded,
      iconColor: p.danger,
      title: context.tr('Delete all data?'),
      subtitle: context.tr('This cannot be undone.'),
      width: 520,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('The following will be removed from this device:'),
            style: TextStyle(color: p.text, fontSize: Fs.body),
          ),
          const SizedBox(height: Sp.sm),
          for (final item in const [
            'All notes, including the trash',
            'Notebooks, tags and templates',
            'Note versions, covers and images',
            'AI conversations',
            'Settings, shortcuts and saved API keys',
            'Scheduled task reminders',
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Sp.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.remove_rounded, size: 16, color: p.danger),
                  const SizedBox(width: Sp.sm),
                  Expanded(
                    child: Text(
                      context.tr(item),
                      style: TextStyle(color: p.textMuted, fontSize: Fs.small),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Sp.md),
          OutlinedButton.icon(
            onPressed: _backingUp
                ? null
                : () async {
                    setState(() => _backingUp = true);
                    await widget.onBackup();
                    if (mounted) setState(() => _backingUp = false);
                  },
            icon: const Icon(Icons.backup_outlined, size: 18),
            label: Text(context.tr('Create backup first')),
          ),
          const SizedBox(height: Sp.sm),
          CheckboxListTile(
            key: const ValueKey('delete-all-understood'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            value: _understood,
            onChanged: (v) => setState(() => _understood = v ?? false),
            title: Text(
              context.tr(
                'I understand that my data will be deleted permanently.',
              ),
              style: TextStyle(color: p.text, fontSize: Fs.small),
            ),
          ),
        ],
      ),
      actions: [
        const DialogCancelButton(result: false),
        FilledButton(
          key: const ValueKey('delete-all-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: p.danger,
            foregroundColor: Colors.white,
          ),
          onPressed: _understood && !_backingUp
              ? () => Navigator.pop(context, true)
              : null,
          child: Text(context.tr('Delete everything')),
        ),
      ],
    );
  }
}
