import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:music_app/app.dart';
import 'package:music_app/features/library/home_providers.dart';
import 'package:music_app/features/library/providers.dart';
import 'package:music_app/features/playlists/providers.dart';

void main() {
  testWidgets('App boots into the Listen Now screen with the new nav',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Stub everything that touches sqlite so tests don't need a native
          // sqlite3 binary on the host machine.
          allSongsProvider.overrideWith((ref) => Stream.value(const [])),
          favoriteSongsProvider.overrideWith((ref) => Stream.value(const [])),
          allPlaylistsProvider.overrideWith((ref) => Stream.value(const [])),
          recentlyPlayedProvider
              .overrideWith((ref) => Stream.value(const [])),
          recentlyAddedProvider
              .overrideWith((ref) => Stream.value(const [])),
          topArtistsProvider.overrideWith((ref) => const []),
        ],
        child: const MusicApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // Page title for the Home / Listen Now screen.
    expect(find.text('Listen Now'), findsOneWidget);
    // Bottom-nav destinations under the new design.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('AI DJ'), findsOneWidget);
    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
  });
}
