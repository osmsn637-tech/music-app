import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/database/providers.dart';
import '../../data/repositories/song_repository.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const [],
    this.loading = false,
  });

  final String query;
  final List<SongRow> results;
  final bool loading;

  SearchState copyWith({String? query, List<SongRow>? results, bool? loading}) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      loading: loading ?? this.loading,
    );
  }
}

class LibrarySearchController extends StateNotifier<SearchState> {
  LibrarySearchController(this._repo) : super(const SearchState());

  final SongRepository _repo;
  Timer? _debounce;

  static const _debounceDuration = Duration(milliseconds: 200);

  void onQueryChanged(String query) {
    state = state.copyWith(query: query);
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      state = state.copyWith(results: const [], loading: false);
      return;
    }

    state = state.copyWith(loading: true);
    _debounce = Timer(_debounceDuration, () async {
      final results = await _repo.search(query);
      // The user may have typed more characters by the time results land.
      if (state.query == query) {
        state = state.copyWith(results: results, loading: false);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }
}

final librarySearchControllerProvider =
    StateNotifierProvider<LibrarySearchController, SearchState>((ref) {
  return LibrarySearchController(ref.watch(songRepositoryProvider));
});
