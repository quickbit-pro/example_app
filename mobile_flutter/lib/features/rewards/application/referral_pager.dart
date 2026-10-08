import 'package:flutter/foundation.dart';

/// Fetches one page of a server-paged referral resource.
typedef ReferralPageFetcher<T> = Future<List<T>> Function(int page, int pageSize);

/// Server paging for the friends list and the reward ledger.
///
/// The member API pages with `page` and `pageSize` and reports no total, so a
/// page shorter than [pageSize] is the last one. The first page can be seeded
/// from the rewards snapshot (which already loaded it) so a list opens with
/// content and only touches the network for the next page or a refresh.
///
/// State is explicit rather than derived, so a screen can tell "nothing yet"
/// from "loading" from "failed" and never renders a zero figure over a failed
/// request: [loaded] is only true after a page arrived, and [error] holds the
/// failure of the first page while [moreError] holds one of a later page (the
/// rows already shown stay on screen and "Load more" offers a retry).
class ReferralPager<T> extends ChangeNotifier {
  ReferralPager({
    required ReferralPageFetcher<T> fetch,
    this.pageSize = 50,
    List<T>? initial,
  }) : _fetch = fetch {
    if (initial != null) {
      _items.addAll(initial);
      _loaded = true;
      _nextPage = 2;
      _hasMore = initial.length >= pageSize;
    }
  }

  final ReferralPageFetcher<T> _fetch;
  final int pageSize;

  final List<T> _items = [];
  int _nextPage = 1;
  bool _loaded = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;
  Object? _moreError;
  int _generation = 0;

  /// Every row received so far, in server order.
  List<T> get items => List.unmodifiable(_items);

  /// A page has arrived (possibly empty). False until then, so an empty
  /// state is only ever shown after a successful response.
  bool get loaded => _loaded;

  /// The first page is in flight.
  bool get loading => _loading;

  /// A later page is in flight.
  bool get loadingMore => _loadingMore;

  /// The last page received was full, so another may exist.
  bool get hasMore => _hasMore;

  /// The first page failed; nothing is shown.
  Object? get error => _error;

  /// A later page failed; the rows already received stay.
  Object? get moreError => _moreError;

  /// Loads the first page unless one is already here.
  Future<void> load() async {
    if (_loaded || _loading) return;
    await _loadFirst();
  }

  /// Drops every row and fetches the first page again.
  Future<void> refresh() => _loadFirst();

  Future<void> _loadFirst() async {
    final generation = ++_generation;
    _loading = true;
    _error = null;
    _moreError = null;
    notifyListeners();
    try {
      final rows = await _fetch(1, pageSize);
      if (generation != _generation) return;
      _items
        ..clear()
        ..addAll(rows);
      _loaded = true;
      _nextPage = 2;
      _hasMore = rows.length >= pageSize;
    } catch (failure) {
      if (generation != _generation) return;
      _error = failure;
    } finally {
      if (generation == _generation) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Appends the next page. A no-op while a request is in flight or when the
  /// last page was short.
  Future<void> loadMore() async {
    if (!_loaded || !_hasMore || _loading || _loadingMore) return;
    final generation = _generation;
    _loadingMore = true;
    _moreError = null;
    notifyListeners();
    try {
      final rows = await _fetch(_nextPage, pageSize);
      if (generation != _generation) return;
      _items.addAll(rows);
      _nextPage += 1;
      _hasMore = rows.length >= pageSize;
    } catch (failure) {
      if (generation != _generation) return;
      _moreError = failure;
    } finally {
      if (generation == _generation) {
        _loadingMore = false;
        notifyListeners();
      }
    }
  }
}
