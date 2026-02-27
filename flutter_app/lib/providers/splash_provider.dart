import 'package:flutter/foundation.dart';

/// Simple ChangeNotifier that carries a progress message string.
/// Provide it above [SplashScreen] so the splash can display live status.
class SplashProvider extends ChangeNotifier {
  String _progressText = 'Starting up...';
  String get progressText => _progressText;

  void setProgress(String text) {
    _progressText = text;
    notifyListeners();
  }
}
