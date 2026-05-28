// Episode detail. Cover + show breadcrumb + title + meta + Play button +
// show notes (HTML-stripped). Resume-from-saved-position is wired in
// AppState — we just open the episode + call playApiSong; the seek to
// the saved position fires when the episode actually loads.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/dto.dart';
import '../api/sunoh_api.dart';
import '../providers/api_providers.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/ui.dart';

class EpisodeDetailScreen extends ConsumerStatefulWidget {
  const EpisodeDetailScreen({super.key, required this.guid});
  final String guid;
  @override
  ConsumerState<EpisodeDetailScreen> createState() =>
      _EpisodeDetailScreenState();
}

class _EpisodeDetailScreenState
    extends ConsumerState<EpisodeDetailScreen> {
  FeedItem? _episode;
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
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  IconBtn(
                      icon: SolarIconsOutline.altArrowLeft,
                      color: c.fg,
                      size: 22,
                      onTap: () => context.pop()),
                  const SizedBox(width: 6),
                  eyebrow('EPISODE', c.fgMute),
                ],
              ),
            ),
            Expanded(child: _body(c, s)),
          ],
        ),
      ),
    );
  }

  Widget _body(SunohColors c, dynamic s) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2, color: c.fgDim),
        ),
      );
    }
    if (_error != null || _episode == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Couldn’t load this episode.\n${_error ?? ''}',
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 13, color: c.fgMute)),
        ),
      );
    }
    final ep = _episode!;
    final accent = s.resolvedAccent as Color;
    final dur = int.tryParse(ep.duration ?? '') ?? 0;
    final notes = _stripHtml(_episodeDescription(ep));
    final resumeSec = s.episodeProgressSec(ep.id) as int?;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 140),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            squircleClip(
              radius: 10,
              child: SunohArt(
                id: ep.id,
                imageUrl: ep.image.isNotEmpty ? ep.image.last.link : null,
                size: 96,
                radius: 10,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ((ep.subtitle ?? '').isNotEmpty)
                    Text(ep.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SunohType.sans(
                            fontSize: 12, color: c.fgMute)),
                  const SizedBox(height: 4),
                  Text(ep.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.heading(
                          fontSize: 18,
                          color: c.fg,
                          height: 1.2,
                          letterSpacing: -0.2)),
                  if (dur > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                        _fmtDuration(dur) +
                            (resumeSec != null && resumeSec > 30
                                ? ' · resume at ${_fmtPos(resumeSec)}'
                                : ''),
                        style: SunohType.sans(
                            fontSize: 12, color: c.fgDim)),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            GestureDetector(
              onTap: () => s.playApiSong(ep,
                  sourceLabel: 'PODCAST · ${ep.subtitle ?? "Episode"}'),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: accent.withValues(alpha: 0.33),
                        blurRadius: 18,
                        offset: const Offset(0, 6)),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIconsFill.play,
                        size: 18,
                        color: accent.computeLuminance() > 0.55
                            ? const Color(0xFF0B0B0D)
                            : const Color(0xFFFAFAFA)),
                    const SizedBox(width: 8),
                    Text(
                        resumeSec != null && resumeSec > 30
                            ? 'Resume'
                            : 'Play',
                        style: SunohType.sans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: accent.computeLuminance() > 0.55
                                ? const Color(0xFF0B0B0D)
                                : const Color(0xFFFAFAFA))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconBtn(
                icon: SolarIconsOutline.addCircle,
                color: c.fgDim,
                size: 18,
                width: 40,
                height: 40,
                background: c.surface,
                onTap: () => s.addApiSongToQueue(ep)),
          ],
        ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 24),
          eyebrow('SHOW NOTES', c.fgMute),
          const SizedBox(height: 8),
          Text(notes,
              style:
                  SunohType.sans(fontSize: 13, color: c.fgDim, height: 1.5)),
        ],
      ],
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
