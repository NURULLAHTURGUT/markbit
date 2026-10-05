import 'package:flutter/material.dart';

import '../core/l10n/app_strings.dart';

/// Shown when the library cannot be opened at startup. Texts follow the
/// language chosen in settings when it could be read, English otherwise.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Markbit',
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 36),
                const SizedBox(height: 16),
                Text(
                  trs(
                    'Your data could not be opened. Your existing files are kept.\nCheck disk access and try again.',
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: onRetry, child: Text(trs('Retry'))),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
