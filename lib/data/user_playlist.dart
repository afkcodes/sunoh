// User-created playlist — local-only, stored in the Hive `library` box
// alongside liked / saved collections. Songs are full FeedItems (same as
// liked / history) so we can play them without a network round-trip.

import '../api/dto.dart';

class UserPlaylist {
  const UserPlaylist({
    required this.id,
    required this.name,
    required this.songs,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Random short id assigned at creation time (kebab-cased timestamp +
  /// random suffix). Stable across renames so the detail screen URL
  /// doesn't change.
  final String id;
  final String name;
  final List<FeedItem> songs;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserPlaylist copyWith({
    String? name,
    List<FeedItem>? songs,
    DateTime? updatedAt,
  }) {
    return UserPlaylist(
      id: id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'songs': songs.map((s) => s.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static UserPlaylist fromJson(Map<String, dynamic> j) {
    final raw = j['songs'];
    final songs = raw is List
        ? raw
            .whereType<Map>()
            .map((m) => FeedItem.fromJson(m.cast<String, dynamic>()))
            .toList()
        : <FeedItem>[];
    return UserPlaylist(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      songs: songs,
      createdAt: DateTime.tryParse(j['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.tryParse(j['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
