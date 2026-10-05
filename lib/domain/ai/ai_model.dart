/// Capabilities come from the provider catalog, or an explicit user override.
class AiModel {
  const AiModel({
    required this.id,
    String? name,
    this.images = false,
    this.pdf = false,
    this.efforts = const [],
    this.known = false,
    this.maxOutputTokens,
  }) : name = name ?? id;
  final String id;
  final String name;
  final bool images;
  final bool pdf;
  final bool known;
  final int? maxOutputTokens;
  final List<String> efforts;

  static const allEfforts = [
    'none',
    'minimal',
    'low',
    'medium',
    'high',
    'xhigh',
    'max',
  ];

  factory AiModel.fromJson(Map<String, dynamic> j, String baseUrl) {
    final fallback = AiModel.fallback(j['id'] as String, baseUrl);
    final architecture = j['architecture'] as Map?;
    final modalities =
        architecture?['input_modalities'] as List? ??
        j['input_modalities'] as List?;
    final reasoning = j['reasoning'] as Map?;
    final supported =
        reasoning?['supported_efforts'] ?? j['supported_reasoning_efforts'];
    final mandatory = reasoning?['mandatory'] == true;
    final efforts = supported is List
        ? supported.whereType<String>().where(allEfforts.contains).toList()
        : reasoning?.containsKey('supported_efforts') == true
        ? allEfforts
        : fallback.efforts;
    return AiModel(
      id: fallback.id,
      name: j['name'] as String?,
      images: modalities == null
          ? fallback.images
          : modalities.contains('image'),
      pdf: modalities == null ? fallback.pdf : modalities.contains('file'),
      efforts: efforts.where((e) => !mandatory || e != 'none').toList(),
      known: modalities != null || fallback.known,
      maxOutputTokens:
          (j['top_provider'] is Map
                  ? (j['top_provider'] as Map)['max_completion_tokens'] as num?
                  : null)
              ?.toInt(),
    );
  }

  factory AiModel.fallback(String id, String baseUrl) {
    final host = Uri.tryParse(baseUrl)?.host;
    if (host != 'api.openai.com') return AiModel(id: id);
    final baseId = id.replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
    final gptEfforts = switch (baseId) {
      'gpt-5' ||
      'gpt-5-mini' ||
      'gpt-5-nano' => const ['minimal', 'low', 'medium', 'high'],
      'gpt-5.1' => const ['none', 'low', 'medium', 'high'],
      'gpt-5.2' => const ['none', 'low', 'medium', 'high', 'xhigh'],
      _ => const <String>[],
    };
    final vision = RegExp(
      r'^(gpt-4o(?:-mini)?|gpt-4\.1(?:-mini|-nano)?|o3|o4-mini)(?:-\d{4}-\d{2}-\d{2})?$',
    ).hasMatch(id);
    final reasoning = RegExp(
      r'^(o3(?:-mini)?|o4-mini)(?:-\d{4}-\d{2}-\d{2})?$',
    ).hasMatch(id);
    return AiModel(
      id: id,
      images: vision || gptEfforts.isNotEmpty,
      pdf: vision || gptEfforts.isNotEmpty,
      known: vision || reasoning || gptEfforts.isNotEmpty,
      efforts: gptEfforts.isNotEmpty
          ? gptEfforts
          : reasoning
          ? const ['low', 'medium', 'high']
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'images': images,
    'pdf': pdf,
    'efforts': efforts,
  };
  factory AiModel.fromOverride(Map<String, dynamic> j) => AiModel(
    id: j['id'] as String,
    name: j['name'] as String?,
    images: j['images'] == true,
    pdf: j['pdf'] == true,
    efforts: (j['efforts'] as List).cast<String>(),
    known: true,
  );
}
