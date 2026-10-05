import 'note.dart';
import 'package:flutter/foundation.dart';

@immutable
class Notebook {
  const Notebook({
    required this.id,
    required this.name,
    this.parentId,
    this.isInbox = false,
  });

  final String id;
  final String name;
  final String? parentId;

  /// The default notebook that cannot be deleted or renamed.
  final bool isInbox;

  Notebook copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
  }) => Notebook(
    id: id,
    name: name ?? this.name,
    parentId: clearParent ? null : (parentId ?? this.parentId),
    isInbox: isInbox,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'parentId': parentId,
    'isInbox': isInbox,
  };

  factory Notebook.fromJson(Map<String, dynamic> j) => Notebook(
    id: j['id'] as String,
    name: j['name'] as String,
    parentId: j['parentId'] as String?,
    isInbox: (j['isInbox'] as bool?) ?? false,
  );
}

@immutable
class Tag {
  const Tag({required this.id, required this.name, required this.colorValue});

  final String id;
  final String name;
  final int colorValue;

  Tag copyWith({String? name, int? colorValue}) => Tag(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': colorValue,
  };

  factory Tag.fromJson(Map<String, dynamic> j) => Tag(
    id: j['id'] as String,
    name: j['name'] as String,
    colorValue: (j['color'] as num).toInt(),
  );
}

@immutable
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    required this.body,
    this.title = '',
    this.notebookId,
    this.tagIds = const [],
    this.images = const {},
    this.attachments = const {},
  });

  final String id;
  final String name;
  final String title;
  final String body;
  final String? notebookId;
  final List<String> tagIds;
  final Map<String, String> images;
  final Map<String, NoteAttachment> attachments;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'tagIds': tagIds,
    'images': images,
    'attachments': attachments.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory NoteTemplate.fromJson(Map<String, dynamic> j) => NoteTemplate(
    id: j['id'] as String,
    name: j['name'] as String,
    title: (j['title'] as String?) ?? '',
    body: (j['body'] as String?) ?? '',
    notebookId: j['notebookId'] as String?,
    tagIds: List<String>.from(j['tagIds'] as List? ?? []),
    images: Map<String, String>.from(j['images'] as Map? ?? {}),
    attachments: (j['attachments'] as Map? ?? {}).map(
      (k, v) => MapEntry(
        k as String,
        NoteAttachment.fromJson(Map<String, dynamic>.from(v as Map)),
      ),
    ),
  );
}
