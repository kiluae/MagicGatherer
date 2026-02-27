import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../engine/flip_engine.dart';

class FlipProvider extends ChangeNotifier {
  final CommanderFlipEngine _engine;

  FlipProvider({CommanderFlipEngine? engine})
      : _engine = engine ?? CommanderFlipEngine();

  // ── Coin State ────────────────────────────────────────────────────────────
  Map<String, bool> coins = {
    'W': false, 'U': false, 'B': false, 'R': false, 'G': false,
  };

  // ── Loading / Flip State ──────────────────────────────────────────────────
  bool isFlipping = false;
  bool isLoading  = false;
  String? errorMessage;

  List<Map<String, dynamic>> results      = [];
  Map<String, dynamic>?     selectedCommander;

  // ── Options ───────────────────────────────────────────────────────────────
  int    maxReturns         = 10;
  int    maxCmc             = 100;
  String poolTier           = 'edhrec_top';
  String localSort          = 'edhrec';
  bool   allowPartialColors = false;
  bool   includePartners    = true;  // default ON so 4-color rolls aren't empty
  String currentIdentityName = 'Colorless';

  // ── Actions ───────────────────────────────────────────────────────────────

  void toggleCoin(String color) {
    coins = {...coins, color: !(coins[color] ?? false)};
    notifyListeners();
  }

  void setMaxReturns(int v)   { maxReturns = v;   notifyListeners(); }
  void setMaxCmc(int v)       { maxCmc = v;       notifyListeners(); }
  void setPoolTier(String v)  { poolTier = v;             notifyListeners(); }
  void setLocalSort(String v) { localSort = v;            notifyListeners(); }
  void togglePartialColors()  { allowPartialColors = !allowPartialColors; notifyListeners(); }
  void togglePartners()       { includePartners    = !includePartners;    notifyListeners(); }

  /// Change sort and instantly re-sort the loaded results in memory.
  void changeLocalSort(String newSort) {
    localSort = newSort;
    _applySorting();
    notifyListeners();
  }

  /// Sorts [results] in-place based on [localSort]. No network call.
  void _applySorting() {
    switch (localSort) {
      case 'edhrec':
        results.sort((a, b) =>
            (a['edhrec_rank'] as int? ?? 999999)
                .compareTo(b['edhrec_rank'] as int? ?? 999999));
      case 'cmc':
        results.sort((a, b) =>
            (a['cmc'] as num? ?? 99)
                .compareTo(b['cmc'] as num? ?? 99));
      case 'price':
        results.sort((a, b) =>
            (double.tryParse(b['prices']?['usd'] as String? ?? '0') ?? 0.0)
                .compareTo(
                    double.tryParse(a['prices']?['usd'] as String? ?? '0') ?? 0.0));
      case 'random':
        results.shuffle(Random.secure());
    }
  }

  void selectCommander(Map<String, dynamic> c) {
    selectedCommander = c;
    notifyListeners();
  }

  /// Fetches commanders matching the currently active coins.
  Future<void> fetchCurrentSelection() async {
    final active   = coins.entries.where((e) => e.value).map((e) => e.key).join();
    final identity = active.isEmpty ? 'c' : active;
    currentIdentityName = CommanderFlipEngine.getIdentityName(identity);

    isLoading    = true;
    errorMessage = null;
    notifyListeners();

    try {
      final commanders = await _engine.fetchCommanders(
        identity:           identity,
        maxCmc:             maxCmc,
        poolTier:           poolTier,
        localSort:          localSort,
        maxReturns:         maxReturns,
        allowPartialColors: allowPartialColors,
        includePartners:    includePartners,
      );
      results           = commanders;
      _applySorting(); // sort before notifying so UI sees final order
      selectedCommander = results.isNotEmpty ? results.first : null;
    } catch (e) {
      errorMessage = 'Fetch failed: $e';
      debugPrint('[FlipProvider] fetchCurrentSelection error: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Starts the coin-flicker animation, then fetches after 1.2 s.
  Future<void> startRandomFlip() async {
    if (isFlipping) return;

    isFlipping = true;
    notifyListeners();

    final rng = Random.secure(); // cryptographic — no clock-seed repeating
    Timer? timer;

    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      coins = {for (final k in coins.keys) k: rng.nextBool()};
      notifyListeners();
    });

    await Future.delayed(const Duration(milliseconds: 1200));
    timer.cancel();

    // Final flip — guarantee at least one coin is heads
    Map<String, bool> finalCoins;
    do {
      finalCoins = {for (final k in coins.keys) k: rng.nextBool()};
    } while (finalCoins.values.every((v) => !v));
    coins      = finalCoins;
    isFlipping = false;
    notifyListeners();

    await fetchCurrentSelection();
  }
}
