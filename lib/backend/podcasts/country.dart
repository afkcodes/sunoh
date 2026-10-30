// Country selection for /podcasts/home.

/// Storefronts with an editorial mix; anything else falls back.
const supportedCountries = {'IN', 'US'};
const defaultCountry = 'IN';

/// `?country=` wins, then the device locale, then [defaultCountry].
/// The server instead guessed from the caller's IP (ip-api.com) and
/// Accept-Language because it could not see the device. On the phone the
/// locale is the same signal without a network call that would leak the
/// user's IP to a third party, so the geo lookup is deliberately not ported.
String resolveCountry({String? explicit, String? deviceCountry}) {
  for (final c in [explicit, deviceCountry]) {
    final up = (c != null && RegExp(r'^[A-Za-z]{2}$').hasMatch(c))
        ? c.toUpperCase()
        : null;
    if (up != null && supportedCountries.contains(up)) return up;
  }
  return defaultCountry;
}
