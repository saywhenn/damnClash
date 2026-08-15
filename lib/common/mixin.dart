import 'dart:async';

import 'package:fl_clash/widgets/inherited.dart';
import 'package:flutter/cupertino.dart';
import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'utils.dart';

mixin AutoDisposeNotifierMixin<T> on AnyNotifier<T, T> {
  T get value => state;

  set value(T value) {
    state = value;
  }

  bool equals(T previous, T next) {
    return false;
  }

  @override
  bool updateShouldNotify(previous, next) {
    final res = !equals(previous, next)
        ? super.updateShouldNotify(previous, next)
        : true;
    if (res) {
      onUpdate(next);
    }
    return res;
  }

  void onUpdate(T value) {}

  void update(T Function(T) builder) {
    final res = builder(value);
    if (res == value) {
      return;
    }
    value = res;
  }
}

mixin AsyncNotifierMixin<T> on AnyNotifier<AsyncValue<T>, T> {
  T get value;

  set value(T value) {
    state = AsyncData(value);
  }
}

mixin UniqueKeyStateMixin<T extends StatefulWidget> on State<T> {
  final key = utils.id;
}

typedef PollGuard = bool Function();

mixin ActivePollingMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  Timer? _pollTimer;
  bool _isForeground = false;
  bool _isPageActive = true;
  bool _isPolling = false;
  int _pollGeneration = 0;

  Duration get pollInterval;

  bool get pollOnStart => true;

  Future<void> poll(PollGuard isCurrent);

  bool get canPoll => mounted && _isForeground && _isPageActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isForeground =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncPolling();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isPageActive = PageActivityScope.isActiveOf(context);
    if (_isPageActive == isPageActive) {
      return;
    }
    _isPageActive = isPageActive;
    _syncPolling();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final isForeground = state == AppLifecycleState.resumed;
    if (_isForeground == isForeground) {
      return;
    }
    _isForeground = isForeground;
    _syncPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _isForeground = false;
    stopPolling();
    super.dispose();
  }

  void startPolling() {
    if (!canPoll || _isPolling) {
      return;
    }
    _isPolling = true;
    final generation = ++_pollGeneration;
    if (pollOnStart) {
      unawaited(_runPoll(generation));
      return;
    }
    _schedulePoll(generation);
  }

  void stopPolling() {
    _isPolling = false;
    _pollGeneration++;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void restartPolling() {
    stopPolling();
    _syncPolling();
  }

  void _syncPolling() {
    if (canPoll) {
      startPolling();
    } else {
      stopPolling();
    }
  }

  bool _isCurrentPoll(int generation) =>
      canPoll && _isPolling && generation == _pollGeneration;

  void _schedulePoll(int generation) {
    _pollTimer = Timer(pollInterval, () {
      _pollTimer = null;
      if (_isCurrentPoll(generation)) {
        unawaited(_runPoll(generation));
      }
    });
  }

  Future<void> _runPoll(int generation) async {
    await poll(() => _isCurrentPoll(generation));
    if (!_isCurrentPoll(generation)) {
      return;
    }
    _schedulePoll(generation);
  }
}
