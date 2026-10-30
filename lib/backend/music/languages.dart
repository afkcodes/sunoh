// Port of sunoh-api src/music/languages.ts.
import '../local_backend.dart';

const _languages = [
  ('Hindi', 'hindi'),
  ('English', 'english'),
  ('Punjabi', 'punjabi'),
  ('Telugu', 'telugu'),
  ('Tamil', 'tamil'),
  ('Bhojpuri', 'bhojpuri'),
  ('Bengali', 'bengali'),
  ('Malayalam', 'malayalam'),
  ('Kannada', 'kannada'),
  ('Marathi', 'marathi'),
  ('Gujarati', 'gujarati'),
  ('Haryanvi', 'haryanvi'),
  ('Urdu', 'urdu'),
  ('Assamese', 'assamese'),
  ('Rajasthani', 'rajasthani'),
  ('Odia', 'odia'),
  ('Sanskrit', 'sanskrit'),
];

Future<LocalReply> languagesController(
  Map<String, String> params,
  Map<String, String> query,
) async => LocalReply([
  for (final (name, value) in _languages) {'name': name, 'value': value},
], message: 'Languages fetched successfully');
