enum PlugProtocol { klap, legacy }

/// A plug (or one outlet of a multi-outlet power strip) the user has added
/// to the app. The password (if any — legacy devices need none) is never
/// stored here — it lives in secure storage, keyed by [id] — so this model
/// is safe to serialize to plain SharedPreferences.
class SavedPlug {
  final String id;
  final String name;
  final String host;
  final String email;
  final PlugProtocol protocol;

  /// Which outlet this represents on a legacy power strip with multiple
  /// individually-switchable sockets. Null for a normal single-relay plug.
  final String? childId;

  SavedPlug({
    required this.id,
    required this.name,
    required this.host,
    required this.email,
    required this.protocol,
    this.childId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'host': host,
    'email': email,
    'protocol': protocol.name,
    if (childId != null) 'childId': childId,
  };

  factory SavedPlug.fromJson(Map<String, dynamic> json) => SavedPlug(
    id: json['id'] as String,
    name: json['name'] as String,
    host: json['host'] as String,
    email: json['email'] as String? ?? '',
    // Plugs saved before legacy support was added have no 'protocol' field.
    protocol: PlugProtocol.values.firstWhere(
      (p) => p.name == json['protocol'],
      orElse: () => PlugProtocol.klap,
    ),
    childId: json['childId'] as String?,
  );
}
