import 'package:flutter/foundation.dart';

import '../../core/l10n/app_strings.dart';
import '../../domain/note_crypto.dart';

enum NoteStatus {
  none('No status'),
  active('Active'),
  onHold('On Hold'),
  completed('Completed'),
  dropped('Dropped');

  const NoteStatus(this.label);
  final String label;

  static NoteStatus parse(String? name) => NoteStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => NoteStatus.none,
  );
}

enum NoteKind {
  /// Markdown document with runnable fenced code blocks.
  markdown,

  /// A single source file that is edited and run as a whole.
  code;

  static NoteKind parse(String? name) => NoteKind.values.firstWhere(
    (k) => k.name == name,
    orElse: () => NoteKind.markdown,
  );
}

const Object _keep = Object();

@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.updatedAt,
    this.notebookId,
    this.status = NoteStatus.none,
    this.tagIds = const [],
    this.pinned = false,
    this.starred = false,
    this.trashed = false,
    this.kind = NoteKind.markdown,
    this.language,
    this.coverImage,
    this.images = const {},
    this.attachments = const {},
    this.dailyDate,
    this.trashedAt,
    this.lock,
  });

  final String id;
  final String title;
  final String body;
  final String? notebookId;
  final NoteStatus status;
  final List<String> tagIds;
  final bool pinned;

  /// Favourite; listed under "Starred" in the sidebar.
  final bool starred;
  final bool trashed;
  final NoteKind kind;

  /// Language id for [NoteKind.code] notes.
  final String? language;

  /// Embedded image bytes (base64), independent of the source file's location.
  final String? coverImage;

  /// Portable image data, referenced by short attachment: links in the body.
  final Map<String, String> images;
  final Map<String, NoteAttachment> attachments;
  final String? dailyDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// When the note was moved to the trash; drives automatic deletion.
  final DateTime? trashedAt;

  /// Present for password-protected notes. Their [body], [images] and
  /// [attachments] are empty here and live encrypted in the lock.
  final NoteLock? lock;

  bool get isLocked => lock != null;

  String get displayTitle =>
      title.trim().isEmpty ? trs('Untitled') : title.trim();

  Note copyWith({
    String? title,
    String? body,
    Object? notebookId = _keep,
    NoteStatus? status,
    List<String>? tagIds,
    bool? pinned,
    bool? starred,
    bool? trashed,
    NoteKind? kind,
    Object? language = _keep,
    Object? coverImage = _keep,
    Map<String, String>? images,
    Map<String, NoteAttachment>? attachments,
    DateTime? updatedAt,
    Object? trashedAt = _keep,
    Object? lock = _keep,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      body: body ?? this.body,
      notebookId: identical(notebookId, _keep)
          ? this.notebookId
          : notebookId as String?,
      status: status ?? this.status,
      tagIds: tagIds ?? this.tagIds,
      pinned: pinned ?? this.pinned,
      starred: starred ?? this.starred,
      trashed: trashed ?? this.trashed,
      kind: kind ?? this.kind,
      language: identical(language, _keep)
          ? this.language
          : language as String?,
      coverImage: identical(coverImage, _keep)
          ? this.coverImage
          : coverImage as String?,
      images: images ?? this.images,
      attachments: attachments ?? this.attachments,
      dailyDate: dailyDate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trashedAt: identical(trashedAt, _keep)
          ? this.trashedAt
          : trashedAt as DateTime?,
      lock: identical(lock, _keep) ? this.lock : lock as NoteLock?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'body': body,
    'notebookId': notebookId,
    'status': status.name,
    'tagIds': tagIds,
    'pinned': pinned,
    if (starred) 'starred': true,
    'trashed': trashed,
    'kind': kind.name,
    'language': language,
    'coverImage': coverImage,
    'images': images,
    'attachments': attachments.map((k, v) => MapEntry(k, v.toJson())),
    'dailyDate': dailyDate,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    if (trashedAt != null) 'trashedAt': trashedAt!.toIso8601String(),
    if (lock != null) 'lock': lock!.toJson(),
  };

  factory Note.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return Note(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      notebookId: json['notebookId'] as String?,
      status: NoteStatus.parse(json['status'] as String?),
      tagIds: ((json['tagIds'] as List?) ?? const []).cast<String>(),
      pinned: (json['pinned'] as bool?) ?? false,
      starred: (json['starred'] as bool?) ?? false,
      trashed: (json['trashed'] as bool?) ?? false,
      kind: NoteKind.parse(json['kind'] as String?),
      language: json['language'] as String?,
      coverImage: json['coverImage'] as String?,
      images: Map<String, String>.from(json['images'] as Map? ?? const {}),
      attachments: (json['attachments'] as Map? ?? {}).map(
        (k, v) => MapEntry(
          k as String,
          NoteAttachment.fromJson(Map<String, dynamic>.from(v as Map)),
        ),
      ),
      dailyDate: json['dailyDate'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ?? now,
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ?? now,
      trashedAt: DateTime.tryParse((json['trashedAt'] as String?) ?? ''),
      lock: json['lock'] is Map
          ? NoteLock.fromJson(Map<String, dynamic>.from(json['lock'] as Map))
          : null,
    );
  }
}

@immutable
class NoteAttachment {
  const NoteAttachment({
    required this.name,
    required this.data,
    required this.size,
  });
  final String name, data;
  final int size;
  Map<String, dynamic> toJson() => {'name': name, 'data': data, 'size': size};
  factory NoteAttachment.fromJson(Map<String, dynamic> j) => NoteAttachment(
    name: j['name'] as String,
    data: j['data'] as String,
    size: (j['size'] as num).toInt(),
  );
}
