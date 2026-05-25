// Deterministic, CSS-free generated album art — ported from the prototype's
// art.jsx. Each id hashes into a palette + shape arrangement, drawn on a canvas.
// No external images.

import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'ui.dart';

// A 96×96 grain tile, rasterized once and reused as a repeating shader across
// every cover. Replaces a per-pixel drawCircle loop that was hammering raster.
ui.Image? _grainTile;
ui.Image _grainImage() {
  if (_grainTile != null) return _grainTile!;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.05);
  for (double y = 0; y < 96; y += 3) {
    for (double x = 0; x < 96; x += 3) {
      canvas.drawCircle(Offset(x, y), 0.5, paint);
    }
  }
  _grainTile = recorder.endRecording().toImageSync(96, 96);
  return _grainTile!;
}

// FNV-1a, kept bit-identical to the JS prototype (unsigned 32-bit).
int _hash(String s) {
  int h = 2166136261;
  for (var i = 0; i < s.length; i++) {
    h ^= s.codeUnitAt(i);
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h & 0xFFFFFFFF;
}

// Palettes tuned to feel like premium editorial covers — muted, low-chroma.
// Each is [bg, accent, tint].
const List<List<Color>> _palettes = [
  [Color(0xFF1F2418), Color(0xFFCAA66B), Color(0xFFE8E4D8)], // moss + brass
  [Color(0xFF2C1B16), Color(0xFFD97757), Color(0xFFF1E8DF)], // ember + cream
  [Color(0xFF0F1820), Color(0xFF7FB3D5), Color(0xFFE6F0F6)], // steel + ice
  [Color(0xFF1A1A1A), Color(0xFFD8D0C4), Color(0xFFF7F3EB)], // bone
  [Color(0xFF221A2B), Color(0xFFA78BD1), Color(0xFFECE4F3)], // violet
  [Color(0xFF15201B), Color(0xFF82B07B), Color(0xFFE6EFE7)], // sage
  [Color(0xFF2A1E15), Color(0xFFB88654), Color(0xFFF1E5D3)], // sienna
  [Color(0xFF0F1414), Color(0xFF5B9B95), Color(0xFFDBE9E7)], // teal stone
  [Color(0xFF1C1410), Color(0xFF8C5A3E), Color(0xFFEAD7C6)], // umber
  [Color(0xFF222018), Color(0xFFC8B88A), Color(0xFFEFE9D8)], // sand
  [Color(0xFF0E1216), Color(0xFF3C5B78), Color(0xFFD6E3EF)], // midnight blue
  [Color(0xFF2B1C1C), Color(0xFFA13F3F), Color(0xFFECD7D7)], // claret
];

const List<String> _shapes = [
  'disc', 'split', 'arc', 'bars', 'beam', 'orbit', 'panes', 'wedge',
];

class ArtData {
  ArtData(this.bg, this.accent, this.tint, this.shape, this.angle, this.seed);
  final Color bg;
  final Color accent;
  final Color tint;
  final String shape;
  final int angle;
  final double seed;
}

ArtData artFor(String id) {
  final h = _hash(id.isEmpty ? 'x' : id);
  final palette = _palettes[h % _palettes.length];
  final shape = _shapes[(h >> 4) % _shapes.length];
  final angle = (h >> 8) % 360;
  final seed = ((h >> 12) % 1000) / 1000.0;
  return ArtData(palette[0], palette[1], palette[2], shape, angle, seed);
}

/// Accent color of an artwork — used for the album-tinted theme.
Color artAccent(String id) => artFor(id).accent;

Color _a(Color c, int alpha255) => c.withValues(alpha: alpha255 / 255.0);

/// A square (or sized) generated cover. [radius] controls corner rounding;
/// pass a very large value for circular (artist) art.
class SunohArt extends StatelessWidget {
  const SunohArt({
    super.key,
    required this.id,
    this.size,
    this.width,
    this.height,
    this.radius = 8,
    this.label,
    this.shadow = true,
    this.imageUrl,
  });

  final String id;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final String? label;
  final bool shadow;

  /// When provided, render the network image inside the squircle. The
  /// deterministic painted art is shown while the image loads (and as a
  /// fallback if it fails) — so the placeholder still feels of-a-piece.
  final String? imageUrl;

  Widget _innerArt() => CustomPaint(
        painter: _ArtPainter(artFor(id), label),
        isComplex: true,
        willChange: false,
        child: const SizedBox.expand(),
      );

  @override
  Widget build(BuildContext context) {
    final w = width ?? size ?? 120;
    final h = height ?? size ?? 120;
    final url = imageUrl;

    // Tier the decode size so different display sizes of the same URL share
    // a single decoded bitmap. Without this, navigating from a 148-px home
    // card to a 200-px detail hero would re-decode (the same URL at a new
    // size = a new memCache entry), making the image fade in fresh on every
    // nav — exactly the "image re-renders weird" symptom.
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 2.0;
    final largest = (w.isFinite && h.isFinite ? (w > h ? w : h) : 0) * dpr;
    final cacheTier = largest <= 192
        ? 192
        : largest <= 384
            ? 384
            : 720;

    return RepaintBoundary(
      child: Container(
        width: w.isFinite ? w : null,
        height: h,
        decoration: squircleDecoration(
          radius: radius,
          shadows: shadow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: squircleClip(
          radius: radius,
          child: url == null || url.isEmpty
              ? _innerArt()
              // Bypass CachedNetworkImage entirely (its placeholder fires for
              // ≥1 frame even on memory-cache hits → the "flicker on nav"
              // symptom). Use raw Image with CachedNetworkImageProvider so
              // we own the placeholder logic via frameBuilder:
              //   - `wasSynchronouslyLoaded: true` → bitmap was in Flutter's
              //     ImageCache and resolved this frame → show it immediately,
              //     no placeholder, no flicker.
              //   - `frame != null` → first decoded frame is ready → show it.
              //   - otherwise → still loading from disk/net → painted art bridges.
              // No fade animations — direct swap, which "looks instant" when
              // cached and "loads naturally" when cold.
              : Image(
                  image: ResizeImage(
                    CachedNetworkImageProvider(url),
                    width: cacheTier,
                    height: cacheTier,
                    policy: ResizeImagePolicy.fit,
                  ),
                  fit: BoxFit.cover,
                  // medium = trilinear with mipmaps; low = plain bilinear.
                  // The CDN tops out at 500×500 so the hero (and on hi-DPR
                  // phones, even mid-size tiles) ends up upscaling slightly
                  // — bilinear made that read as soft/blocky. Mipmaps are
                  // worth the small perf cost for product imagery.
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, wasSyncLoaded) {
                    if (wasSyncLoaded || frame != null) return child;
                    return _innerArt();
                  },
                  errorBuilder: (_, _, _) => _innerArt(),
                ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.d, this.label);
  final ArtData d;
  final String? label;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final rect = Offset.zero & size;
    final s = math.min(w, h);

    // base fill
    canvas.drawRect(rect, Paint()..color = d.bg);

    // base soft gradient wash
    final wash = Paint()
      ..shader = RadialGradient(
        center: Alignment((20 + d.seed * 60) / 50 - 1, (10 + d.seed * 30) / 50 - 1),
        radius: 1.0,
        colors: [_a(d.accent, 0x40), _a(d.accent, 0x00)],
        stops: const [0.0, 0.6],
      ).createShader(rect);
    canvas.drawRect(rect, wash);

    switch (d.shape) {
      case 'disc':
        _disc(canvas, w, h, s);
        break;
      case 'split':
        _split(canvas, w, h, rect);
        break;
      case 'arc':
        _arc(canvas, w, h);
        break;
      case 'bars':
        _bars(canvas, w, h);
        break;
      case 'beam':
        _beam(canvas, rect);
        break;
      case 'orbit':
        _orbit(canvas, w, h, s);
        break;
      case 'panes':
        _panes(canvas, w, h);
        break;
      case 'wedge':
      default:
        _wedge(canvas, rect, w, h);
    }

    _grain(canvas, w, h);
    _label(canvas, w, h, s);
  }

  void _disc(Canvas c, double w, double h, double s) {
    final center = Offset(0.5 * w, 0.52 * h);
    final rx = 0.32 * w, ry = 0.32 * h;
    c.drawOval(Rect.fromCenter(center: center, width: rx * 2, height: ry * 2),
        Paint()..color = d.accent);
    final ring = s * 0.012;
    c.drawOval(
      Rect.fromCenter(center: center, width: rx * 2 - ring, height: ry * 2 - ring),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ring
        ..color = _a(d.tint, 0x33),
    );
  }

  void _split(Canvas c, double w, double h, Rect rect) {
    final rad = d.angle * math.pi / 180;
    // CSS gradient angle: 0deg points up; convert to a direction vector.
    final dx = math.sin(rad), dy = -math.cos(rad);
    final begin = Alignment(-dx, -dy), end = Alignment(dx, dy);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: begin,
        end: end,
        colors: [d.accent, d.accent, _a(d.accent, 0)],
        stops: const [0.0, 0.5, 0.501],
      ).createShader(rect);
    c.drawRect(rect, paint);
    // centered tint disc, overlay-ish
    c.drawOval(
      Rect.fromCenter(center: Offset(w / 2, h / 2), width: 0.38 * w, height: 0.38 * h),
      Paint()..color = _a(d.tint, 0x66),
    );
  }

  void _arc(Canvas c, double w, double h) {
    // huge circle rising from the bottom-left
    final big = Rect.fromLTWH(-0.30 * w, 0.30 * h, 1.60 * w, 1.60 * h);
    c.drawOval(big, Paint()..color = d.accent);
    final small = Rect.fromLTWH(
        w - 0.12 * w - 0.40 * w, 0.12 * h, 0.40 * w, 0.40 * h);
    c.drawOval(small, Paint()..color = _a(d.tint, 0xD8));
  }

  void _bars(Canvas c, double w, double h) {
    const heights = [0.4, 0.7, 0.55, 0.92, 0.3, 0.65];
    final left = 0.12 * w, right = 0.12 * w, top = 0.15 * h, bottom = 0.15 * h;
    final innerW = w - left - right, innerH = h - top - bottom;
    final gap = 0.06 * innerW;
    final barW = (innerW - gap * (heights.length - 1)) / heights.length;
    for (var i = 0; i < heights.length; i++) {
      final bh = heights[i] * innerH;
      final x = left + i * (barW + gap);
      final y = top + (innerH - bh);
      final paint = Paint()
        ..color = i.isOdd ? d.accent : _a(d.tint, 0x99);
      c.drawRect(Rect.fromLTWH(x, y, barW, bh), paint);
    }
  }

  void _beam(Canvas c, Rect rect) {
    final rad = d.angle * math.pi / 180;
    final dx = math.sin(rad), dy = -math.cos(rad);
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-dx, -dy),
          end: Alignment(dx, dy),
          colors: [_a(d.accent, 0), _a(d.accent, 0xCC), _a(d.accent, 0xCC), _a(d.accent, 0)],
          stops: const [0.0, 0.4, 0.6, 1.0],
        ).createShader(rect),
    );
    final rad2 = (d.angle + 90) * math.pi / 180;
    final dx2 = math.sin(rad2), dy2 = -math.cos(rad2);
    c.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(-dx2, -dy2),
          end: Alignment(dx2, dy2),
          colors: [_a(d.tint, 0x22), _a(d.tint, 0)],
          stops: const [0.0, 0.5],
        ).createShader(rect),
    );
  }

  void _orbit(Canvas c, double w, double h, double s) {
    final sw = math.max(1.0, s * 0.008);
    void ring(double frac, Color col) {
      final inset = (1 - frac) / 2;
      c.drawOval(
        Rect.fromLTWH(inset * w, inset * h, frac * w, frac * h),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..color = col,
      );
    }

    ring(0.85, _a(d.accent, 0x55));
    ring(0.55, _a(d.accent, 0x88));
    c.drawOval(
      Rect.fromLTWH(0.70 * w, 0.14 * h, 0.14 * w, 0.14 * h),
      Paint()..color = d.accent,
    );
  }

  void _panes(Canvas c, double w, double h) {
    final inset = 0.12;
    final gx = inset * w, gy = inset * h;
    final innerW = w - 2 * gx, innerH = h - 2 * gy;
    final gap = 0.04 * innerW;
    final cw = (innerW - gap) / 2, ch = (innerH - gap) / 2;
    final colors = [d.accent, _a(d.tint, 0x88), _a(d.tint, 0x33), _a(d.accent, 0xAA)];
    final cells = [
      Rect.fromLTWH(gx, gy, cw, ch),
      Rect.fromLTWH(gx + cw + gap, gy, cw, ch),
      Rect.fromLTWH(gx, gy + ch + gap, cw, ch),
      Rect.fromLTWH(gx + cw + gap, gy + ch + gap, cw, ch),
    ];
    for (var i = 0; i < 4; i++) {
      c.drawRRect(
        RRect.fromRectAndRadius(cells[i], const Radius.circular(2)),
        Paint()..color = colors[i],
      );
    }
  }

  void _wedge(Canvas c, Rect rect, double w, double h) {
    final rad = d.angle * math.pi / 180;
    c.drawRect(
      rect,
      Paint()
        ..shader = SweepGradient(
          center: const Alignment(-0.4, 0.4), // 30% 70%
          colors: [d.accent, d.bg, _a(d.accent, 0x88), d.bg],
          stops: const [0.0, 120 / 360, 240 / 360, 1.0],
          transform: GradientRotation(rad),
        ).createShader(rect),
    );
    c.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(0.4, -0.4), // 70% 30%
          radius: 0.6,
          colors: [_a(d.tint, 0x33), _a(d.tint, 0)],
          stops: const [0.0, 1.0],
        ).createShader(rect),
    );
  }

  void _grain(Canvas c, double w, double h) {
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.ImageShader(
          _grainImage(),
          ui.TileMode.repeated,
          ui.TileMode.repeated,
          Matrix4.identity().storage,
        ),
    );
  }

  void _label(Canvas c, double w, double h, double s) {
    if (label == null) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: math.max(7, s * 0.07),
          letterSpacing: 0.5,
          color: _a(d.tint, 0xB3),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(w * 0.08, h - s * 0.08 - tp.height));
  }

  @override
  bool shouldRepaint(covariant _ArtPainter old) =>
      old.d.shape != d.shape || old.label != label;
}
