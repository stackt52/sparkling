import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network reachability as a boolean stream (CUS-054, STF-062).
///
/// Note: connectivity != server reachability; combine with [OfflineQueue]
/// sync results (or [report]) for the true "synced" state.
class ConnectivityService {
  /// Production: listens to `connectivity_plus`.
  ConnectivityService({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity(),
      _source = null,
      _lastKnown = true {
    _listenPlatform();
  }

  /// Driven by an explicit [source] stream (tests, demo mode).
  ConnectivityService.fromStream(Stream<bool> source, {bool initial = true})
    : _connectivity = null,
      _source = source,
      _lastKnown = initial {
    _sub = source.listen(_emit);
  }

  /// Always online (demo mode).
  factory ConnectivityService.alwaysOnline() =>
      ConnectivityService.fromStream(const Stream<bool>.empty(), initial: true);

  final Connectivity? _connectivity;
  final Stream<bool>? _source;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  StreamSubscription<dynamic>? _sub;
  bool _lastKnown;

  void _listenPlatform() {
    final c = _connectivity!;
    _sub = c.onConnectivityChanged.listen(
      (results) => _emit(_isOnline(results)),
    );
    c.checkConnectivity().then((r) => _emit(_isOnline(r))).catchError((_) {});
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  void _emit(bool online) {
    final changed = online != _lastKnown;
    _lastKnown = online;
    if (changed && !_controller.isClosed) _controller.add(online);
  }

  /// Emits the current value first, then every transition.
  Stream<bool> get online async* {
    yield _lastKnown;
    yield* _controller.stream;
  }

  /// Only the transitions.
  Stream<bool> get changes => _controller.stream;

  bool get lastKnown => _lastKnown;
  bool get isOffline => !_lastKnown;

  Future<bool> isOnline() async {
    if (_source != null) return _lastKnown;
    try {
      final r = await _connectivity!.checkConnectivity();
      _emit(_isOnline(r));
    } catch (_) {}
    return _lastKnown;
  }

  /// Manually override (e.g. after an API call failed with `network`, or
  /// succeeded while the platform said offline).
  void report(bool online) => _emit(online);

  Future<void> dispose() async {
    await _sub?.cancel();
    await _controller.close();
  }
}
