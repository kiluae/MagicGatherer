import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/card_models.dart';

/// EDHREC JSON API client.
/// No proxy needed — desktop Dart HTTP calls any URL freely.
class EdhrecService {
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };
  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _rateLimit() async {
    final gap = DateTime.now().difference(_lastRequest);
    if (gap.inMilliseconds < 150) {
      await Future.delayed(Duration(milliseconds: 150 - gap.inMilliseconds));
    }
    _lastRequest = DateTime.now();
  }

  String _toSlug(String name) => name
      .toLowerCase()
      .replaceAll("'", '')
      .replaceAll(',', '')
      .replaceAll(' ', '-');

  // ── Commander page (for Deck Doctor) ──────────────────────────────────────

  /// Returns raw cardlists from EDHREC for a given commander.
  Future<EdhrecCommanderPage?> getCommanderPage(String commanderName) async {
    await _rateLimit();
    final slug = _toSlug(commanderName);
    final uri = Uri.parse(
        'https://json.edhrec.com/pages/commanders/$slug.json');
    final resp = await http.get(uri, headers: _headers);
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final cardlists = data['container']?['json_dict']?['cardlists'] as List?
        ?? data['cardlists'] as List?
        ?? [];

    return EdhrecCommanderPage(
      commanderName: commanderName,
      cardlists: cardlists.cast<Map<String, dynamic>>(),
    );
  }

}

// ── Supporting models ─────────────────────────────────────────────────────────

class EdhrecCommanderPage {
  final String commanderName;
  final List<Map<String, dynamic>> cardlists;

  const EdhrecCommanderPage({
    required this.commanderName,
    required this.cardlists,
  });

  /// Parses each cardlist and maps to EdhrecCard with functional symbol.
  List<EdhrecCard> toEdhrecCards() {
    final seen = <String, EdhrecCard>{};
    const genericSymbols = {'Card', '♟', 'E', 'A', 'I', '★'};

    for (final list in cardlists) {
      final category = list['header'] as String? ?? '';
      final symbol = _symbolForCategory(category);

      for (final c in (list['cardviews'] as List? ?? [])) {
        final card = c as Map<String, dynamic>;
        final name = card['name'] as String?;
        if (name == null) continue;
        // Keep the most specific symbol
        final existing = seen[name];
        if (existing == null ||
            (genericSymbols.contains(existing.symbol) && !genericSymbols.contains(symbol))) {
          seen[name] = EdhrecCard(
            name: name,
            category: category,
            symbol: symbol,
            imageUri: card['image_uris']?['normal'] as String?,
          );
        }
      }
    }
    return seen.values.toList();
  }

  static String _symbolForCategory(String cat) {
    final low = cat.toLowerCase();
    if (_any(low, ['draw', 'cantrip', 'loot', 'card advantage', 'divination', 'impulse', 'cycle'])) return 'D';
    if (_any(low, ['ramp', 'mana artifact', 'mana rock', 'acceleration', 'mana fix', 'mana base'])) return 'M';
    if (_any(low, ['removal', 'exile', 'destroy', 'kill spell', 'spot removal', 'targeted', 'interaction'])) return 'R';
    if (_any(low, ['board wipe', 'sweeper', 'wrath', 'mass removal'])) return 'W';
    if (_any(low, ['counter', 'protection', 'stax', 'tax'])) return 'X';
    if (_any(low, ['tutor', 'toolbox'])) return 'G';
    if (low.contains('land')) return 'L';
    if (low.contains('synergy') || low.contains('engine')) return 'S';
    if (_any(low, ['top card', 'staple', 'new card', 'popular'])) return 'T';
    if (low.contains('creature')) return '♟';
    if (low.contains('planeswalker')) return '★';
    if (low.contains('enchantment')) return 'E';
    if (low.contains('artifact')) return 'A';
    if (low.contains('instant') || low.contains('sorcery')) return 'I';
    return 'Card';
  }

  static bool _any(String haystack, List<String> needles) =>
      needles.any((n) => haystack.contains(n));
}
