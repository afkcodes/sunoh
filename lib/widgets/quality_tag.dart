// What the current track's audio actually is, and what the app is doing about
// it.
//
// Three states, one slot. The point of the tag is to answer a question the
// listener would otherwise have no way to settle: "the setting says lossless —
// am I actually getting it?"
//
//   - **Looking.** A cold catalog lookup takes a moment, and silence during it
//     reads as the feature doing nothing at all.
//   - **Found.** Named from mpv's own decoder, so it cannot claim hi-res for a
//     stream that is not. See AppState.currentQualityLabel.
//   - **Not found.** Most hi-res catalogues are a fraction of the size of the
//     streaming ones, so this is the common case and not an error. It says so
//     in those terms, and then gets out of the way.
//
// Nothing is shown for a lossy track when the setting is off. A tag that is
// always present answers nothing.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/lossless_api.dart';
import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';

/// How long "no hi-res" stays up before fading.
///
/// Long enough to read, short enough that a permanent apology does not become
/// part of the layout. The found state has no timer — that one is worth
/// keeping on screen.
const Duration _kMissLinger = Duration(seconds: 6);

class QualityTag extends ConsumerStatefulWidget {
  const QualityTag({super.key, required this.colors, this.compact = false});

  final SunohColors colors;

  /// The mini player's variant: shorter copy, smaller type, no spinner.
  final bool compact;

  @override
  ConsumerState<QualityTag> createState() => _QualityTagState();
}

class _QualityTagState extends ConsumerState<QualityTag> {
  Timer? _hideMiss;
  bool _missExpired = false;
  String? _lastSongId;

  @override
  void dispose() {
    _hideMiss?.cancel();
    super.dispose();
  }

  /// Restart the linger whenever the track changes, so a new miss gets its own
  /// six seconds rather than inheriting the previous track's expired timer.
  void _noteSong(String? songId) {
    if (songId == _lastSongId) return;
    _lastSongId = songId;
    _hideMiss?.cancel();
    _missExpired = false;
  }

  void _startMissTimer() {
    if (_hideMiss?.isActive ?? false) return;
    _hideMiss = Timer(_kMissLinger, () {
      if (mounted) setState(() => _missExpired = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final listenable = s.qualityListenable;
    if (listenable == null) return const SizedBox.shrink();
    _noteSong(s.currentApiSong?.id);

    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final label = s.currentQualityLabel;
        final lookup = s.losslessLookup;

        // Found beats everything: if mpv says the audio is lossless, the
        // lookup's own opinion is history.
        if (label != null) {
          return _Chip(
            text: widget.compact ? 'HI-RES' : label,
            colors: widget.colors,
            tone: _Tone.good,
            compact: widget.compact,
          );
        }

        switch (lookup) {
          case LosslessLookup.searching:
            return _Chip(
              text: widget.compact ? 'HI-RES…' : 'Finding hi-res…',
              colors: widget.colors,
              tone: _Tone.busy,
              compact: widget.compact,
              spinner: !widget.compact,
            );
          case LosslessLookup.unavailable:
            _startMissTimer();
            if (_missExpired || widget.compact) {
              return const SizedBox.shrink();
            }
            return _Chip(
              text: 'No hi-res for this one · standard quality',
              colors: widget.colors,
              tone: _Tone.quiet,
              compact: false,
            );
          case null:
          case LosslessLookup.found:
            return const SizedBox.shrink();
        }
      },
    );
  }
}

enum _Tone { good, busy, quiet }

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.colors,
    required this.tone,
    required this.compact,
    this.spinner = false,
  });

  final String text;
  final SunohColors colors;
  final _Tone tone;
  final bool compact;
  final bool spinner;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final fg = switch (tone) {
      _Tone.good => c.accent,
      _Tone.busy => c.fgDim,
      _Tone.quiet => c.fgMute,
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Row(
        key: ValueKey('$text$compact'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            SizedBox(
              width: 9,
              height: 9,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: fg),
            )
          else
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          SizedBox(width: compact ? 5 : 7),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SunohType.mono(
              fontSize: compact ? 8.5 : 10,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
