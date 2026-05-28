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
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

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
    final accent = s.resolvedAccent;
    final inFlight = s.spotifyImport.status == SpotifyImportStatus.fetching;
    return ColoredBox(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 14, 4),
              child: Row(
                children: [
                  IconBtn(
                    icon: SolarIconsOutline.altArrowLeft,
                    color: c.fg,
                    size: 22,
                    onTap: () => context.pop(),
                  ),
                  const SizedBox(width: 6),
                  Text('Import from Spotify',
                      style: SunohType.heading(
                          fontSize: 22,
                          color: c.fg,
                          letterSpacing: -0.3)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Text(
                'Paste a public Spotify playlist URL. We’ll find the best Saavn match for each track and save it as a new playlist in your library.',
                style: SunohType.sans(
                    fontSize: 13, color: c.fgMute, height: 1.4),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Container(
                decoration: squircleDecoration(
                  radius: 16,
                  color: c.surface,
                  borderColor: c.line,
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 0),
                      child: Row(
                        children: [
                          Icon(SolarIconsOutline.link,
                              size: 16, color: c.fgDim),
                          const SizedBox(width: 8),
                          Text('Playlist URL',
                              style: eyebrowStyle(c, accent: c.fgMute)),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 12, 4),
                      child: TextField(
                        controller: _ctl,
                        autofocus: false,
                        enabled: !inFlight && !_busy,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: SunohType.sans(fontSize: 14, color: c.fg),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: InputBorder.none,
                          hintText:
                              'https://open.spotify.com/playlist/…',
                          hintStyle: SunohType.sans(
                              fontSize: 14, color: c.fgMute),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    Divider(color: c.line.withValues(alpha: 0.5), height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: inFlight || _busy ? null : _onPaste,
                            icon: Icon(SolarIconsOutline.clipboardText,
                                size: 14, color: c.fg),
                            label: Text('Paste',
                                style: SunohType.sans(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: c.fg)),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          if (_ctl.text.isNotEmpty)
                            TextButton.icon(
                              onPressed: inFlight || _busy
                                  ? null
                                  : () => setState(() => _ctl.clear()),
                              icon: Icon(SolarIconsOutline.eraser,
                                  size: 14, color: c.fgDim),
                              label: Text('Clear',
                                  style: SunohType.sans(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: c.fgDim)),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap:
                      (inFlight || _busy || !_looksLikeSpotifyUrl(_ctl.text))
                          ? null
                          : _onImport,
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: squircleDecoration(
                      radius: 14,
                      color: (_looksLikeSpotifyUrl(_ctl.text) &&
                              !inFlight &&
                              !_busy)
                          ? accent
                          : accent.withValues(alpha: 0.35),
                    ),
                    child: Text(
                      inFlight ? 'Import in progress…' : 'Import',
                      style: SunohType.heading(
                          fontSize: 15,
                          color: Colors.white,
                          letterSpacing: -0.1),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TipsBlock(colors: c),
            ),
          ],
        ),
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
    final tips = [
      'Works on any public Spotify playlist — yours or anyone else’s.',
      'Imports take ~1–2 minutes, depending on playlist size. You can keep using the app while it runs.',
      'Tracks that don’t exist on Saavn (e.g. region-locked indie) are skipped.',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('TIPS',
            style: SunohType.mono(
                fontSize: 9, color: c.fgMute, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    width: 3,
                    height: 3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.fgDim,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t,
                    style: SunohType.sans(
                        fontSize: 12, color: c.fgMute, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Forgiving eyebrow style accessor — the existing `eyebrow()` builder
/// renders a Text widget, but here we want just the style for use inside
/// a Row that has its own widgets.
TextStyle eyebrowStyle(SunohColors c, {Color? accent}) =>
    SunohType.mono(
      fontSize: 9,
      color: accent ?? c.fgMute,
      letterSpacing: 1.4,
    );
