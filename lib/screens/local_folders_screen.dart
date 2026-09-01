// Which folders the on-device library takes music from.
//
// A phone's audio is not all music: notification tones, voice notes, WhatsApp
// audio and podcast downloads from another app all land in MediaStore and all
// show up in the library. MediaStore's IS_MUSIC flag and the duration floor
// catch some of it, and nothing catches a folder of forwarded voice notes that
// happen to be four minutes long.
//
// Choosing folders rather than excluding them. Both express the same thing,
// but a real library is a hundred album folders under one parent: "use this
// one" is a tap, and "not those ninety-nine" is not. Picking nothing means the
// whole device, so a fresh install works without ever opening this screen.
//
// A chosen folder covers everything inside it, and the list is ordered and
// indented by path so a parent sits directly above the folders it covers.
// Folders already covered are shown checked but not tappable — untangling
// them would mean choosing every sibling instead, which is the mess this
// screen exists to avoid.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:solar_icons/solar_icons.dart';

import '../api/local_media_channel.dart';
import '../audio/local_library.dart';
import '../providers/app_state_provider.dart';
import '../providers/local_library_provider.dart';
import '../state/app_state.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class LocalFoldersScreen extends ConsumerStatefulWidget {
  const LocalFoldersScreen({super.key});

  @override
  ConsumerState<LocalFoldersScreen> createState() => _LocalFoldersScreenState();
}

class _LocalFoldersScreenState extends ConsumerState<LocalFoldersScreen> {
  /// Roots staged for the next apply. Null until there is a scan to read, so a
  /// scan still in flight cannot seed an empty selection that then looks like
  /// a deliberate choice.
  Set<String>? _staged;

  static bool _same(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final lib = ref.watch(localLibraryProvider);
    final rows = _rows(lib.folders);

    final staged = _staged ??= {...lib.includedFolders};
    final dirty = !_same(staged, lib.includedFolders);

    return ColoredBox(
      color: c.bg,
      child: Column(
        children: [
          _Header(
            colors: c,
            scanning: lib.isScanning,
            everything: staged.isEmpty,
            onUseEverything: staged.isEmpty
                ? null
                : () => setState(() => _staged = <String>{}),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Text(
              staged.isEmpty
                  ? 'Using every folder on this device. Choose one or more to '
                        'narrow it down — a folder brings everything inside it.'
                  : staged.length == 1
                  ? '1 folder chosen, and everything inside it.'
                  : '${staged.length} folders chosen, and everything inside '
                        'them.',
              style: SunohType.sans(
                fontSize: 13,
                color: c.fgMute,
                height: 1.45,
              ),
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
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final row = rows[i];
                      final chosen = staged.contains(row.folder.path);
                      final covered =
                          !chosen &&
                          staged.isNotEmpty &&
                          isUnderAnyRoot(row.folder.path, staged);
                      return _FolderRow(
                        row: row,
                        colors: c,
                        // Nothing chosen means everything is in, but the rows
                        // are not "chosen": showing them all ticked would make
                        // "Use everything" look like it did nothing.
                        state: chosen
                            ? _Pick.chosen
                            : covered
                            ? _Pick.covered
                            : _Pick.off,
                        onTap: covered
                            ? null
                            : () => setState(() {
                                final next = {...staged};
                                if (!next.remove(row.folder.path)) {
                                  // Drop anything this folder now covers, so
                                  // the set stays the shortest description of
                                  // the same choice.
                                  next.removeWhere(
                                    (p) => isUnderAnyRoot(p, {row.folder.path}),
                                  );
                                  next.add(row.folder.path);
                                }
                                _staged = next;
                              }),
                      );
                    },
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

  Future<void> _apply(LocalLibrary lib, AppState s, Set<String> staged) async {
    await lib.setIncludedFolders(staged);
    if (!mounted) return;
    // Re-seed from what actually landed, so the bar clears only once the
    // library really matches the choice.
    setState(() => _staged = null);
    s.flashToast(
      staged.isEmpty
          ? 'Using every folder'
          : 'Using ${staged.length} folder${staged.length == 1 ? '' : 's'}',
    );
  }

  /// Order by path so a parent sits directly above what it contains, and give
  /// each row its depth relative to the other folders actually present — the
  /// absolute path depth would indent everything off the screen.
  static List<_Row> _rows(List<LocalFolder> folders) {
    final sorted = [...folders]..sort((a, b) => a.path.compareTo(b.path));
    return [
      for (final f in sorted)
        _Row(
          folder: f,
          depth: sorted
              .where((o) => o.path != f.path && f.path.startsWith('${o.path}/'))
              .length,
        ),
    ];
  }
}

class _Row {
  const _Row({required this.folder, required this.depth});
  final LocalFolder folder;
  final int depth;
}

enum _Pick { chosen, covered, off }

class _Header extends StatelessWidget {
  const _Header({
    required this.colors,
    required this.scanning,
    required this.everything,
    required this.onUseEverything,
  });

  final SunohColors colors;
  final bool scanning;
  final bool everything;
  final VoidCallback? onUseEverything;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        6,
      ),
      child: Row(
        children: [
          IconBtn(
            icon: SolarIconsOutline.altArrowLeft,
            color: c.fgDim,
            size: 18,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Music folders',
              style: SunohType.heading(
                fontSize: 24,
                color: c.fg,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (scanning)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
            )
          else if (!everything)
            GestureDetector(
              onTap: onUseEverything,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  'Use everything',
                  style: SunohType.sans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.row,
    required this.state,
    required this.colors,
    required this.onTap,
  });

  final _Row row;
  final _Pick state;
  final SunohColors colors;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final folder = row.folder;
    final dim = state == _Pick.off;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        // Indent is capped: a deeply nested folder still needs room for its
        // name, and past a few levels the extra offset stops meaning anything.
        padding: EdgeInsets.fromLTRB(
          20.0 + 18 * row.depth.clamp(0, 4),
          10,
          20,
          10,
        ),
        child: Row(
          children: [
            _Check(state: state, colors: c),
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
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: dim ? c.fgMute : c.fg,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // Where it sits, not the whole path: two folders can share
                    // a name, and picking the wrong one silently hides the
                    // wrong music.
                    state == _Pick.covered
                        ? 'Included with the folder above'
                        : folderLocation(folder.path),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SunohType.sans(fontSize: 11.5, color: c.fgMute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${folder.trackCount}',
              style: SunohType.mono(fontSize: 12, color: c.fgMute),
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.state, required this.colors});
  final _Pick state;
  final SunohColors colors;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    final on = state != _Pick.off;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        // A covered folder is in the library but was not picked, so it reads
        // as a quieter version of the same tick rather than a second control.
        color: switch (state) {
          _Pick.chosen => c.accent,
          _Pick.covered => c.accent.withValues(alpha: 0.28),
          _Pick.off => Colors.transparent,
        },
        shape: BoxShape.circle,
        border: on ? null : Border.all(color: c.line, width: 1.5),
      ),
      child: on
          ? Icon(
              Icons.check_rounded,
              size: 15,
              color: state == _Pick.chosen ? c.onAccent : c.fgDim,
            )
          : null,
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
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: squircleDecoration(
        radius: 16,
        color: c.surface,
        borderColor: c.line,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Your library will be rescanned.',
              style: SunohType.sans(fontSize: 12.5, color: c.fgMute),
            ),
          ),
          GestureDetector(
            onTap: busy ? null : onApply,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: squircleDecoration(radius: 999, color: c.accent),
              child: Text(
                busy ? 'Applying…' : 'Apply',
                style: SunohType.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: c.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
