// Radio tab — on-air hero, the FM dial centerpiece, saved stations, categories.
// Ported from radio.jsx.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../router/router.dart';

import '../data/catalog.dart';
import '../data/models.dart';
import '../theme/tokens.dart';
import '../widgets/album_art.dart';
import '../widgets/playing_bars.dart';
import '../widgets/ui.dart';

class RadioTab extends StatefulWidget {
  const RadioTab({super.key, required this.colors});
  final SunohColors colors;

  @override
  State<RadioTab> createState() => _RadioTabState();
}

class _RadioTabState extends State<RadioTab> {
  double freq = 92.3;

  Station get closest => kStations.reduce((best, s) =>
      (s.freqValue - freq).abs() < (best.freqValue - freq).abs() ? s : best);

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final cl = closest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // on-air hero
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: squircleClip(
            radius: 18,
            child: Container(
              decoration: squircleDecoration(radius: 18, color: c.surface, borderColor: c.line),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(-1, -1),
                          radius: 1.1,
                          colors: [
                            artAccent(cl.id).withValues(alpha: 0.27),
                            artAccent(cl.id).withValues(alpha: 0),
                          ],
                          stops: const [0, 0.6],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFF3C3C).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: const Color(0xFFFF5050).withValues(alpha: 0.4),
                                    width: 0.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const PlayingBars(color: Color(0xFFFF7575), size: 12, count: 4),
                                  const SizedBox(width: 8),
                                  eyebrow('ON AIR', const Color(0xFFFF7575),
                                      size: 10, letterSpacing: 1.2),
                                ],
                              ),
                            ),
                            eyebrow('${cl.listeners} listening', c.fgMute,
                                size: 10, letterSpacing: 1.2),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            SunohArt(id: cl.id, size: 64, radius: 8),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(cl.name,
                                      style: SunohType.heading(
                                          fontSize: 22, color: c.fg, height: 1.1, letterSpacing: -0.2)),
                                  const SizedBox(height: 2),
                                  Text(cl.tag,
                                      style: SunohType.sans(fontSize: 12, color: c.fgDim)),
                                  const SizedBox(height: 4),
                                  eyebrow(cl.live, c.fgMute, size: 10, letterSpacing: 0.4),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PlayPill(
                              accent: c.accent,
                              onTap: () => context.openRef(DetailRef('station', cl.id)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 40),

        // dial
        Padding(
          padding: const EdgeInsets.only(left: 20, bottom: 8),
          child: eyebrow('TUNE', c.fgMute),
        ),
        RadioDial(
          colors: c,
          currentFreq: freq,
          onTune: (f) => setState(() => freq = f),
        ),
        const SizedBox(height: 40),

        // saved stations
        SectionHeader(title: 'Saved stations',  colors: c),
        for (final st in kStations)
          GestureDetector(
            onTap: () => setState(() => freq = st.freqValue),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  SunohArt(id: st.id, size: 44, radius: 6),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(st.name,
                                style: SunohType.sans(
                                    fontSize: 14, fontWeight: FontWeight.w500, color: c.fg)),
                            const SizedBox(width: 8),
                            Text(st.freq,
                                style: SunohType.mono(
                                    fontSize: 10, color: c.fgMute, letterSpacing: 0.4)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('${st.tag} · ${st.listeners} listening',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SunohType.sans(fontSize: 11.5, color: c.fgMute)),
                      ],
                    ),
                  ),
                  if ((st.freqValue - freq).abs() < 0.2)
                    PlayingBars(color: c.accent, size: 14, count: 4),
                ],
              ),
            ),
          ),
        const SizedBox(height: 40),

        // categories
        SectionHeader(title: 'By kind',  colors: c),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 171 / 78,
            children: [
              _CategoryTile('Music', '24 stations', const [Color(0xFF2C1B16), Color(0xFFD97757)]),
              _CategoryTile('Talk', '18 stations', const [Color(0xFF0F1820), Color(0xFF7FB3D5)]),
              _CategoryTile('News', '12 stations', const [Color(0xFF1C1410), Color(0xFF8C5A3E)]),
              _CategoryTile('Sports', '8 stations', const [Color(0xFF1F2418), Color(0xFFCAA66B)]),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}

class _PlayPill extends StatelessWidget {
  const _PlayPill({required this.accent, required this.onTap});
  final Color accent;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: accent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 18, offset: const Offset(0, 6)),
          ],
        ),
        child: const Icon(PhosphorIconsFill.play, size: 22, color: Color(0xFF0B0B0D)),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile(this.label, this.sub, this.gradient);
  final String label;
  final String sub;
  final List<Color> gradient;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: squircleDecoration(
        radius: 12,
        gradient: LinearGradient(
            colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: SunohType.heading(fontSize: 19, color: Colors.white, letterSpacing: -0.2)),
          eyebrow(sub, Colors.white.withValues(alpha: 0.6), size: 9, letterSpacing: 1.2),
        ],
      ),
    );
  }
}

// ── The FM dial — horizontal scrollable tick strip with a fixed center pointer
class RadioDial extends StatefulWidget {
  const RadioDial({
    super.key,
    required this.colors,
    required this.currentFreq,
    required this.onTune,
  });
  final SunohColors colors;
  final double currentFreq;
  final ValueChanged<double> onTune;

  @override
  State<RadioDial> createState() => _RadioDialState();
}

class _RadioDialState extends State<RadioDial> {
  static const double minF = 87, maxF = 108, pxPerUnit = 60;
  final controller = ScrollController();
  double _viewport = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      _viewport = controller.position.viewportDimension;
      final offset = (widget.currentFreq - minF) * pxPerUnit;
      controller.jumpTo((offset).clamp(0, controller.position.maxScrollExtent));
      setState(() {});
    });
    controller.addListener(_onScroll);
  }

  void _onScroll() {
    final c = controller.offset + _viewport / 2;
    final freq = minF + (c - _viewport / 2) / pxPerUnit;
    final snapped = (freq * 10).round() / 10;
    if ((snapped - widget.currentFreq).abs() > 0.05 &&
        snapped >= minF &&
        snapped <= maxF) {
      widget.onTune(snapped);
    }
  }

  @override
  void didUpdateWidget(RadioDial old) {
    super.didUpdateWidget(old);
    // When tuned externally (tapping a saved station), recenter.
    if (old.currentFreq != widget.currentFreq && controller.hasClients) {
      final target = (widget.currentFreq - minF) * pxPerUnit;
      if ((controller.offset - target).abs() > 2) {
        controller.animateTo(
          target.clamp(0, controller.position.maxScrollExtent),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final ticks = <double>[];
    for (var f = (minF * 10).round(); f <= (maxF * 10).round(); f++) {
      ticks.add(f / 10);
    }
    return Column(
      children: [
        // readout
        Column(
          children: [
            eyebrow('FM · LIVE', c.fgMute),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                text: widget.currentFreq.toStringAsFixed(1),
                style: SunohType.mono(
                    fontSize: 40,
                    fontWeight: FontWeight.w500,
                    color: c.fg,
                    letterSpacing: -1,
                    height: 1),
                children: [
                  TextSpan(
                    text: ' MHz',
                    style: SunohType.mono(fontSize: 18, color: c.fgMute),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        // dial
        SizedBox(
          height: 84,
          child: Stack(
            children: [
              LayoutBuilder(builder: (context, box) {
                final half = box.maxWidth / 2;
                return SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: (maxF - minF) * pxPerUnit + box.maxWidth,
                    height: 84,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final f in ticks)
                          Positioned(
                            left: half + (f - minF) * pxPerUnit,
                            top: 14,
                            child: _Tick(f: f, colors: c),
                          ),
                        for (final st in kStations)
                          Positioned(
                            left: half + (st.freqValue - minF) * pxPerUnit,
                            top: 0,
                            child: _StationPin(
                              station: st,
                              close: (st.freqValue - widget.currentFreq).abs() < 0.2,
                              colors: c,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
              // gradient masks
              Positioned(
                left: 0, top: 0, bottom: 0, width: 40,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c.bg, c.bg.withValues(alpha: 0)]),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 0, top: 0, bottom: 0, width: 40,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                          colors: [c.bg, c.bg.withValues(alpha: 0)],
                          begin: Alignment.centerRight,
                          end: Alignment.centerLeft),
                    ),
                  ),
                ),
              ),
              // center pointer
              Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  child: Container(width: 2, color: c.accent),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: IgnorePointer(
                  child: Transform.translate(
                    offset: const Offset(0, -4),
                    child: Transform.rotate(
                      angle: 0.785398,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                            color: c.accent, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
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

class _Tick extends StatelessWidget {
  const _Tick({required this.f, required this.colors});
  final double f;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final isMajor = (f - f.round()).abs() < 0.05;
    return Column(
      children: [
        Container(
          width: 1,
          height: isMajor ? 30 : 14,
          color: colors.fgMute.withValues(alpha: isMajor ? 0.6 : 0.25),
        ),
        if (isMajor) ...[
          const SizedBox(height: 6),
          Text(f.round().toString(),
              style: SunohType.mono(fontSize: 10, color: colors.fgMute, letterSpacing: 0.5)),
        ],
      ],
    );
  }
}

class _StationPin extends StatelessWidget {
  const _StationPin({required this.station, required this.close, required this.colors});
  final Station station;
  final bool close;
  final SunohColors colors;
  @override
  Widget build(BuildContext context) {
    final col = close ? colors.accent : colors.fgDim;
    return Column(
      children: [
        Transform.translate(
          offset: const Offset(-2, 0),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: col, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(height: 2),
        Transform.translate(
          offset: const Offset(-10, 0),
          child: Text(station.name.split(' ').first.toUpperCase(),
              style: SunohType.mono(
                  fontSize: 8,
                  color: close ? colors.accent : colors.fgMute,
                  letterSpacing: 0.4)),
        ),
      ],
    );
  }
}
