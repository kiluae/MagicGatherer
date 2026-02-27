import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Pure-Dart headless engine — no Flutter imports.
/// Handles RNG identity generation, Scryfall query construction, and result parsing.
class ScryfallEngine {
  static const _base = 'https://api.scryfall.com';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  final http.Client _client;

  ScryfallEngine({http.Client? client}) : _client = client ?? http.Client();

  // ── 1. RNG Identity ────────────────────────────────────────────────────────

  /// Generates a color identity string.
  /// For each color NOT overridden by [overrides], randomly decide to include it.
  /// Returns "c" if all five evaluate to false.
  String generateIdentity(Map<String, bool> overrides) {
    final rng = Random();
    const colors = ['W', 'U', 'B', 'R', 'G'];
    final result = <String>[];
    for (final c in colors) {
      final forced = overrides[c];
      if (forced != null) {
        if (forced) result.add(c);
      } else {
        if (rng.nextBool()) result.add(c);
      }
    }
    return result.isEmpty ? 'c' : result.join();
  }

  // ── 2. Query Builder + 3. Bulletproof Parsing ─────────────────────────────

  /// Fetches commanders matching [identity], [maxCmc], and [sortType] from Scryfall.
  /// Shuffles the first page and returns the first 5 results.
  Future<List<Map<String, dynamic>>> fetchCommanders(
      String identity, int maxCmc, String sortType) async {
    await Future.delayed(const Duration(milliseconds: 100));

    final uri = Uri.parse('$_base/cards/search').replace(queryParameters: {
      'q': 'is:commander+id<=$identity+cmc<=$maxCmc',
      'order': sortType,
    });

    final resp = await _client.get(uri, headers: _headers);
    if (resp.statusCode != 200) return [];

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (json['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // 4. Randomization — shuffle first page, return top 5
    data.shuffle();
    final top5 = data.take(5).toList();

    // Normalize each card to include a guaranteed image URL
    return top5.map((card) {
      final imageUrl = _getImageUrl(card);
      return {...card, '__image_url': imageUrl};
    }).toList();
  }

  /// Safely extracts the normal image URL from a card, handling double-faced cards.
  String _getImageUrl(Map<String, dynamic> card) {
    if (card.containsKey('image_uris')) {
      return card['image_uris']['normal'] as String? ?? '';
    }
    final faces = card['card_faces'] as List?;
    if (faces != null && faces.isNotEmpty) {
      final front = faces[0] as Map<String, dynamic>;
      return front['image_uris']?['normal'] as String? ?? '';
    }
    return '';
  }
}
