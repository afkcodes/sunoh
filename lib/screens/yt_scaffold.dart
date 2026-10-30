// The frame the YouTube Music list pages share: a pinned bar over a big page
// title, and the loading and empty states drawn inside it.
//
// Split out of ytmusic_screens.dart once the moods pages moved to their own
// file; both files draw in it.

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'detail_chrome.dart';

/// Shared chrome for the list pages: the pinned bar over a big page title,
/// the same frame as Recently played and a "See all".
class YtScaffold extends StatelessWidget {
  const YtScaffold({
    super.key,
    required this.title,
    required this.colors,
    required this.children,
  });
  final String title;
  final SunohColors colors;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DetailPage(
      colors: colors,
      colour: colors.bg,
      title: title,
      solidAt: PageTitle.solidAt,
      builder: (_) => [
        SliverToBoxAdapter(
          child: PageTitle(colors: colors, title: title),
        ),
        SliverList.list(children: children),
      ],
    );
  }
}

Widget ytLoading(SunohColors c) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 60),
  child: Center(
    child: SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2, color: c.fgMute),
    ),
  ),
);

Widget ytError(SunohColors c, String message) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 30, 16, 30),
  child: Text(message, style: SunohType.sans(fontSize: 13, color: c.fgMute)),
);
