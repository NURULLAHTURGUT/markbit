import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether this process shows the welcome tour and the startup animation.
/// Enabled by `main()` for the main window; tests and note windows go
/// straight to the workspace.
final onboardingEnabledProvider = Provider<bool>((ref) => false);

const _doneKey = 'onboarding_done_v1';

/// True while the welcome tour is open, which happens on the very first
/// launch only.
final onboardingPendingProvider = NotifierProvider<OnboardingNotifier, bool>(
  OnboardingNotifier.new,
);

class OnboardingNotifier extends Notifier<bool> {
  @override
  bool build() =>
      ref.watch(onboardingEnabledProvider) &&
      ref.read(sharedPrefsProvider).getBool(_doneKey) != true;

  /// Records that the tour was shown, so it never opens again on its own —
  /// even if the app is closed before the last step.
  Future<void> markSeen() =>
      ref.read(sharedPrefsProvider).setBool(_doneKey, true);

  /// Closes the tour (finished or skipped).
  Future<void> finish() async {
    state = false;
    await markSeen();
  }
}
