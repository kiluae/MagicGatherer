import '../models/card_models.dart';
import '../services/scryfall_repository.dart';

// ── Deck Diagnosis Record ───────────────────────────────────────────────────

/// Summary statistics for a parsed deck.
class DeckDiagnosis {
  final int totalCards;
  final int rampCount;
  final int drawCount;
  final int removalCount;
  final int landCount;

  const DeckDiagnosis({
    required this.totalCards,
    required this.rampCount,
    required this.drawCount,
    required this.removalCount,
    required this.landCount,
  });
}

// ── Format Surgeon Engine ───────────────────────────────────────────────────

/// Static analyzer that categorizes cards by role (Ramp, Draw, Removal, Land)
/// and suggests format-legal replacements for dropped cards from the local
/// Scryfall oracle database.
class DeckDoctorEngine {
  // ── Card Role Categorizers ────────────────────────────────────────────────

  static final _rampRe = RegExp(
    r'(Add \{|add \{|search your library for a basic land|'
    r'search your library for .* land card|'
    r'put .* land card .* onto the battlefield)',
    caseSensitive: false,
  );

  static final _drawRe = RegExp(
    r'(draw a card|draw cards|draw two|draw three|draws? .* cards?)',
    caseSensitive: false,
  );

  static final _removalRe = RegExp(
    r'(destroy target|exile target|deals? \d+ damage to .* target|'
    r'destroy all|exile all|deals? \d+ damage to each)',
    caseSensitive: false,
  );

  static bool isRamp(String oracleText) => _rampRe.hasMatch(oracleText);
  static bool isDraw(String oracleText) => _drawRe.hasMatch(oracleText);
  static bool isRemoval(String oracleText) => _removalRe.hasMatch(oracleText);

  static bool isLand(String typeLine) =>
      typeLine.toLowerCase().contains('land');

  /// Returns a list of role tags for a card's oracle text / type line.
  static List<String> getRoles(String oracleText, String typeLine) {
    final roles = <String>[];
    if (isLand(typeLine)) roles.add('Land');
    if (isRamp(oracleText)) roles.add('Ramp');
    if (isDraw(oracleText)) roles.add('Draw');
    if (isRemoval(oracleText)) roles.add('Removal');
    return roles;
  }

  // ── Diagnosis ─────────────────────────────────────────────────────────────

  /// Analyzes a parsed deck and returns role-based counts.
  static DeckDiagnosis diagnose(List<ProxyCard> deck) {
    int ramp = 0, draw = 0, removal = 0, land = 0;

    for (final card in deck) {
      final oracle   = card.scryfallData['oracle_text'] as String? ?? '';
      final typeLine = card.scryfallData['type_line']   as String? ?? '';
      final qty      = card.quantity;

      if (isLand(typeLine))   land    += qty;
      if (isRamp(oracle))     ramp    += qty;
      if (isDraw(oracle))     draw    += qty;
      if (isRemoval(oracle))  removal += qty;
    }

    return DeckDiagnosis(
      totalCards:   deck.fold(0, (s, c) => s + c.quantity),
      rampCount:    ramp,
      drawCount:    draw,
      removalCount: removal,
      landCount:    land,
    );
  }

  // ── Suggestions ───────────────────────────────────────────────────────────

  /// For each dropped card, finds up to [limit] format-legal replacements
  /// from [globalCardPool] that share colors and match the same roles.
  ///
  /// [formatFilter] is 'arena' or 'mtgo'.
  static Map<String, List<Map<String, dynamic>>> getSuggestions(
    List<ProxyCard> droppedCards, {
    String formatFilter = 'arena',
    int limit = 3,
  }) {
    final results = <String, List<Map<String, dynamic>>>{};

    for (final dropped in droppedCards) {
      final name     = dropped.name;
      final oracle   = dropped.scryfallData['oracle_text'] as String? ?? '';
      final typeLine = dropped.scryfallData['type_line']   as String? ?? '';
      final colors   = (dropped.scryfallData['color_identity'] as List?)
                           ?.cast<String>()
                           .toSet() ??
                       <String>{};
      final roles = getRoles(oracle, typeLine);

      // Skip lands — we don't suggest land replacements
      if (roles.length == 1 && roles.first == 'Land') {
        results[name] = [];
        continue;
      }

      // Search globalCardPool for matching replacements
      final candidates = <Map<String, dynamic>>[];

      for (final poolCard in globalCardPool) {
        // Format legality check
        final legalities = poolCard['legalities'] as Map<String, dynamic>?;
        if (legalities == null) continue;

        final bool isLegal;
        if (formatFilter == 'arena') {
          isLegal = legalities['timeless'] != 'not_legal' ||
                    legalities['standard'] == 'legal' ||
                    legalities['historic'] == 'legal';
        } else if (formatFilter == 'mtgo') {
          isLegal = legalities['vintage'] != 'not_legal' ||
                    poolCard['mtgo_id'] != null;
        } else {
          continue; // Paper cards shouldn't be "dropped"
        }
        if (!isLegal) continue;

        // Color identity check — replacement must fit within dropped card's colors
        final poolColors = (poolCard['color_identity'] as List?)
                               ?.cast<String>()
                               .toSet() ??
                           <String>{};
        if (!poolColors.every((c) => colors.contains(c))) continue;

        // Role match — at least one role must overlap
        final poolOracle   = poolCard['oracle_text'] as String? ?? '';
        final poolType     = poolCard['type_line']   as String? ?? '';
        final poolRoles    = getRoles(poolOracle, poolType);
        final hasOverlap   = roles.any((r) => poolRoles.contains(r));
        if (!hasOverlap) continue;

        // Don't suggest the same card
        final poolName = poolCard['name'] as String? ?? '';
        if (poolName.toLowerCase() == name.toLowerCase()) continue;

        candidates.add(poolCard);
        if (candidates.length >= limit) break;
      }

      results[name] = candidates;
    }

    return results;
  }
}
