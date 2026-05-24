// 10-band EQ preset library — ported from the user's React Native app at
// /home/ashish/projects/Sunoh (`src/features/equalizer/eqPresets.ts`).
//
// Frequencies: 31, 63, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz. Gains in dB,
// range -12..+12. The RN set is more aggressive (max +10 dB on Deep Impact)
// than the `sunoh_next` port we briefly carried; this was the user's
// canonical curve set and they preferred it.

class EqPreset {
  const EqPreset({
    required this.id,
    required this.name,
    required this.gains,
    required this.description,
  });

  final String id;
  final String name;
  final List<double> gains; // 10 bands, -12..+12 dB
  final String description;
}

const List<EqPreset> kEqPresets = [
  // ── Reference (base / studio / audiophile) ────────────────────────────
  EqPreset(
    id: 'flat',
    name: 'Flat',
    gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    description:
        'Pure, uncolored reference. The truth of your audio, exactly as intended.',
  ),
  EqPreset(
    id: 'studio-monitor',
    name: 'Studio Monitor',
    gains: [1, 0, -1, 1, 2, 3, 2, 3, 4, 2],
    description:
        "Mix engineer's choice. Reveals flaws and beauty equally, honest and unforgiving.",
  ),
  EqPreset(
    id: 'audiophile',
    name: 'Audiophile',
    gains: [3, 2, 1, 2, 0, 1, 3, 5, 6, 4],
    description:
        'High-resolution refinement. Micro-details emerge, soundstage expands, realism heightened.',
  ),
  EqPreset(
    id: 'studio-elite',
    name: 'Studio Elite',
    gains: [2, 1, 0, 2, 1, 3, 4, 6, 7, 5],
    description:
        'Mastering-grade precision with artistic touch. Clinical accuracy meets musical emotion.',
  ),

  // ── Genres ────────────────────────────────────────────────────────────
  EqPreset(
    id: 'rock',
    name: 'Rock',
    gains: [5, 3, -2, -3, -2, 2, 5, 7, 6, 4],
    description:
        'Aggressive punch with scooped mids and soaring highs. Guitar riffs cut through, drums hit hard.',
  ),
  EqPreset(
    id: 'pop',
    name: 'Pop',
    gains: [3, 4, 5, 4, 2, 1, 4, 6, 5, 3],
    description:
        'Radio-ready sparkle with forward vocals and controlled bass. Bright, commercial, addictive.',
  ),
  EqPreset(
    id: 'jazz',
    name: 'Jazz',
    gains: [4, 3, 2, 4, 1, -1, 2, 4, 5, 6],
    description:
        'Warm club intimacy with natural instrument timbre. Brushes shimmer, upright bass resonates deeply.',
  ),
  EqPreset(
    id: 'classical',
    name: 'Classical',
    gains: [2, 1, 0, 1, -2, -1, 2, 5, 7, 8],
    description:
        'Concert hall grandeur with pristine string detail. Wide dynamic range reveals every orchestral layer.',
  ),
  EqPreset(
    id: 'hip-hop',
    name: 'Hip-Hop',
    gains: [8, 6, 3, 1, -1, 0, 2, 4, 6, 5],
    description:
        'Subwoofer-crushing lows with crystalline hi-hats. 808s rumble, vocals sit perfectly in the pocket.',
  ),
  EqPreset(
    id: 'electronic',
    name: 'Electronic',
    gains: [6, 5, 2, 0, 1, 3, 4, 6, 8, 6],
    description:
        'Synthesizer sweetness with extended sub-bass. Laser-sharp highs, pulsing energy throughout.',
  ),

  // ── Frequency focus / enhancement ─────────────────────────────────────
  EqPreset(
    id: 'bass-boost',
    name: 'Bass Boost',
    gains: [9, 7, 4, 2, 0, 0, 1, 2, 1, 0],
    description:
        'Deep rumble without mud. Feel the kick drum in your chest, basslines become visceral.',
  ),
  EqPreset(
    id: 'vocal-clarity',
    name: 'Vocal Clarity',
    gains: [-3, -2, 2, 6, 7, 6, 5, 3, 1, -1],
    description:
        'Every word crystal clear, like the singer is beside you. Perfect for podcasts and storytelling.',
  ),
  EqPreset(
    id: 'treble-boost',
    name: 'Treble Boost',
    gains: [0, 0, 0, 0, 2, 4, 6, 8, 9, 7],
    description:
        'Air and sparkle cascade from above. Cymbals shimmer endlessly, acoustic guitars breathe life.',
  ),
  EqPreset(
    id: 'bass-texture',
    name: 'Bass Texture',
    gains: [7, 6, 5, 3, 1, 0, 2, 3, 4, 3],
    description:
        'Articulate low-end definition. Hear individual bass notes, not just rumble. Musical clarity.',
  ),
  EqPreset(
    id: 'midrange-magic',
    name: 'Midrange Magic',
    gains: [1, 2, 3, 5, 6, 6, 5, 4, 3, 2],
    description:
        'Where music lives and breathes. Guitars sing, pianos resonate, voices connect emotionally.',
  ),
  EqPreset(
    id: 'high-definition',
    name: 'High Definition',
    gains: [2, 2, 3, 4, 5, 6, 7, 8, 8, 6],
    description:
        'Ultra-detailed top-end extension. Hear into the music, revealing layers you never knew existed.',
  ),
  EqPreset(
    id: 'presence-boost',
    name: 'Presence Boost',
    gains: [1, 2, 3, 5, 7, 8, 7, 6, 5, 3],
    description:
        'Intimate forward projection. Vocalists whisper in your ear, instruments surround you closely.',
  ),

  // ── Device optimization ───────────────────────────────────────────────
  EqPreset(
    id: 'headphones',
    name: 'Headphones',
    gains: [4, 3, 2, 3, 4, 4, 3, 5, 6, 5],
    description:
        'Immersive headphone optimization. Compensates for driver proximity, creates natural space.',
  ),
  EqPreset(
    id: 'earbuds',
    name: 'Earbuds',
    gains: [5, 4, 2, 2, 3, 4, 5, 7, 6, 4],
    description:
        'Earbud sweetening with enhanced presence. Small drivers deliver big sound, fatigue-free.',
  ),
  EqPreset(
    id: 'speakers',
    name: 'Speakers',
    gains: [3, 2, 2, 4, 3, 2, 3, 5, 6, 4],
    description:
        'Room-aware tuning for optimal speaker response. Balances reflections, tames resonances.',
  ),

  // ── Moods / situations ────────────────────────────────────────────────
  EqPreset(
    id: 'live-concert',
    name: 'Live Concert',
    gains: [4, 3, 2, 3, 4, 3, 6, 8, 7, 5],
    description:
        'Front-row energy without the crowd. Stadium reverb, amplifier grit, real performance presence.',
  ),
  EqPreset(
    id: 'midnight-mode',
    name: 'Midnight Mode',
    gains: [-4, -2, 2, 5, 4, 4, 3, 2, 0, -2],
    description:
        'Whisper-quiet dynamics for late hours. Explosions tamed, dialogue clear, neighbors sleeping.',
  ),
  EqPreset(
    id: 'workout',
    name: 'Workout',
    gains: [7, 6, 4, 2, 3, 4, 6, 5, 4, 3],
    description:
        'Adrenaline-pumping energy surge. Motivating punch pushes you harder, rhythm drives you forward.',
  ),
  EqPreset(
    id: 'lounge-chill',
    name: 'Lounge Chill',
    gains: [4, 4, 3, 3, 2, 2, 3, 4, 5, 4],
    description:
        'Relaxed sophistication for laid-back moments. Smooth jazz, downtempo, evening cocktails.',
  ),
  EqPreset(
    id: 'energy-surge',
    name: 'Energy Surge',
    gains: [6, 6, 5, 3, 4, 5, 7, 6, 5, 4],
    description:
        'High-octane motivation boost. Driving rhythm section propels you forward with unstoppable momentum.',
  ),

  // ── Signature ─────────────────────────────────────────────────────────
  EqPreset(
    id: 'warm-analog',
    name: 'Warm Analog',
    gains: [5, 4, 2, 2, 0, 1, 3, 5, 4, 2],
    description:
        'Vintage tape saturation warmth. Nostalgic tube glow, musical harmonic richness throughout.',
  ),
  EqPreset(
    id: 'crystal-clear',
    name: 'Crystal Clear',
    gains: [0, 1, 2, 4, 6, 7, 8, 7, 6, 5],
    description:
        'Transparent brilliance from top to bottom. Resolution so high, you hear the room, the breath.',
  ),
  EqPreset(
    id: 'rich-full',
    name: 'Rich & Full',
    gains: [5, 4, 3, 3, 4, 5, 4, 6, 5, 3],
    description:
        'Luxurious body and weight. Every frequency dense with harmonic content, musically satisfying.',
  ),
  EqPreset(
    id: 'atmospheric',
    name: 'Atmospheric',
    gains: [2, 1, 0, 1, 2, 3, 6, 8, 9, 7],
    description:
        'Ethereal soundscape expansion. Creates three-dimensional space, perfect for ambient immersion.',
  ),
  EqPreset(
    id: 'vibrant-pop',
    name: 'Vibrant Pop',
    gains: [4, 5, 6, 5, 3, 4, 6, 8, 7, 5],
    description:
        'Technicolor audio excitement. Pop hooks explode with energy, infectious and irresistible.',
  ),
  EqPreset(
    id: 'deep-impact',
    name: 'Deep Impact',
    gains: [10, 8, 5, 3, 1, 2, 4, 6, 7, 6],
    description:
        'Cinematic low-frequency authority. Explosions shake foundations, thunder rolls with power.',
  ),
  EqPreset(
    id: 'silk-smooth',
    name: 'Silk Smooth',
    gains: [3, 3, 2, 3, 4, 4, 3, 2, 0, -1],
    description:
        'Velvet-soft refinement removes all harshness. Hours of listening without a hint of fatigue.',
  ),
  EqPreset(
    id: 'balanced-premium',
    name: 'Balanced Premium',
    gains: [4, 3, 3, 4, 3, 4, 5, 6, 6, 4],
    description:
        'Sophisticated all-rounder with refined taste. Nothing exaggerated, everything enhanced perfectly.',
  ),
  EqPreset(
    id: 'dynamic-punch',
    name: 'Dynamic Punch',
    gains: [6, 5, 3, 2, 2, 3, 5, 7, 6, 4],
    description:
        'Explosive transient impact. Drums crack with authority, attacks are lightning-fast and precise.',
  ),
];

/// Lookup by id.
EqPreset? eqPresetById(String id) {
  for (final p in kEqPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// Category groupings for the picker UI. Matches the RN reference's
/// PRESET_CATEGORIES with short Flutter-side display names.
const Map<String, List<String>> kEqPresetCategories = {
  'Reference': ['flat', 'studio-monitor', 'audiophile', 'studio-elite'],
  'Genres': ['rock', 'pop', 'jazz', 'classical', 'hip-hop', 'electronic'],
  'Focus': [
    'bass-boost',
    'vocal-clarity',
    'treble-boost',
    'bass-texture',
    'midrange-magic',
    'high-definition',
    'presence-boost',
  ],
  'Devices': ['headphones', 'earbuds', 'speakers'],
  'Moods': [
    'live-concert',
    'midnight-mode',
    'workout',
    'lounge-chill',
    'energy-surge',
  ],
  'Signature': [
    'warm-analog',
    'crystal-clear',
    'rich-full',
    'atmospheric',
    'vibrant-pop',
    'deep-impact',
    'silk-smooth',
    'balanced-premium',
    'dynamic-punch',
  ],
};
