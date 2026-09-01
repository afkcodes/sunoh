// The Music / Podcasts / Audiobooks home feeds, as Android Auto browse nodes.
//
// These mirror the three top tabs of the phone's Home screen. Each is a list
// of editorial sections ("New releases", "Trending"), and each section is a
// list of rows the car can either play or drill into.
//
// Two shapes, two levels:
//
//   sunoh:f:<feed>            the feed        → its sections
//   sunoh:g:<feed>#<index>    one section     → its items
//
// Sections are addressed by position because their headings are
// server-supplied free text: they are not stable ids, they change between
// requests, and they routinely contain the colons and hashes our id format
// uses as separators.

import 'package:audio_service/audio_service.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import 'auto_catalog.dart';
import 'auto_media_id.dart';

/// The three home feeds, in the order the phone shows them.
enum AutoFeed { music, podcasts, audiobooks }

extension AutoFeedX on AutoFeed {
  String get id => '$kAutoFeedPrefix$name';
  String get title => switch (this) {
    AutoFeed.music => 'Music',
    AutoFeed.podcasts => 'Podcasts',
    AutoFeed.audiobooks => 'Audiobooks',
  };
}

const String kAutoFeedPrefix = 'sunoh:f:';
const String kAutoSectionPrefix = 'sunoh:g:';

class AutoFeeds {
  AutoFeeds({required this.api, required this.catalog, this.languages});

  final SunohApi api;
  final AutoCatalog catalog;

  /// The user's music-language selection, so the car's Music tab matches the
  /// phone's. Null lets the backend pick its default.
  final String? Function()? languages;

  /// Sections per feed, cached for the life of the service.
  ///
  /// A car reconnect re-walks the whole tree, and these are the most
  /// expensive nodes here — three network round trips, on a connection that
  /// may be moving at speed. Holding them keeps a re-browse instant.
  final Map<AutoFeed, List<HomeSection>> _sections = {};

  static bool isFeed(String id) => id.startsWith(kAutoFeedPrefix);
  static bool isSection(String id) => id.startsWith(kAutoSectionPrefix);

  /// The three feed rows, for the root.
  List<MediaItem> feedTabs() => [
    for (final f in AutoFeed.values)
      MediaItem(
        id: f.id,
        title: f.title,
        playable: false,
        extras: kChildrenList,
      ),
  ];

  /// One feed's sections, as browsable rows.
  Future<List<MediaItem>> sections(String feedId) async {
    final feed = _feedOf(feedId);
    if (feed == null) return const [];
    final sections = await _load(feed);
    final rows = <MediaItem>[];
    for (var i = 0; i < sections.length; i++) {
      final s = sections[i];
      // Skip anything that would render as an empty screen. A section whose
      // rows are all of a type we can't route (upstream adds them without
      // notice) is worse than an absent one: in the car it looks like a
      // loading failure with no way to tell.
      if (!s.items.any(AutoCatalog.isRenderable)) continue;
      final heading = s.heading.trim();
      rows.add(
        MediaItem(
          id: '$kAutoSectionPrefix${feed.name}#$i',
          title: heading.isEmpty ? feed.title : heading,
          artist: '${s.items.length} items',
          playable: false,
          // Mixed children: collections and songs in one scroll. Hinting both
          // as list keeps the row height uniform — see kChildrenList.
          extras: kChildrenList,
          // Artwork of the first entry, so a section reads as itself rather
          // than as an anonymous text row.
          artUri: AutoCatalog.artOf(s.items.first),
        ),
      );
    }
    return rows;
  }

  /// One section's items: songs play, collections drill in.
  Future<List<MediaItem>> sectionItems(String sectionId) async {
    if (!isSection(sectionId)) return const [];
    final body = sectionId.substring(kAutoSectionPrefix.length);
    final hash = body.lastIndexOf('#');
    if (hash < 0) return const [];
    final feed = _feedNamed(body.substring(0, hash));
    final index = int.tryParse(body.substring(hash + 1));
    if (feed == null || index == null) return const [];

    final sections = await _load(feed);
    if (index < 0 || index >= sections.length) return const [];
    final section = sections[index];
    final label = section.heading.trim().isEmpty
        ? feed.title.toUpperCase()
        : section.heading.trim().toUpperCase();

    // A section of nothing but songs is a playlist in disguise — serve it as
    // one so the whole row is a queue and tapping track 3 starts at track 3.
    final songs = section.items.where((i) => i.type == 'song').toList();
    if (songs.length == section.items.length) {
      return catalog.tracks(sectionId, songs, label);
    }

    // Mixed or collection-only: remember the songs among them so a tapped
    // track still plays with its neighbours as the queue.
    catalog.remember(sectionId, songs, label);
    final rows = <MediaItem>[];
    var songIndex = 0;
    for (final item in section.items) {
      if (item.type == 'song') {
        rows.add(
          catalog.mediaItem(
            item,
            id: AutoMediaId.track(sectionId, songIndex++),
          ),
        );
        continue;
      }
      final collectionId = AutoCatalog.collectionIdFor(item);
      if (collectionId == null) continue;
      catalog.label(collectionId, '${item.type.toUpperCase()} · ${item.title}');
      rows.add(catalog.browsable(item, id: collectionId));
    }
    return rows;
  }

  /// Fetch (and cache) a feed's sections. A failure yields an empty feed
  /// rather than propagating — the car shows an empty tab it can back out of.
  Future<List<HomeSection>> _load(AutoFeed feed) async {
    final cached = _sections[feed];
    if (cached != null) return cached;
    try {
      final sections = switch (feed) {
        AutoFeed.music => await api.fetchHome(languages: languages?.call()),
        AutoFeed.podcasts => await api.fetchPodcastHome(),
        AutoFeed.audiobooks => await api.fetchAudiobookHome(),
      };
      _sections[feed] = sections;
      return sections;
    } catch (_) {
      return const [];
    }
  }

  AutoFeed? _feedOf(String feedId) => isFeed(feedId)
      ? _feedNamed(feedId.substring(kAutoFeedPrefix.length))
      : null;

  static AutoFeed? _feedNamed(String name) {
    for (final f in AutoFeed.values) {
      if (f.name == name) return f;
    }
    return null;
  }
}
