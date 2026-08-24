/// A user-defined action button that turns off a set of plugs and pauses
/// their on-device schedule for a fixed duration (e.g. "Guest over" pausing
/// the grow lamps for a day), rather than just toggling power once.
class PlugAction {
  final String id;
  final String name;
  final List<String> plugIds;
  final int pauseHours;

  /// When this action's pause is due to lift, or null if it isn't active.
  final DateTime? activeUntil;

  PlugAction({
    required this.id,
    required this.name,
    required this.plugIds,
    required this.pauseHours,
    this.activeUntil,
  });

  bool get isActive => activeUntil != null && activeUntil!.isAfter(DateTime.now());

  PlugAction withActiveUntil(DateTime? activeUntil) => PlugAction(
    id: id,
    name: name,
    plugIds: plugIds,
    pauseHours: pauseHours,
    activeUntil: activeUntil,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'plugIds': plugIds,
    'pauseHours': pauseHours,
    if (activeUntil != null) 'activeUntil': activeUntil!.toIso8601String(),
  };

  factory PlugAction.fromJson(Map<String, dynamic> json) => PlugAction(
    id: json['id'] as String,
    name: json['name'] as String,
    plugIds: (json['plugIds'] as List<dynamic>).cast<String>(),
    pauseHours: json['pauseHours'] as int,
    activeUntil: json['activeUntil'] != null
        ? DateTime.parse(json['activeUntil'] as String)
        : null,
  );
}
