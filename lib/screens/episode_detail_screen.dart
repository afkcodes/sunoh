// Episode detail, laid out as an album page: the episode's cover hero with
// the show as its byline, length and resume point in the meta line, then
// queue and play, then the show notes (HTML-stripped). Resume-from-saved-
// position is wired in AppState — we just call playApiSong; the seek to the
// saved position fires when the episode actually loads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';
import '../providers/palette_provider.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'detail_chrome.dart';
import 'detail_hero.dart';
import 'detail_loading.dart';

class EpisodeDetailScreen extends ConsumerStatefulWidget {
  const EpisodeDetailScreen({super.key, required this.guid});
  final String guid;
  @override
  ConsumerState<EpisodeDetailScreen> createState() =>
      _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState extends ConsumerState<EpisodeDetailScreen> {
  FeedItem? _episode;
  String? _art;
  String _notes = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(sunohApiProvider);
    try {
      final ep = await api.fetchPodcastEpisode(widget.guid);
      if (!mounted) return;
      setState(() {
        _episode = ep;
        // Worked out once here rather than on every rebuild.
        if (ep != null) {
          _art = ep.image.isNotEmpty ? ep.image.last.link : null;
          _notes = _stripHtml(_episodeDescription(ep));
        }
        _loading = false;
      });
    } on SunohApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final ep = _episode;
    if (_loading) return DetailLoading(colors: c);
    if (_error != null || ep == null) return _failed(c);

    final art = _art;
    final palette = art == null
        ? null
        : ref.watch(artPaletteProvider(art)).value;
    final accent = palette == null ? c.accent : s.themedAccent(palette.accent);
    final dur = int.tryParse(ep.duration ?? '') ?? 0;
    final resumeSec = s.episodeProgressSec(ep.id);
    final resume = resumeSec != null && resumeSec > 30;
    final here = s.currentApiSong?.id == ep.id;

    return DetailPage(
      colors: c,
      colour: accent,
      title: ep.title,
      builder: (scroll) => [
        SliverToBoxAdapter(
          child: DetailHero(
            colors: c,
            colour: accent,
            scroll: scroll,
            cover: DetailCover(id: ep.id, imageUrl: art),
            title: ep.title,
            byline: ep.subtitle,
            meta: joinMeta([
              'Episode',
              if (dur > 0) _fmtDuration(dur),
              if (resume) 'resume at ${_fmtPos(resumeSec)}',
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: FadeSlideIn(
            index: 3,
            child: DetailActions(
              colors: c,
              colour: accent,
              playing: here && s.isPlaying,
              shuffle: false,
              leading: [
                IconBtn(
                  icon: RemixIcons.add_circle_line,
                  color: c.fg,
                  onTap: () => s.addApiSongToQueue(ep),
                ),
              ],
              onPlay: () => here
                  ? s.playPause()
                  : s.playApiSong(
                      ep,
                      sourceLabel: 'PODCAST · ${ep.subtitle ?? "Episode"}',
                    ),
            ),
          ),
        ),
        if (_notes.isNotEmpty)
          SliverToBoxAdapter(
            child: DetailNote(colors: c, text: _notes),
          ),
      ],
    );
  }

  Widget _failed(SunohColors c) {
    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Couldn’t load this episode.\n${_error ?? ''}',
                textAlign: TextAlign.center,
                style: SunohType.sans(fontSize: 13, color: c.fgMute),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: DetailBar(
              colors: c,
              colour: c.bg,
              title: '',
              solid: const FixedFlag(false),
            ),
          ),
        ],
      ),
    );
  }

  static String _episodeDescription(FeedItem ep) {
    // FeedItem doesn't carry a description field today. Until we
    // surface one we just show an empty placeholder; the PodcastShow
    // detail already covers the show-level blurb.
    return '';
  }

  static String _stripHtml(String html) {
    final s = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _fmtDuration(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  static String _fmtPos(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
