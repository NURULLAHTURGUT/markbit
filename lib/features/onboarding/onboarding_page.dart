import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/onboarding.dart';
import '../../application/providers.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/theme/app_palette.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/theme_preview.dart';

/// Folder holding the tour screenshots (see assets/onboarding/README.md).
const onboardingAssets = 'assets/onboarding';

/// One feature of the tour: a screenshot with a title and a short text.
class TourSlide {
  const TourSlide(this.image, this.icon, this.title, this.text);
  final String image;
  final IconData icon;
  final String title;
  final String text;
}

const tourSlides = <TourSlide>[
  TourSlide(
    'tour-editor.gif',
    Icons.edit_note_rounded,
    'Write in Markdown',
    'Edit on the left and see the result on the right: math, diagrams, tables, charts and images, updated as you type.',
  ),
  TourSlide(
    'tour-run-code.png',
    Icons.play_circle_outline_rounded,
    'Run code where you write it',
    'Press Run on any code block — Python, JavaScript, Go, Rust, SQL and more. The output appears right below your note.',
  ),
  TourSlide(
    'tour-organize.png',
    Icons.dashboard_outlined,
    'Keep everything organised',
    'Notebooks, tags, statuses, pinned and starred notes, covers and wiki links keep a growing library easy to browse.',
  ),
  TourSlide(
    'tour-tasks.png',
    Icons.event_available_outlined,
    'Plan with tasks and reminders',
    'Checkboxes become tasks with due dates, priorities and repeats. Reminders arrive even when Markbit is closed.',
  ),
  TourSlide(
    'tour-ai.png',
    Icons.auto_awesome_outlined,
    'Ask the AI assistant',
    'Ask about the note you are editing, find bugs or draft text. Suggested changes are only written after you approve them.',
  ),
  TourSlide(
    'tour-search.png',
    Icons.manage_search_rounded,
    'Find anything in seconds',
    'Press Ctrl+K to search every note and run any command. Filters like tag:, lang: or has:tasks narrow things down.',
  ),
];

enum _Step { welcome, language, theme, tour, preferences, done }

/// The first-launch welcome: language, theme, a short feature tour with
/// screenshots, a few preferences, then the app. Every choice applies at
/// once and can be changed later in Settings.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  // welcome, language, theme, 6 tour slides, preferences, done.
  static final _pages = <(_Step, int)>[
    (_Step.welcome, 0),
    (_Step.language, 0),
    (_Step.theme, 0),
    for (var i = 0; i < tourSlides.length; i++) (_Step.tour, i),
    (_Step.preferences, 0),
    (_Step.done, 0),
  ];
  int _index = 0;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    // Shown once: closing the app halfway does not bring it back.
    ref.read(onboardingPendingProvider.notifier).markSeen();
  }

  void _go(int index) {
    if (index < 0 || index >= _pages.length) return;
    setState(() {
      _forward = index > _index;
      _index = index;
    });
  }

  void _next() => _index == _pages.length - 1 ? _finish() : _go(_index + 1);

  void _finish() => ref.read(onboardingPendingProvider.notifier).finish();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (step, slide) = _pages[_index];
    final last = _index == _pages.length - 1;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final body = switch (step) {
      _Step.welcome => const _Welcome(),
      _Step.language => const _LanguageStep(),
      _Step.theme => const _ThemeStep(),
      _Step.tour => _TourStep(slide: tourSlides[slide]),
      _Step.preferences => const _PreferencesStep(),
      _Step.done => const _DoneStep(),
    };

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _next,
        const SingleActivator(LogicalKeyboardKey.enter): _next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _go(_index - 1),
        const SingleActivator(LogicalKeyboardKey.escape): _finish,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: p.editorBg,
          body: SafeArea(
            child: Column(
              children: [
                // Skip is always one click away (fixed height so the
                // content does not jump on the last step).
                Padding(
                  padding: const EdgeInsets.fromLTRB(Sp.lg, Sp.md, Sp.lg, 0),
                  child: SizedBox(
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: last
                          ? null
                          : TextButton(
                              key: const ValueKey('onboarding-skip'),
                              onPressed: _finish,
                              child: Text(context.tr('Skip')),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Sp.xl,
                        vertical: Sp.lg,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 860),
                        child: AnimatedSwitcher(
                          duration: reduceMotion ? Duration.zero : Motion.slow,
                          switchInCurve: Motion.curve,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: Offset(_forward ? .04 : -.04, 0),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey(_index),
                            child: body,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _Footer(
                  index: _index,
                  count: _pages.length,
                  last: last,
                  onBack: _index == 0 ? null : () => _go(_index - 1),
                  onNext: _next,
                  onDot: _go,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.index,
    required this.count,
    required this.last,
    required this.onBack,
    required this.onNext,
    required this.onDot,
  });
  final int index, count;
  final bool last;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final ValueChanged<int> onDot;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.xl, Sp.sm, Sp.xl, Sp.xl),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Align(
              alignment: Alignment.centerLeft,
              child: onBack == null
                  ? null
                  : TextButton.icon(
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(context.tr('Back')),
                    ),
            ),
          ),
          Expanded(
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < count; i++)
                  GestureDetector(
                    onTap: () => onDot(i),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: AnimatedContainer(
                        duration: Motion.normal,
                        curve: Motion.curve,
                        width: i == index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == index
                              ? p.accent
                              : i < index
                              ? p.accent.withValues(alpha: .4)
                              : p.border,
                          borderRadius: BorderRadius.circular(Rad.pill),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(
            width: 180,
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                key: const ValueKey('onboarding-next'),
                onPressed: onNext,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr(
                          last
                              ? 'Start'
                              : index == 0
                              ? 'Get started'
                              : 'Next',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!last) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Large heading and supporting line used by every step.
class _Title extends StatelessWidget {
  const _Title(this.title, this.subtitle);
  final String title, subtitle;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: p.text,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        const SizedBox(height: Sp.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textMuted,
              fontSize: Fs.body,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: .8, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (context, scale, child) =>
              Transform.scale(scale: scale, child: child),
          child: Container(
            padding: const EdgeInsets.all(Sp.lg),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: p.isDark ? .14 : .08),
              shape: BoxShape.circle,
            ),
            child: Image.asset(
              'assets/icon/markbit.png',
              width: 96,
              height: 96,
            ),
          ),
        ),
        const SizedBox(height: Sp.xl),
        _Title(
          context.tr('Welcome to Markbit'),
          context.tr(
            'Markdown notes that run code. Let\'s set things up in a minute and take a quick look at what you can do.',
          ),
        ),
        const SizedBox(height: Sp.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Sp.sm,
          runSpacing: Sp.sm,
          children: [
            for (final (icon, label) in const [
              (Icons.edit_note_rounded, 'Markdown'),
              (Icons.play_arrow_rounded, 'Run code'),
              (Icons.task_alt_rounded, 'Tasks'),
              (Icons.auto_awesome_outlined, 'AI assistant'),
              (Icons.lock_outline_rounded, 'Offline & private'),
            ])
              Chip(
                avatar: Icon(icon, size: 16, color: p.accent),
                label: Text(context.tr(label)),
              ),
          ],
        ),
      ],
    );
  }
}

/// A selectable card used by the language step.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    super.key,
    required this.selected,
    required this.onTap,
    required this.child,
    this.width = 180,
  });
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(Rad.lg),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: width,
          padding: const EdgeInsets.all(Sp.md),
          decoration: BoxDecoration(
            color: selected
                ? p.accent.withValues(alpha: p.isDark ? .14 : .07)
                : p.surface,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(
              color: selected ? p.accent : p.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _LanguageStep extends ConsumerWidget {
  const _LanguageStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final current = ref.watch(settingsProvider.select((s) => s.language));
    final options = {
      'system': context.tr('System language'),
      ...AppStrings.languageNames,
    };
    return Column(
      children: [
        _Title(
          context.tr('Choose your language'),
          context.tr(
            'Markbit will use it everywhere. You can change it any time in Settings.',
          ),
        ),
        const SizedBox(height: Sp.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Sp.md,
          runSpacing: Sp.md,
          children: [
            for (final MapEntry(key: code, value: name) in options.entries)
              _ChoiceCard(
                key: ValueKey('language-$code'),
                selected: current == code,
                onTap: () => ref
                    .read(settingsProvider.notifier)
                    .update((s) => s.copyWith(language: code)),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: p.codeBg,
                        borderRadius: BorderRadius.circular(Rad.md),
                      ),
                      child: code == 'system'
                          ? Icon(
                              Icons.computer_rounded,
                              size: 18,
                              color: p.textMuted,
                            )
                          : Text(
                              code.toUpperCase(),
                              style: TextStyle(
                                color: p.textMuted,
                                fontWeight: FontWeight.w700,
                                fontSize: Fs.small,
                              ),
                            ),
                    ),
                    const SizedBox(width: Sp.md),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: p.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (current == code)
                      Icon(
                        Icons.check_circle_rounded,
                        size: 18,
                        color: p.accent,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ThemeStep extends ConsumerWidget {
  const _ThemeStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final current = ref.watch(settingsProvider.select((s) => s.themeId));
    Widget card(String id, String name, AppPalette? palette) => _ChoiceCard(
      key: ValueKey('theme-$id'),
      width: 184,
      selected: current == id,
      onTap: () => ref
          .read(settingsProvider.notifier)
          .update((s) => s.copyWith(themeId: id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Rad.md),
            child: SizedBox(
              height: 92,
              child: palette == null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        ThemePreview(Palettes.light),
                        ClipPath(
                          clipper: DiagonalClipper(),
                          child: ThemePreview(Palettes.dark),
                        ),
                      ],
                    )
                  : ThemePreview(palette),
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
                    color: p.text,
                    fontWeight: FontWeight.w600,
                    fontSize: Fs.small,
                  ),
                ),
              ),
              if (current == id)
                Icon(Icons.check_circle_rounded, size: 16, color: p.accent),
            ],
          ),
        ],
      ),
    );
    return Column(
      children: [
        _Title(
          context.tr('Pick a look'),
          context.tr(
            'Themes apply instantly. "System" follows your light or dark mode.',
          ),
        ),
        const SizedBox(height: Sp.xl),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: Sp.md,
          runSpacing: Sp.md,
          children: [
            card('system', 'System', null),
            for (final pal in Palettes.all) card(pal.id, pal.name, pal),
          ],
        ),
      ],
    );
  }
}

class _TourStep extends StatelessWidget {
  const _TourStep({required this.slide});
  final TourSlide slide;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Leave room for the title and text below on short windows.
    final imageWidth = (MediaQuery.sizeOf(context).height * .5 * 1.6).clamp(
      320.0,
      860.0,
    );
    return Column(
      children: [
        Container(
          constraints: BoxConstraints(maxWidth: imageWidth),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Rad.xl),
            border: Border.all(color: p.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: p.isDark ? .35 : .10),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: ColoredBox(
              color: p.sidebarBg,
              child: Image.asset(
                '$onboardingAssets/${slide.image}',
                // Show the whole screenshot, whatever its proportions.
                fit: BoxFit.contain,
                // Decode at display size: keeps large GIFs light in memory.
                cacheWidth:
                    (imageWidth * MediaQuery.devicePixelRatioOf(context))
                        .round(),
                // A missing screenshot shows a calm illustration instead.
                errorBuilder: (context, _, _) => _TourPlaceholder(slide.icon),
              ),
            ),
          ),
        ),
        const SizedBox(height: Sp.xl),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(slide.icon, color: p.accent, size: 26),
            const SizedBox(width: Sp.sm),
            Flexible(
              child: Text(
                context.tr(slide.title),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: p.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Sp.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            context.tr(slide.text),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.textMuted,
              fontSize: Fs.body,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }
}

class _TourPlaceholder extends StatelessWidget {
  const _TourPlaceholder(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            p.accent.withValues(alpha: p.isDark ? .22 : .14),
            p.sidebarBg,
          ],
        ),
      ),
      child: Center(
        child: Icon(icon, size: 96, color: p.accent.withValues(alpha: .7)),
      ),
    );
  }
}

class _PreferencesStep extends ConsumerWidget {
  const _PreferencesStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget toggle(
      IconData icon,
      String title,
      String subtitle,
      bool value,
      ValueChanged<bool> onChanged,
    ) => SwitchListTile(
      value: value,
      onChanged: onChanged,
      secondary: Icon(icon, color: p.accent),
      title: Text(
        context.tr(title),
        style: TextStyle(color: p.text, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        context.tr(subtitle),
        style: TextStyle(color: p.textMuted, fontSize: Fs.small),
      ),
    );
    return Column(
      children: [
        _Title(
          context.tr('A few preferences'),
          context.tr(
            'Sensible defaults are already set. Adjust anything you like.',
          ),
        ),
        const SizedBox(height: Sp.xl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          // A Material (not a coloured box) so the switches' ink shows.
          child: Material(
            color: p.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Rad.lg),
              side: BorderSide(color: p.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.sm),
              child: Column(
                children: [
                  toggle(
                    Icons.notifications_active_outlined,
                    'Task reminders as notifications',
                    'Get reminded of due tasks, even when Markbit is closed.',
                    s.systemNotifications,
                    (v) => n.update((x) => x.copyWith(systemNotifications: v)),
                  ),
                  toggle(
                    Icons.lightbulb_outline_rounded,
                    'Markdown suggestions',
                    'Offer completions for lists, tables and code blocks while you type.',
                    s.markdownSuggestions,
                    (v) => n.update((x) => x.copyWith(markdownSuggestions: v)),
                  ),
                  toggle(
                    Icons.format_list_numbered_rounded,
                    'Line numbers',
                    'Show line numbers next to the editor.',
                    s.lineNumbers,
                    (v) => n.update((x) => x.copyWith(lineNumbers: v)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Sp.lg,
                      Sp.sm,
                      Sp.lg,
                      Sp.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.zoom_in_rounded, color: p.accent),
                        const SizedBox(width: Sp.lg),
                        Expanded(
                          child: Text(
                            context.tr('Interface size'),
                            style: TextStyle(
                              color: p.text,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        SegmentedButton<double>(
                          showSelectedIcon: false,
                          segments: [
                            ButtonSegment(
                              value: .9,
                              label: Text(context.tr('Compact')),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(context.tr('Default')),
                            ),
                            ButtonSegment(
                              value: 1.15,
                              label: Text(context.tr('Large')),
                            ),
                          ],
                          selected: {
                            const [.9, 1.0, 1.15].firstWhere(
                              (v) => (v - s.uiScale).abs() < .01,
                              orElse: () => 1.0,
                            ),
                          },
                          onSelectionChanged: (v) =>
                              n.update((x) => x.copyWith(uiScale: v.first)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DoneStep extends StatelessWidget {
  const _DoneStep();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const keys = [
      ('Ctrl+K', 'Search and run any command'),
      ('Ctrl+N', 'New note'),
      ('Ctrl+Enter', 'Run the code block at the cursor'),
      ('Ctrl+J', 'Open the AI assistant'),
    ];
    return Column(
      children: [
        Icon(Icons.celebration_outlined, size: 64, color: p.accent),
        const SizedBox(height: Sp.lg),
        _Title(
          context.tr('You\'re all set'),
          context.tr(
            'Your notes stay on this device. Add an AI provider any time in Settings → AI assistant.',
          ),
        ),
        const SizedBox(height: Sp.xl),
        Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(Sp.lg),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Rad.lg),
            border: Border.all(color: p.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Handy shortcuts'),
                style: TextStyle(
                  color: p.textFaint,
                  fontSize: Fs.caption,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: Sp.sm),
              for (final (key, label) in keys)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    children: [
                      Container(
                        constraints: const BoxConstraints(minWidth: 92),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Sp.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: p.codeBg,
                          borderRadius: BorderRadius.circular(Rad.sm),
                          border: Border.all(color: p.border),
                        ),
                        child: Text(
                          key,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: p.text,
                            fontSize: Fs.small,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: Sp.md),
                      Expanded(
                        child: Text(
                          context.tr(label),
                          style: TextStyle(color: p.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
