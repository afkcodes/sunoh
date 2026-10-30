// Spotify playlist importer — entry screen.
//
// Tiny, focused: a single URL input, a Paste affordance, and an
// Import CTA. Once Import is tapped, the screen pops immediately —
// the actual work is held by AppState (`importSpotifyPlaylist`) and
// surfaced everywhere via [SpotifyImportBanner]. So the user is free
// to keep using the app while the ~80 s scrape + match runs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:remixicon/remixicon.dart';

import '../providers/app_state_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'pill_button.dart';
import 'sub_page_bar.dart';

class SpotifyImportScreen extends ConsumerStatefulWidget {
  const SpotifyImportScreen({super.key});
  @override
  ConsumerState<SpotifyImportScreen> createState() =>
      _SpotifyImportScreenState();
}

class _SpotifyImportScreenState extends ConsumerState<SpotifyImportScreen> {
  final TextEditingController _ctl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  bool _looksLikeSpotifyUrl(String s) {
    final t = s.trim();
    if (t.isEmpty) return false;
    return t.contains('spotify.com/playlist/') ||
        t.startsWith('spotify:playlist:');
  }

  Future<void> _onPaste() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() => _ctl.text = text);
    _ctl.selection = TextSelection.collapsed(offset: text.length);
  }

  Future<void> _onImport() async {
    final url = _ctl.text.trim();
    if (!_looksLikeSpotifyUrl(url)) {
      ref.read(appStateProvider).flashToast('Paste a Spotify playlist URL');
      return;
    }
    setState(() => _busy = true);
    // Fire-and-forget — AppState owns the long-running future. We just
    // need the call to start before we pop, so the banner has the
    // `fetching` state to render.
    final s = ref.read(appStateProvider);
    unawaitedImport(s.importSpotifyPlaylist(url));
    if (mounted) {
      s.flashToast('Importing — we’ll let you know when it’s done');
      context.pop();
    }
  }

  /// Local equivalent of `unawaited`; avoids importing dart:async at the
  /// top of every screen that needs it.
  void unawaitedImport(Future<void> _) {}

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final inFlight = s.spotifyImport.status == SpotifyImportStatus.fetching;
    final locked = inFlight || _busy;
    final ready = !locked && _looksLikeSpotifyUrl(_ctl.text);
    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          SubPageBar(title: 'Import from Spotify', colors: c),
          Expanded(
            // Scrolls so the keyboard can never push the Import button off a
            // screen it has no way back onto.
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 140),
              children: [
                FadeSlideIn(
                  child: Text(
                    'Paste a public Spotify playlist URL. We’ll find the best Saavn match for each track and save it as a new playlist in your library.',
                    style: SunohType.sans(
                      fontSize: 14,
                      color: c.fgDim,
                      height: 1.45,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                FadeSlideIn(index: 1, child: _urlCard(c, locked)),
                const SizedBox(height: 12),
                FadeSlideIn(
                  index: 2,
                  // Not ready is the neutral pill, not a faded accent:
                  // onAccent on a 35% accent is dark on dark, and hid the label.
                  child: PillButton(
                    label: inFlight ? 'Import in progress…' : 'Import',
                    colors: c,
                    primary: true,
                    height: 48,
                    expand: true,
                    onTap: ready ? _onImport : null,
                  ),
                ),
                const SizedBox(height: 24),
                FadeSlideIn(index: 3, child: _TipsBlock(colors: c)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The URL field on a card, with Paste and Clear under it as small pills.
  /// No rule between field and pills: spacing separates them, as on every
  /// other card.
  Widget _urlCard(SunohColors c, bool locked) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(RemixIcons.link, size: 16, color: c.fgDim),
              const SizedBox(width: 8),
              Text(
                'Playlist URL',
                style: SunohType.sans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: c.fgDim,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ctl,
            autofocus: false,
            enabled: !locked,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            style: SunohType.sans(fontSize: 15, color: c.fg),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 6),
              border: InputBorder.none,
              hintText: 'https://open.spotify.com/playlist/…',
              hintStyle: SunohType.sans(fontSize: 15, color: c.fgMute),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PillButton(
                label: 'Paste',
                icon: RemixIcons.clipboard_line,
                colors: c,
                height: 32,
                onTap: locked ? null : _onPaste,
              ),
              if (_ctl.text.isNotEmpty) ...[
                const SizedBox(width: 8),
                PillButton(
                  label: 'Clear',
                  icon: RemixIcons.eraser_line,
                  colors: c,
                  height: 32,
                  onTap: locked ? null : () => setState(_ctl.clear),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TipsBlock extends StatelessWidget {
  const _TipsBlock({required this.colors});
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final c = colors;
    const tips = [
      'Works on any public Spotify playlist — yours or anyone else’s.',
      'Imports take ~1–2 minutes, depending on playlist size. You can keep using the app while it runs.',
      'Tracks that don’t exist on Saavn (e.g. region-locked indie) are skipped.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow('TIPS', c.fgMute, size: 10.5, letterSpacing: 0.84),
        const SizedBox(height: 8),
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.fgMute,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t,
                    style: SunohType.sans(
                      fontSize: 13,
                      color: c.fgDim,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
