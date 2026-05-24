// Riverpod providers for the API layer.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/client.dart';
import '../api/sunoh_api.dart';

/// Single shared Dio instance.
final dioProvider = Provider((_) => buildSunohDio());

/// The typed sunoh-api service.
final sunohApiProvider = Provider((ref) => SunohApi(ref.watch(dioProvider)));
