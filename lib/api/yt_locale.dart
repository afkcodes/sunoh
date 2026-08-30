// Which region and interface language YouTube Music requests are made for.
//
// InnerTube takes two locale fields and they do different jobs:
//
//   gl  region. Shifts the editorial rows on home (gl=IN returns "Old
//       School Romance" where gl=US returns "Easy Evenings"). Measured
//       caveat: the CHARTS pages ignore it completely. FEmusic_charts
//       returns identical Indian content for gl=US, because YouTube
//       geolocates those from the requesting IP. A region picker cannot
//       override that, and the Settings copy says so rather than
//       promising something the API won't honour.
//   hl  interface language. Affects the strings YouTube sends back
//       (section headings and so on), not which music is returned.
//
// Resolution order, first hit wins:
//
//   1. an explicit override the user picked in Settings
//   2. a cached IP lookup (region only, refreshed daily)
//   3. the device locale
//   4. IN / en
//
// The IP lookup never blocks a request. Everything falls back to the
// device locale, which is available synchronously, so the first feed after
// a cold start is always correct-ish and self-corrects once the lookup
// lands.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// A resolved (region, language) pair plus where it came from, so the UI
/// can show "Auto (India)" rather than pretending the user chose it.
@immutable
class YtLocale {
  const YtLocale({
    required this.country,
    required this.language,
    this.countryIsAuto = true,
    this.languageIsAuto = true,
  });

  final String country;
  final String language;
  final bool countryIsAuto;
  final bool languageIsAuto;

  static const fallback =
      YtLocale(country: 'IN', language: 'en');

  @override
  String toString() => 'YtLocale($country/$language, '
      'auto: country=$countryIsAuto language=$languageIsAuto)';

  @override
  bool operator ==(Object other) =>
      other is YtLocale &&
      other.country == country &&
      other.language == language &&
      other.countryIsAuto == countryIsAuto &&
      other.languageIsAuto == languageIsAuto;

  @override
  int get hashCode =>
      Object.hash(country, language, countryIsAuto, languageIsAuto);
}

/// Region codes offered in Settings. Not exhaustive on purpose — a
/// 250-entry ISO list is worse to scroll than a short list of the places
/// this app is actually used, and "Auto" covers everyone else.
const kYtRegions = <String, String>{
  'IN': 'India',
  'US': 'United States',
  'GB': 'United Kingdom',
  'CA': 'Canada',
  'AU': 'Australia',
  'DE': 'Germany',
  'FR': 'France',
  'JP': 'Japan',
  'KR': 'South Korea',
  'BR': 'Brazil',
  'MX': 'Mexico',
  'ID': 'Indonesia',
  'PK': 'Pakistan',
  'BD': 'Bangladesh',
  'AE': 'United Arab Emirates',
  'SG': 'Singapore',
  'NG': 'Nigeria',
  'ZA': 'South Africa',
};

/// Interface languages offered in Settings.
const kYtLanguages = <String, String>{
  'en': 'English',
  'hi': 'Hindi',
  'bn': 'Bengali',
  'ta': 'Tamil',
  'te': 'Telugu',
  'mr': 'Marathi',
  'gu': 'Gujarati',
  'kn': 'Kannada',
  'ml': 'Malayalam',
  'pa': 'Punjabi',
  'ur': 'Urdu',
  'es': 'Spanish',
  'pt': 'Portuguese',
  'fr': 'French',
  'de': 'German',
  'ja': 'Japanese',
  'ko': 'Korean',
  'id': 'Indonesian',
};

class YtLocaleResolver {
  YtLocaleResolver(this._dio);
  final Dio _dio;

  /// Re-checked at most once a day. A phone's public IP changes often
  /// enough to matter when travelling, and rarely enough that hitting a
  /// third-party service per launch would be wasteful.
  static const _kTtl = Duration(hours: 24);

  String? _cachedCountry;
  DateTime? _cachedAt;

  /// Region from the device locale. Synchronous and always available.
  static String? deviceCountry() {
    final code = PlatformDispatcher.instance.locale.countryCode;
    return (code == null || code.isEmpty) ? null : code.toUpperCase();
  }

  /// Language from the device locale. Synchronous and always available.
  static String? deviceLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode;
    return (code.isEmpty) ? null : code.toLowerCase();
  }

  /// Resolve with the overrides applied. Never throws.
  ///
  /// [countryOverride] / [languageOverride] are the Settings values; null
  /// means "auto".
  YtLocale resolve({String? countryOverride, String? languageOverride}) {
    final country = (countryOverride != null && countryOverride.isNotEmpty)
        ? countryOverride
        : (_freshCachedCountry() ??
            deviceCountry() ??
            YtLocale.fallback.country);
    final language = (languageOverride != null && languageOverride.isNotEmpty)
        ? languageOverride
        : (deviceLanguage() ?? YtLocale.fallback.language);
    return YtLocale(
      country: country,
      language: language,
      countryIsAuto: countryOverride == null || countryOverride.isEmpty,
      languageIsAuto: languageOverride == null || languageOverride.isEmpty,
    );
  }

  String? _freshCachedCountry() {
    final at = _cachedAt;
    if (_cachedCountry == null || at == null) return null;
    if (DateTime.now().difference(at) > _kTtl) return null;
    return _cachedCountry;
  }

  /// Look the region up by IP and cache it.
  ///
  /// Fire-and-forget: callers keep whatever the device locale gave them
  /// until this lands. Returns the country code, or null on any failure —
  /// a geo service being down must never affect playback or browsing.
  ///
  /// Note this necessarily discloses the device's IP to a third party.
  /// It's a plain "what country is this address in" request with no
  /// identifiers attached, and it stops entirely once the user sets an
  /// explicit region in Settings.
  Future<String?> refreshFromIp() async {
    if (_freshCachedCountry() != null) return _cachedCountry;
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://ipwho.is/',
        options: Options(
          responseType: ResponseType.json,
          receiveTimeout: const Duration(seconds: 6),
          sendTimeout: const Duration(seconds: 6),
        ),
      );
      final code = res.data?['country_code'];
      if (code is String && code.length == 2) {
        _cachedCountry = code.toUpperCase();
        _cachedAt = DateTime.now();
        // ignore: avoid_print
        print('[yt-locale] region from IP: $_cachedCountry');
        return _cachedCountry;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[yt-locale] IP lookup failed, staying on device locale: $e');
    }
    return null;
  }
}
