import 'package:flutter/foundation.dart';
import '../engine/scryfall_engine.dart';

/// MVC State Controller for the Commander Roller.
/// Holds all state and orchestrates the ScryfallEngine.
class RollProvider extends ChangeNotifier {
  final ScryfallEngine _engine;

  RollProvider({ScryfallEngine? engine})
      : _engine = engine ?? ScryfallEngine();

  // ── State ─────────────────────────────────────────────────────────────────

  /// W/U/B/R/G overrides. true = forced in, false = forced out, null = random.
  Map<String, bool?> colorOverrides = {
    'W': null,
    'U': null,
    'B': null,
    'R': null,
    'G': null,
  };

  int maxCmc = 6;
  String sortType = 'edhrec';

  bool isLoading = false;
  String? errorMessage;

  List<Map<String, dynamic>> results = [];
  Map<String, dynamic>? selectedCommander;

  // ── Actions ───────────────────────────────────────────────────────────────

  /// Toggles a color override: null → true → false → null
  void toggleColor(String color) {
    final current = colorOverrides[color];
    if (current == null) {
      colorOverrides = {...colorOverrides, color: true};
    } else if (current == true) {
      colorOverrides = {...colorOverrides, color: false};
    } else {
      colorOverrides = {...colorOverrides, color: null};
    }
    notifyListeners();
  }

  void setMaxCmc(int value) {
    maxCmc = value;
    notifyListeners();
  }

  void setSortType(String value) {
    sortType = value;
    notifyListeners();
  }

  void selectCommander(Map<String, dynamic> commander) {
    selectedCommander = commander;
    notifyListeners();
  }

  /// Main roll action — generates identity via RNG, fetches from Scryfall.
  Future<void> roll() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Build the overrides map for the engine: only pass truly forced colors
      final forced = <String, bool>{};
      for (final entry in colorOverrides.entries) {
        if (entry.value != null) forced[entry.key] = entry.value!;
      }

      final identity = _engine.generateIdentity(forced);
      final commanders = await _engine.fetchCommanders(identity, maxCmc, sortType);

      results = commanders;
      selectedCommander = commanders.isNotEmpty ? commanders.first : null;
    } catch (e) {
      errorMessage = 'Roll failed: $e';
      results = [];
      selectedCommander = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}
