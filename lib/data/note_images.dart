import '../core/util/ids.dart';
import 'models/note.dart';

/// Keep binary image data out of editor text and AI context.
abstract final class NoteImages {
  static final embedded = RegExp(
    r'(data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+)',
  );
  static final references = RegExp(r'attachment:[a-zA-Z0-9-]+');

  static Note compact(Note note) {
    if (note.kind != NoteKind.markdown || !note.body.contains('data:image/')) {
      return note;
    }
    final images = Map<String, String>.of(note.images);
    final body = note.body.replaceAllMapped(embedded, (match) {
      final data = match[0]!;
      var key = images.entries
          .where((e) => e.value == data)
          .map((e) => e.key)
          .firstOrNull;
      key ??= newId();
      images[key] = data;
      return 'attachment:$key';
    });
    return note.copyWith(body: body, images: images);
  }

  static String expand(Note note) => note.body.replaceAllMapped(
    references,
    (m) => note.images[m[0]!.substring('attachment:'.length)] ?? m[0]!,
  );

  static int width(String? title) =>
      (int.tryParse(
                RegExp(
                      r'(?:^|;)width=(\d+)%(?:;|$)',
                    ).firstMatch(title ?? '')?.group(1) ??
                    '',
              ) ??
              100)
          .clamp(10, 100);
}

class ImageOptions {
  const ImageOptions({
    this.width = 100,
    this.align = 'left',
    this.caption = '',
    this.rounded = false,
    this.remove = false,
  });
  final int width;
  final String align, caption;
  final bool rounded, remove;
  factory ImageOptions.parse(String? title, {String alt = ''}) => ImageOptions(
    width: NoteImages.width(title),
    align:
        RegExp(
          r'(?:^|;)align=(left|center|right)(?:;|$)',
        ).firstMatch(title ?? '')?.group(1) ??
        'left',
    rounded: (title ?? '').contains('rounded=1'),
    caption: (title ?? '').contains('caption=1') ? alt : '',
  );
  String get title =>
      'width=$width%;align=$align${rounded ? ';rounded=1' : ''}${caption.isNotEmpty ? ';caption=1' : ''}';
  String markdown(String uri, String fallback) {
    final alt = (caption.isEmpty ? fallback : caption)
        .replaceAll('\\', '\\\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]')
        .replaceAll('|', '&#124;')
        .replaceAll(RegExp(r'[\r\n]+'), ' ');
    return '![$alt]($uri "$title")';
  }
}
