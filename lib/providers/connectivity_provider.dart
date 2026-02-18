import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivityProvider with ChangeNotifier {
  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool? _isOnline;

  bool? get isOnline => _isOnline;

  ConnectivityProvider({Connectivity? connectivity}) : _connectivity = connectivity ?? Connectivity();

  Future<void> init() async {
    if (_sub != null) return;

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final has = results.isNotEmpty && !results.contains(ConnectivityResult.none);
      final next = has ? true : false;
      if (_isOnline == next) return;
      _isOnline = next;
      notifyListeners();
    });

    final results = await _connectivity.checkConnectivity();
    final has = results.isNotEmpty && !results.contains(ConnectivityResult.none);
    final next = has ? true : false;
    if (_isOnline != next) {
      _isOnline = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _sub = null;
    super.dispose();
  }
}
