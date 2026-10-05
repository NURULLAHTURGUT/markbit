import 'package:flutter/foundation.dart';

enum ViewMode { edit, split, preview }

enum SortField { updated, created, title }

/// How code runs.
enum ExecutionMode {
  /// Use local toolchains when installed, otherwise the remote API.
  auto('Automatic'),

  /// Only local toolchains (desktop).
  local('Local only'),

  /// Only the Piston-compatible remote API.
  remote('Remote API only');

  const ExecutionMode(this.label);
  final String label;
}

@immutable
class AppSettings {
  const AppSettings({
    this.themeId = 'system',
    this.language = 'system',
    this.editorFontSize = 14,
    this.lineNumbers = true,
    this.markdownSuggestions = true,
    this.trashRetentionDays = 30,
    this.historyLimit = 100,
    this.systemNotifications = true,
    this.uiScale = 1.0,
    this.shortcuts = const {},
    this.defaultViewMode = ViewMode.split,
    this.sortField = SortField.updated,
    this.sortAscending = false,
    this.sidebarWidth = 248,
    this.listWidth = 330,
    this.executionMode = ExecutionMode.auto,
    // Empty: code is never sent to a remote service until the user enters
    // their own Piston-compatible server.
    this.remoteEndpoint = '',
    this.runTimeoutSeconds = 20,
    this.aiBaseUrl = 'https://api.openai.com/v1',
    this.aiModel = 'gpt-4o-mini',
    this.aiSystemPrompt =
        'You are a concise senior software engineer helping inside a developer notebook. '
        'Answer in the language the user writes in. Prefer short explanations and '
        'fenced code blocks with a language tag.',
  });

  final String themeId;

  /// `system`, `en` or `tr`.
  final String language;
  final double editorFontSize;
  final bool lineNumbers;
  final bool markdownSuggestions;

  /// Days a note stays in the trash before it is deleted; 0 keeps it.
  final int trashRetentionDays;

  /// Versions kept per note in version history.
  final int historyLimit;

  /// Task reminders as operating-system notifications (also while closed).
  final bool systemNotifications;

  /// Interface zoom, 0.8-1.5 (everything, not just text).
  final double uiScale;

  /// Rebound keyboard shortcuts: action name -> serialized key combination.
  final Map<String, String> shortcuts;
  final ViewMode defaultViewMode;
  final SortField sortField;
  final bool sortAscending;
  final double sidebarWidth;
  final double listWidth;
  final ExecutionMode executionMode;
  final String remoteEndpoint;
  final int runTimeoutSeconds;
  final String aiBaseUrl;
  final String aiModel;
  final String aiSystemPrompt;

  AppSettings copyWith({
    String? themeId,
    String? language,
    double? editorFontSize,
    bool? lineNumbers,
    bool? markdownSuggestions,
    int? trashRetentionDays,
    int? historyLimit,
    bool? systemNotifications,
    double? uiScale,
    Map<String, String>? shortcuts,
    ViewMode? defaultViewMode,
    SortField? sortField,
    bool? sortAscending,
    double? sidebarWidth,
    double? listWidth,
    ExecutionMode? executionMode,
    String? remoteEndpoint,
    int? runTimeoutSeconds,
    String? aiBaseUrl,
    String? aiModel,
    String? aiSystemPrompt,
  }) {
    return AppSettings(
      themeId: themeId ?? this.themeId,
      language: language ?? this.language,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      lineNumbers: lineNumbers ?? this.lineNumbers,
      markdownSuggestions: markdownSuggestions ?? this.markdownSuggestions,
      trashRetentionDays: trashRetentionDays ?? this.trashRetentionDays,
      historyLimit: historyLimit ?? this.historyLimit,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      uiScale: uiScale ?? this.uiScale,
      shortcuts: shortcuts ?? this.shortcuts,
      defaultViewMode: defaultViewMode ?? this.defaultViewMode,
      sortField: sortField ?? this.sortField,
      sortAscending: sortAscending ?? this.sortAscending,
      sidebarWidth: sidebarWidth ?? this.sidebarWidth,
      listWidth: listWidth ?? this.listWidth,
      executionMode: executionMode ?? this.executionMode,
      remoteEndpoint: remoteEndpoint ?? this.remoteEndpoint,
      runTimeoutSeconds: runTimeoutSeconds ?? this.runTimeoutSeconds,
      aiBaseUrl: aiBaseUrl ?? this.aiBaseUrl,
      aiModel: aiModel ?? this.aiModel,
      aiSystemPrompt: aiSystemPrompt ?? this.aiSystemPrompt,
    );
  }

  Map<String, dynamic> toJson() => {
    'themeId': themeId,
    'language': language,
    'editorFontSize': editorFontSize,
    'lineNumbers': lineNumbers,
    'markdownSuggestions': markdownSuggestions,
    'trashRetentionDays': trashRetentionDays,
    'historyLimit': historyLimit,
    'systemNotifications': systemNotifications,
    'uiScale': uiScale,
    'shortcuts': shortcuts,
    'defaultViewMode': defaultViewMode.name,
    'sortField': sortField.name,
    'sortAscending': sortAscending,
    'sidebarWidth': sidebarWidth,
    'listWidth': listWidth,
    'executionMode': executionMode.name,
    'remoteEndpoint': remoteEndpoint,
    'runTimeoutSeconds': runTimeoutSeconds,
    'aiBaseUrl': aiBaseUrl,
    'aiModel': aiModel,
    'aiSystemPrompt': aiSystemPrompt,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    const d = AppSettings();
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    return AppSettings(
      themeId: (j['themeId'] as String?) ?? d.themeId,
      language: (j['language'] as String?) ?? d.language,
      editorFontSize:
          (j['editorFontSize'] as num?)?.toDouble() ?? d.editorFontSize,
      lineNumbers: (j['lineNumbers'] as bool?) ?? d.lineNumbers,
      markdownSuggestions:
          (j['markdownSuggestions'] as bool?) ?? d.markdownSuggestions,
      trashRetentionDays:
          (j['trashRetentionDays'] as num?)?.toInt() ?? d.trashRetentionDays,
      historyLimit: (j['historyLimit'] as num?)?.toInt() ?? d.historyLimit,
      systemNotifications:
          (j['systemNotifications'] as bool?) ?? d.systemNotifications,
      uiScale: ((j['uiScale'] as num?)?.toDouble() ?? d.uiScale).clamp(
        0.8,
        1.5,
      ),
      shortcuts: j['shortcuts'] is Map
          ? Map<String, String>.from(j['shortcuts'] as Map)
          : d.shortcuts,
      defaultViewMode: pick(
        ViewMode.values,
        j['defaultViewMode'] as String?,
        d.defaultViewMode,
      ),
      sortField: pick(SortField.values, j['sortField'] as String?, d.sortField),
      sortAscending: (j['sortAscending'] as bool?) ?? d.sortAscending,
      sidebarWidth: (j['sidebarWidth'] as num?)?.toDouble() ?? d.sidebarWidth,
      listWidth: (j['listWidth'] as num?)?.toDouble() ?? d.listWidth,
      executionMode: pick(
        ExecutionMode.values,
        j['executionMode'] as String?,
        d.executionMode,
      ),
      remoteEndpoint: (j['remoteEndpoint'] as String?) ?? d.remoteEndpoint,
      runTimeoutSeconds:
          (j['runTimeoutSeconds'] as num?)?.toInt() ?? d.runTimeoutSeconds,
      aiBaseUrl: (j['aiBaseUrl'] as String?) ?? d.aiBaseUrl,
      aiModel: (j['aiModel'] as String?) ?? d.aiModel,
      aiSystemPrompt: (j['aiSystemPrompt'] as String?) ?? d.aiSystemPrompt,
    );
  }
}
