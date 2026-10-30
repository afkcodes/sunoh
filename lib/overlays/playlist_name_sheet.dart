// Naming a playlist: the one prompt behind both New playlist and Rename.
//
// A sheet rather than the centre-screen dialog it used to be (sheet.dart says
// why). It lives with the overlays, not in the playlist screen, because three
// places open it: Library, a playlist's own menu, and the Add to playlist
// sheet. The last opens it from inside another sheet, which works because
// showSunohSheet puts every sheet on the root navigator, so this one stacks
// above the picker instead of under the mini player.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_state_provider.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';
import 'sheet.dart';

/// The trimmed name, or null when the sheet is cancelled or dismissed.
/// An [initial] name means a rename: the field starts with it, and the sheet
/// says Rename and Save rather than New and Create.
Future<String?> promptForPlaylistName(
  BuildContext context, {
  String? initial,
}) => showSunohSheet<String>(
  context,
  builder: (_) => _PlaylistNameSheet(initial: initial),
);

/// Stateful only to own the controller. The dialog this replaced made one per
/// call and never disposed it.
class _PlaylistNameSheet extends ConsumerStatefulWidget {
  const _PlaylistNameSheet({this.initial});
  final String? initial;

  @override
  ConsumerState<_PlaylistNameSheet> createState() => _PlaylistNameSheetState();
}

class _PlaylistNameSheetState extends ConsumerState<_PlaylistNameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(appStateProvider).colors;
    final renaming = widget.initial != null;
    return SunohSheet(
      title: renaming ? 'Rename playlist' : 'New playlist',
      actions: SheetActions(
        secondary: SheetButton(
          label: 'Cancel',
          onTap: () => Navigator.of(context).pop(),
        ),
        primary: SheetButton(
          label: renaming ? 'Save' : 'Create',
          filled: true,
          onTap: _submit,
        ),
      ),
      // SunohSheet lifts itself above the keyboard, so the autofocused field
      // and the buttons under it stay in view while typing.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        // A filled field rather than a hairline underline, like the app's
        // other inputs; the accent cursor still marks focus.
        child: DecoratedBox(
          decoration: squircleDecoration(
            radius: SunohRadius.card,
            color: c.surface2,
          ),
          child: TextField(
            controller: _controller,
            autofocus: true,
            cursorColor: c.accent,
            style: SunohType.sans(fontSize: 15, color: c.fg),
            decoration: InputDecoration(
              hintText: 'Playlist name',
              hintStyle: SunohType.sans(fontSize: 14, color: c.fgMute),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ),
      ),
    );
  }
}
