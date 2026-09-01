// Riverpod surface for the on-device music library.
//
// A ChangeNotifier rather than a FutureProvider because the library has more
// states than "loading or loaded": permission can be refused, refused
// permanently, or granted onto a device with no music, and each needs a
// different thing said to the user.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../audio/local_library.dart';

final localLibraryProvider = ChangeNotifierProvider<LocalLibrary>((ref) {
  final library = LocalLibrary();
  // Scan only if access is already granted — never prompt from here. This
  // provider is watched by the Library tab's device row, and raising a system
  // permission dialog because someone opened Library is both startling and
  // the fastest route to a permanent denial. The device library screen asks
  // properly, when the user has actually gone looking for it.
  //
  // Deferred a frame so the scan cannot stall the build that created it.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => library.loadIfPermitted(),
  );
  return library;
});
