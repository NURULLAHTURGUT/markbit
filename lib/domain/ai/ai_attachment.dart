import 'dart:convert';
import 'dart:typed_data';

class AiAttachment {
  const AiAttachment({
    required this.name,
    required this.mime,
    required this.data,
    required this.size,
    this.text,
  });
  final String name;
  final String mime;
  final String data;
  final int size;
  final String? text;
  bool get isImage => mime.startsWith('image/');
  bool get isPdf => mime == 'application/pdf';

  factory AiAttachment.fromBytes(String name, Uint8List bytes) {
    final extension = name.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      _ => 'text/plain',
    };
    final text = mime == 'text/plain' ? utf8.decode(bytes) : null;
    if (text != null && (text.contains('\u0000') || text.length > 200000)) {
      throw const FormatException(
        'Choose a UTF-8 text document under 200,000 characters.',
      );
    }
    return AiAttachment(
      name: name,
      mime: mime,
      size: bytes.length,
      data: text == null ? base64Encode(bytes) : '',
      text: text,
    );
  }

  Map<String, dynamic> get contentPart => text != null
      ? {'type': 'text', 'text': 'Attached document: $name\n\n$text'}
      : isImage
      ? {
          'type': 'image_url',
          'image_url': {'url': 'data:$mime;base64,$data'},
        }
      : {
          'type': 'file',
          'file': {'filename': name, 'file_data': 'data:$mime;base64,$data'},
        };

  Map<String, dynamic> toJson() => {
    'name': name,
    'mime': mime,
    'data': data,
    'size': size,
    'text': text,
  };
  factory AiAttachment.fromJson(Map<String, dynamic> j) => AiAttachment(
    name: j['name'] as String,
    mime: j['mime'] as String,
    data: j['data'] as String,
    size: j['size'] as int,
    text: j['text'] as String?,
  );
}
