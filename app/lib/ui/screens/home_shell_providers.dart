import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Index of the active bottom-nav tab in [HomeShell]. Lifted to a provider
/// so screens (e.g. Home's "Start Station" feature card) can flip the tab
/// without pushing a new route — keeping the shell + mini-player + glass
/// nav intact across the transition.
///
/// 0 = Home, 1 = AI DJ, 2 = Search, 3 = Library.
final homeTabIndexProvider = StateProvider<int>((_) => 0);

/// Active chip on the Library tab ('Songs' | 'Favorites' | 'Playlists').
/// Lifted to a provider so the Home screen's "See All" can deep-link
/// straight into the playlists view without a Navigator push.
final libraryChipProvider = StateProvider<String>((_) => 'Songs');
