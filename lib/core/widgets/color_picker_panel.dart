import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_strings.dart';
import '../theme/app_palette.dart';
import '../theme/tokens.dart';

/// Shared across tag and text dialogs. Only confirmed colors enter the history.
class RecentColors {
  static const key = 'recent_custom_colors';
  static Future<List<Color>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(key) ?? [])
        .map((s) => int.tryParse(s, radix: 16))
        .whereType<int>()
        .take(5)
        .map(Color.new)
        .toList();
  }

  static Future<void> remember(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    final value = color.toARGB32().toRadixString(16);
    final values = {
      value,
      ...prefs.getStringList(key) ?? <String>[],
    }.take(5).toList();
    await prefs.setStringList(key, values);
  }
}

/// Saturation/value square and vertical hue spectrum, with a precise HEX field.
class ColorPickerPanel extends StatefulWidget {
  const ColorPickerPanel({
    super.key,
    required this.color,
    required this.onChanged,
    this.onValidityChanged,
  });
  final Color color;
  final ValueChanged<Color> onChanged;
  final ValueChanged<bool>? onValidityChanged;

  @override
  State<ColorPickerPanel> createState() => _ColorPickerPanelState();
}

class _ColorPickerPanelState extends State<ColorPickerPanel> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  late final _hex = TextEditingController(text: _hexOf(widget.color));
  List<Color> _recent = [];
  String? _error;
  String _hexOf(Color c) =>
      c.toARGB32().toRadixString(16).substring(2).toUpperCase();

  @override
  void initState() {
    super.initState();
    RecentColors.load()
        .then((colors) {
          if (mounted) setState(() => _recent = colors);
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor color) {
    setState(() {
      _hsv = color;
      _hex.text = _hexOf(color.toColor());
      _error = null;
    });
    widget.onChanged(color.toColor());
    widget.onValidityChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final height = (constraints.maxWidth * .68).clamp(140.0, 220.0);
            return SizedBox(
              height: height,
              child: Row(
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, bounds) {
                        void choose(Offset point) => _set(
                          _hsv
                              .withSaturation(
                                (point.dx / bounds.maxWidth).clamp(0.0, 1.0),
                              )
                              .withValue(
                                (1 - point.dy / height).clamp(0.0, 1.0),
                              ),
                        );
                        return Semantics(
                          label: context.tr('Saturation and brightness'),
                          child: GestureDetector(
                            key: const ValueKey('color-saturation-value'),
                            onPanDown: (d) => choose(d.localPosition),
                            onPanUpdate: (d) => choose(d.localPosition),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Rad.md),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.white,
                                          HSVColor.fromAHSV(
                                            1,
                                            _hsv.hue,
                                            1,
                                            1,
                                          ).toColor(),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: [
                                          Colors.transparent,
                                          Colors.black,
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left:
                                        (_hsv.saturation * bounds.maxWidth - 7)
                                            .clamp(0.0, bounds.maxWidth - 14),
                                    top: ((1 - _hsv.value) * height - 7).clamp(
                                      0.0,
                                      height - 14,
                                    ),
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: _hsv.toColor(),
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Colors.black54,
                                            blurRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Semantics(
                    label: context.tr('Hue'),
                    value: '${_hsv.hue.round()}°',
                    increasedValue: '${((_hsv.hue + 5) % 360).round()}°',
                    decreasedValue: '${((_hsv.hue - 5 + 360) % 360).round()}°',
                    onIncrease: () => _set(_hsv.withHue((_hsv.hue + 5) % 360)),
                    onDecrease: () =>
                        _set(_hsv.withHue((_hsv.hue - 5 + 360) % 360)),
                    child: GestureDetector(
                      key: const ValueKey('color-hue'),
                      onPanDown: (d) => _set(
                        _hsv.withHue(
                          (d.localPosition.dy / height * 360).clamp(0.0, 360.0),
                        ),
                      ),
                      onPanUpdate: (d) => _set(
                        _hsv.withHue(
                          (d.localPosition.dy / height * 360).clamp(0.0, 360.0),
                        ),
                      ),
                      child: SizedBox(
                        width: 28,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(Rad.sm),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    for (var h = 0; h <= 360; h += 60)
                                      HSVColor.fromAHSV(
                                        1,
                                        h.toDouble(),
                                        1,
                                        1,
                                      ).toColor(),
                                  ],
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: (_hsv.hue / 360 * height - 4).clamp(
                                0.0,
                                height - 8,
                              ),
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(Rad.xs),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black54,
                                      blurRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('Recently used colors'),
          style: TextStyle(fontSize: Fs.small, color: p.textMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < 5; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: i < _recent.length
                      ? Tooltip(
                          message: '#${_hexOf(_recent[i])}',
                          child: OutlinedButton(
                            key: ValueKey('recent-color-$i'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: _recent[i],
                              padding: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(Rad.md),
                              ),
                              side: BorderSide(color: p.border),
                            ),
                            onPressed: () =>
                                _set(HSVColor.fromColor(_recent[i])),
                            child: const SizedBox.shrink(),
                          ),
                        )
                      : DecoratedBox(
                          decoration: BoxDecoration(
                            color: p.text.withValues(alpha: .04),
                            border: Border.all(color: p.border),
                            borderRadius: BorderRadius.circular(Rad.md),
                          ),
                        ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 48,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(Rad.md),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                key: const ValueKey('color-hex'),
                controller: _hex,
                maxLength: 7,
                decoration: InputDecoration(
                  labelText: context.tr('Custom color (HEX)'),
                  prefixText: '#',
                  counterText: '',
                  errorText: _error,
                ),
                onChanged: (value) {
                  final raw = value.trim().replaceFirst('#', '');
                  if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(raw)) {
                    final c = Color(int.parse('FF$raw', radix: 16));
                    setState(() {
                      _hsv = HSVColor.fromColor(c);
                      _error = null;
                    });
                    widget.onChanged(c);
                    widget.onValidityChanged?.call(true);
                  } else {
                    setState(
                      () => _error = context.tr('Enter a 6-digit HEX color.'),
                    );
                    widget.onValidityChanged?.call(false);
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
