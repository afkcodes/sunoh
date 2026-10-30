// Which folders the on-device library takes music from.
//
// A phone's audio is not all music: notification tones, voice notes, WhatsApp
// audio and podcast downloads from another app all land in MediaStore and all
// show up in the library. MediaStore's IS_MUSIC flag and the duration floor
// catch some of it, and nothing catches a folder of forwarded voice notes that
// happen to be four minutes long.
//
// The screen is a tree with a row for the device itself at the top. Every
// folder follows the one above it until you say otherwise, so the two things
// people actually want are each a couple of taps: keep everything but the
// ringtones (leave the top row on, turn one folder off), or take only one
// library (turn the top row off, turn that folder on). See [FolderRules] for
// why one rule beats an include list or an exclude list.
//
// Rows are ordered and indented by path so a folder sits directly under the
// one it inherits from, and the count on the right is every track in that
// folder whether it is currently taken or not.
//
// The selection applies in one go. Six folders is one decision, and applying
// each separately would rescan the library six times, five of those showing a
// state nobody asked for.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:remixicon/remixicon.dart';

import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/motion.dart';
import '../widgets/ui.dart';
import 'pill_button.dart';
import 'sub_page_bar.dart';

class LocalFoldersScreen extends ConsumerStatefulWidget {
  const LocalFoldersScreen({super.key});

  @override
  ConsumerState<LocalFoldersScreen> createState() => _LocalFoldersScreenState();
}

class _LocalFoldersScreenState extends ConsumerState<LocalFoldersScreen> {
  /// Rules staged for the next apply. Null until there is a scan to read, so a
  /// scan still in flight cannot seed a choice nobody made.
  FolderRules? _staged;

  /// Rows are derived from the folder list, which only changes on a rescan, so
  /// they are built once per scan rather than on every frame — see the
  /// no-work-in-`build` rule. [LocalLibrary.folders] hands back the same list
  /// instance until a rescan replaces it, which is what makes the identity
  /// check sound.
  List<LocalFolder>? _rowsFor;
  List<_Row> _rows = const [];

  List<_Row> _rowsOf(List<LocalFolder> folders) {
    if (identical(folders, _rowsFor)) return _rows;
    _rowsFor = folders;
    return _rows = _tree(folders);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);
    final rows = _rowsOf(lib.folders);

    final staged = _staged ??= lib.folderRules;
    final dirty = !staged.sameAs(lib.folderRules);
    final kept = rows.where((r) => staged.allows(r.folder.path));
    final tracks = kept.fold<int>(0, (n, r) => n + r.folder.trackCount);

    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          SubPageBar(
            title: 'Music folders',
            colors: c,
            actions: [
              if (lib.isScanning)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.fgMute,
                    ),
                  ),
                )
              else if (!staged.isDefault)
                PillButton(
                  label: 'Reset',
                  colors: c,
                  height: 32,
                  onTap: () => setState(() => _staged = const FolderRules()),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Turn a folder off to leave it out. Everything inside it follows '
              'unless you turn one back on.',
              style: SunohType.sans(fontSize: 14, color: c.fgDim, height: 1.45),
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? Center(
                    child: Text(
                      lib.isScanning
                          ? 'Scanning…'
                          : 'No music folders found on this device.',
                      style: SunohType.sans(fontSize: 13, color: c.fgMute),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: dirty ? 8 : 140),
                    // One extra for the device row the folders hang off.
                    itemCount: rows.length + 1,
                    itemBuilder: (context, i) => i == 0
                        ? _DeviceRow(
                            colors: c,
                            on: staged.defaultIncluded,
                            tracks: tracks,
                            onTap: () => setState(() {
                              _staged = staged.withDefault(
                                included: !staged.defaultIncluded,
                              );
                            }),
                          )
                        : _rowFor(rows[i - 1], staged, c),
                  ),
          ),
          if (dirty)
            _ApplyBar(
              colors: c,
              busy: lib.isScanning,
              onApply: () => _apply(lib, s, staged),
            ),
        ],
      ),
    );
  }

  Widget _rowFor(_Row row, FolderRules staged, SunohColors c) {
    final path = row.folder.path;
    final on = staged.allows(path);
    return _FolderRow(
      row: row,
      colors: c,
      on: on,
      // An explicit rule is drawn solid so a folder someone deliberately set
      // is distinguishable from one that merely follows its parent — otherwise
      // there is no way to see what you have actually decided.
      explicit: staged.overrides.containsKey(path),
      onTap: () => setState(() => _staged = staged.set(path, included: !on)),
    );
  }

  Future<void> _apply(LocalLibrary lib, AppState s, FolderRules staged) async {
    await lib.setFolderRules(staged);
    if (!mounted) return;
    // Re-seed from what actually landed, so the bar clears only once the
    // library really matches the choice.
    setState(() => _staged = null);
    s.flashToast(staged.isDefault ? 'Using every folder' : 'Folders updated');
  }

  /// Order by path so a folder sits directly below the one it inherits from,
  /// and give each row its depth among the folders actually present — absolute
  /// path depth would indent everything off the screen.
  ///
  /// One pass with a stack of open ancestors rather than counting ancestors per
  /// row: the counting version is quadratic, which is invisible on a phone with
  /// twenty folders and is not on one with a thousand.
  static List<_Row> _tree(List<LocalFolder> folders) {
    final sorted = [...folders]..sort((a, b) => a.path.compareTo(b.path));
    final open = <String>[];
    final rows = <_Row>[];
    for (final f in sorted) {
      while (open.isNotEmpty && !f.path.startsWith('${open.last}/')) {
        open.removeLast();
      }
      rows.add(_Row(folder: f, depth: open.length));
      open.add(f.path);
    }
    return rows;
  }
}

class _Row {
  const _Row({required this.folder, required this.depth});
  final LocalFolder folder;
  final int depth;
}

/// The device itself, at the top of the tree. Every folder falls back to this,
/// including folders that do not exist yet — which is the whole reason it is a
/// row you can see and set rather than a hidden default.
class _DeviceRow extends StatelessWidget {
  const _DeviceRow({
    required this.colors,
    required this.on,
    required this.tracks,
    required this.onTap,
  });

  final SunohColors colors;
  final bool on;
  final int tracks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            _Check(on: on, explicit: true, colors: c),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'All music on this device',
                    style: SunohType.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.fg,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    on
                        ? 'New folders are included'
                        : 'New folders are left out',
                    style: SunohType.sans(fontSize: 13, color: c.fgDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$tracks',
              style: SunohType.mono(fontSize: 12.5, color: c.fgDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.row,
    required this.on,
    required this.explicit,
    required this.colors,
    required this.onTap,
  });

  final _Row row;
  final bool on;
  final bool explicit;
  final SunohColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final folder = row.folder;
    return Pressable(
      scale: 0.99,
      onTap: onTap,
      child: Padding(
        // Indent is capped: a deeply nested folder still needs room for its
        // name, and past a few levels the extra offset stops meaning anything.
        padding: EdgeInsets.fromLTRB(
          16.0 + 18 * (row.depth + 1).clamp(0, 4),
          9,
          16,
          9,
        ),
        child: Row(
          children: [
            _Check(on: on, explicit: explicit, colors: c),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.name.isEmpty ? folder.path : folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: on ? c.fg : c.fgMute,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Where it sits, not the whole path: two folders can share
                    // a name, and picking the wrong one silently hides the
                    // wrong music.
                    folderLocation(folder.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 13, color: c.fgDim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${folder.trackCount}',
              style: SunohType.mono(fontSize: 12.5, color: c.fgMute),
            ),
          ],
        ),
      ),
    );
  }
}

/// Four states in one control: in or out, each either set here or inherited.
/// Inherited reads as a faded version of the same mark rather than as a third
/// symbol, because it is the same answer — just decided further up.
class _Check extends StatelessWidget {
  const _Check({
    required this.on,
    required this.explicit,
    required this.colors,
  });

  final bool on;
  final bool explicit;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      alignment: Alignment.center,
      // Off is a filled well rather than a ring, like every other surface.
      // On swaps the well for a filled check-circle, the same weight as the well.
      decoration: BoxDecoration(
        color: on ? Colors.transparent : c.surface2,
        shape: BoxShape.circle,
      ),
      child: on
          ? Icon(
              RemixIcons.checkbox_circle_fill,
              size: 24,
              color: explicit ? c.accent : c.accent.withValues(alpha: 0.45),
            )
          // A folder turned off here gets a mark of its own, so a deliberate
          // exclusion is not mistaken for one that just follows its parent.
          : (explicit
                ? Container(width: 9, height: 1.8, color: c.fgMute)
                : null),
    );
  }
}

/// Floats above the mini player rather than sitting flush at the bottom: the
/// player and nav bar are drawn over every screen's last 140 logical pixels, so
/// a flush bar is invisible exactly when it matters.
class _ApplyBar extends StatelessWidget {
  const _ApplyBar({
    required this.colors,
    required this.busy,
    required this.onApply,
  });

  final SunohColors colors;
  final bool busy;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 148),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: squircleDecoration(
        radius: SunohRadius.card,
        color: c.surface,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Your library will be rescanned.',
              style: SunohType.sans(fontSize: 13, color: c.fgDim),
            ),
          ),
          PillButton(
            label: busy ? 'Applying…' : 'Apply',
            colors: c,
            primary: true,
            onTap: busy ? null : onApply,
          ),
        ],
      ),
    );
  }
}
