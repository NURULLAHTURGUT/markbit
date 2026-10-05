import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/tokens.dart';

enum NoticeKind { info, success, warning, error }

/// One compact, animated notification queue per root overlay.
abstract final class AppNotifications {
  static final _queues = Expando<_NoticeQueue>();
  static void show(
    BuildContext context,
    String message, {
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
    NoticeKind kind = NoticeKind.info,
    OverlayState? overlay,
  }) {
    final target = overlay ?? Overlay.maybeOf(context, rootOverlay: true);
    if (target == null || !target.mounted) return;
    final queue = _queues[target] ??= _NoticeQueue(target);
    queue.add(_Notice(message, actionLabel, onAction, duration, kind));
  }
}

class _Notice {
  const _Notice(
    this.message,
    this.actionLabel,
    this.action,
    this.duration,
    this.kind,
  );
  final String message;
  final String? actionLabel;
  final VoidCallback? action;
  final Duration duration;
  final NoticeKind kind;
}

class _NoticeQueue {
  _NoticeQueue(this.overlay);
  final OverlayState overlay;
  final Queue<_Notice> pending = Queue();
  OverlayEntry? entry;
  String? currentMessage;
  void add(_Notice notice) {
    if (notice.message == currentMessage ||
        pending.any((n) => n.message == notice.message)) {
      return;
    }
    if (pending.length >= 10) pending.removeFirst();
    pending.add(notice);
    if (entry == null) _next();
  }

  void _next() {
    if (!overlay.mounted) {
      pending.clear();
      return;
    }
    if (pending.isEmpty) return;
    final notice = pending.removeFirst();
    currentMessage = notice.message;
    entry = OverlayEntry(
      builder: (_) => _NotificationCard(
        notice: notice,
        onDone: () {
          entry?.remove();
          entry?.dispose();
          entry = null;
          currentMessage = null;
          _next();
        },
      ),
    );
    overlay.insert(entry!);
  }
}

class _NotificationCard extends StatefulWidget {
  const _NotificationCard({required this.notice, required this.onDone});
  final _Notice notice;
  final VoidCallback onDone;
  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _timer;
  bool _closing = false;
  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 200),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _animation.value = 1;
      } else {
        _animation.forward();
      }
      _resume();
    });
  }

  void _resume() {
    _timer?.cancel();
    if (!_closing) _timer = Timer(widget.notice.duration, _close);
  }

  Future<void> _close() async {
    if (_closing || !mounted) return;
    _closing = true;
    _timer?.cancel();
    if (!MediaQuery.disableAnimationsOf(context)) await _animation.reverse();
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = widget.notice;
    final color = switch (n.kind) {
      NoticeKind.info => p.accent,
      NoticeKind.success => p.success,
      NoticeKind.warning => p.warning,
      NoticeKind.error => p.danger,
    };
    final icon = switch (n.kind) {
      NoticeKind.info => Icons.info_outline_rounded,
      NoticeKind.success => Icons.check_rounded,
      NoticeKind.warning => Icons.warning_amber_rounded,
      NoticeKind.error => Icons.error_outline_rounded,
    };
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: SlideTransition(
                position:
                    Tween<Offset>(
                      begin: const Offset(0, -1.2),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: FadeTransition(
                  opacity: _animation,
                  child: MouseRegion(
                    onEnter: (_) => _timer?.cancel(),
                    onExit: (_) => _resume(),
                    child: GestureDetector(
                      onVerticalDragEnd: (_) => _close(),
                      child: Material(
                        key: const ValueKey('app-notification'),
                        color: p.surface.withValues(alpha: 1),
                        borderRadius: BorderRadius.circular(20),
                        elevation: 8,
                        shadowColor: Colors.black.withValues(alpha: 0.16),
                        child: Semantics(
                          liveRegion: true,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: p.border),
                            ),
                            padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(Rad.md),
                                  ),
                                  child: Icon(icon, size: 18, color: color),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        n.message,
                                        style: TextStyle(
                                          color: p.text,
                                          fontSize: Fs.label,
                                          height: 1.4,
                                        ),
                                      ),
                                      if (n.actionLabel != null)
                                        TextButton(
                                          style: TextButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            minimumSize: const Size(0, 30),
                                            foregroundColor: p.accent,
                                          ),
                                          onPressed: () async {
                                            await _close();
                                            n.action?.call();
                                          },
                                          child: Text(n.actionLabel!),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('Dismiss notification'),
                                  onPressed: _close,
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                    color: p.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
