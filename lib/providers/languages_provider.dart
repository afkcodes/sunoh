// `/music/languages` provider — populates the Settings → Music Languages
// picker. The values rarely change so we keep the response cached for
// 24 h (matches RN's staleTime).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/dto.dart';
import 'api_providers.dart';

final languagesProvider =
    FutureProvider.autoDispose<List<ApiLanguage>>((ref) async {
  // Keep the response alive across nav cycles; refetch at most once a day.
  final link = ref.keepAlive();
  Future<void>.delayed(const Duration(hours: 24)).then((_) => link.close());
  final api = ref.watch(sunohApiProvider);
  return api.fetchLanguages();
});
