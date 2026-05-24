// Domain models for the sunoh. catalog.
// Ported from the design prototype's data.jsx — fictional placeholder content.

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration, // seconds
    required this.plays,
  });

  final String id;
  final String title;
  final String artist;
  final String album; // album id, or a podcast/station id for synthesized tracks
  final int duration;
  final String plays;
}

class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.kind, // Album | EP | Single
    required this.trackCount,
    required this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final int year;
  final String kind;
  final int trackCount;
  final String duration;
}

class Artist {
  const Artist({
    required this.id,
    required this.name,
    required this.monthly,
    required this.tags,
  });

  final String id;
  final String name;
  final String monthly;
  final List<String> tags;
}

class Playlist {
  const Playlist({
    required this.id,
    required this.title,
    required this.curator,
    required this.tracks,
    required this.hours,
    required this.sub,
  });

  final String id;
  final String title;
  final String curator;
  final int tracks;
  final String hours;
  final String sub;
}

class Station {
  const Station({
    required this.id,
    required this.name,
    required this.freq,
    required this.tag,
    required this.live,
    required this.listeners,
  });

  final String id;
  final String name;
  final String freq;
  final String tag;
  final String live;
  final String listeners;

  double get freqValue => double.parse(freq);
}

class Podcast {
  const Podcast({
    required this.id,
    required this.title,
    required this.host,
    required this.cadence,
    required this.episodes,
    required this.sub,
  });

  final String id;
  final String title;
  final String host;
  final String cadence;
  final int episodes;
  final String sub;
}

class Episode {
  const Episode({
    required this.id,
    required this.pod,
    required this.num,
    required this.title,
    required this.date,
    required this.duration,
    required this.sub,
  });

  final String id;
  final String pod;
  final int num;
  final String title;
  final String date;
  final String duration;
  final String sub;
}

class Mix {
  const Mix({required this.id, required this.title, required this.sub});
  final String id;
  final String title;
  final String sub;
}

class LyricLine {
  const LyricLine(this.t, this.line);
  final int t; // start time in seconds
  final String line;
}

/// A navigation destination pushed onto the detail stack.
class DetailRef {
  const DetailRef(this.kind, this.id, {this.source});
  final String kind; // album | playlist | artist | podcast | station
  final String id;
  /// Which backend provider this entity belongs to ('saavn' | 'gaana' |
  /// 'spotify'). Required by sunoh-api for album/playlist/song endpoints —
  /// the server defaults to saavn when missing, which 404s for gaana ids.
  final String? source;

  @override
  bool operator ==(Object other) =>
      other is DetailRef &&
      other.kind == kind &&
      other.id == id &&
      other.source == source;

  @override
  int get hashCode => Object.hash(kind, id, source);
}
