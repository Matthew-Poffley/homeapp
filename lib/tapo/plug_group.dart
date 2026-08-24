/// A user-defined group of plugs that can be toggled together.
class PlugGroup {
  final String id;
  final String name;
  final List<String> plugIds;

  PlugGroup({required this.id, required this.name, required this.plugIds});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'plugIds': plugIds};

  factory PlugGroup.fromJson(Map<String, dynamic> json) => PlugGroup(
    id: json['id'] as String,
    name: json['name'] as String,
    plugIds: (json['plugIds'] as List<dynamic>).cast<String>(),
  );
}
