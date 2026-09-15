class AppPopup {
  const AppPopup({
    required this.id,
    required this.title,
    required this.message,
    required this.version,
    this.enabled = false,
  });

  final String id;
  final String title;
  final String message;
  final String version;
  final bool enabled;

  bool get visible =>
      enabled && title.trim().isNotEmpty && message.trim().isNotEmpty;

  factory AppPopup.fromJson(String id, Map<String, dynamic> json) => AppPopup(
        id: id,
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        version: json['version'] as String? ?? id,
        enabled: json['enabled'] as bool? ?? false,
      );
}
