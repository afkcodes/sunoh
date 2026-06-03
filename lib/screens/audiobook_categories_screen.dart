// Full audiobook genres grid — opens from the "Browse" chip on the
// Audiobooks tab. Identical structural shape to PodcastCategoriesScreen
// but stripped down to a single sorted grid (no per-section grouping
// because the cozyaudiobooks taxonomy is flat).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:solar_icons/solar_icons.dart';

import '../providers/app_state_provider.dart';
import '../providers/audiobook_provider.dart';
import '../router/router.dart';
import '../theme/tokens.dart';
import '../widgets/ui.dart';

class AudiobookCategoriesScreen extends ConsumerWidget {
  const AudiobookCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appStateProvider);
    final c = s.colors;
    final async = ref.watch(audiobookCategoriesProvider);

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(SolarIconsOutline.altArrowLeft, color: c.fg),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Genres',
          style: SunohType.sans(
              fontSize: 16, fontWeight: FontWeight.w600, color: c.fg),
        ),
      ),
      body: async.when(
        data: (cats) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.3,
          ),
          itemCount: cats.length,
          itemBuilder: (ctx, i) {
            final cat = cats[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  context.openAudiobookCategory(cat.id, name: cat.name),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: squircleDecoration(
                  radius: 14,
                  color: c.surface,
                  borderColor: c.line,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      cat.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SunohType.sans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.fg,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${cat.count} book${cat.count == 1 ? '' : 's'}',
                      style: SunohType.sans(fontSize: 11, color: c.fgMute),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Couldn’t load genres.',
              textAlign: TextAlign.center,
              style: SunohType.sans(fontSize: 13, color: c.fgMute),
            ),
          ),
        ),
      ),
    );
  }
}
