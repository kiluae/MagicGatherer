import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/card_models.dart';

/// Rate-limited Scryfall API client.
/// Enforces a minimum 100ms gap between requests (Scryfall's guideline).
class ScryfallService {
  static const String _base = 'https://api.scryfall.com';
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _rateLimit() async {
    final gap = DateTime.now().difference(_lastRequest);
    if (gap.inMilliseconds < 100) {
      await Future.delayed(Duration(milliseconds: 100 - gap.inMilliseconds));
    }
    _lastRequest = DateTime.now();
  }

  Future<http.Response> _get(Uri uri) async {
    await _rateLimit();
    return http.get(uri, headers: _headers);
  }

  Future<http.Response> _post(Uri uri, Map<String, dynamic> body) async {
    await _rateLimit();
    return http.post(uri,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body));
  }

  // ── Card lookup ────────────────────────────────────────────────────────────

  /// Fuzzy name lookup — returns null if not found.
  Future<ScryfallCard?> getCardByName(String name) async {
    final uri = Uri.parse('$_base/cards/named')
        .replace(queryParameters: {'fuzzy': name});
    final resp = await _get(uri);
    if (resp.statusCode != 200) return null;
    return ScryfallCard.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  // ── Collection batch fetch (up to 75 per call) ────────────────────────────

  /// Fetches a list of named cards in batches of 75.
  /// Returns all found cards; silently skips not-found ones.
  Future<List<ScryfallCard>> getCollection(
    List<String> names, {
    void Function(String msg)? onLog,
    void Function(double pct)? onProgress,
    String formatFilter = 'paper',
  }) async {
    final results = <ScryfallCard>[];
    // De-dup while preserving quantity
    final quantities = <String, int>{};
    for (final n in names) {
      quantities[n.toLowerCase()] = (quantities[n.toLowerCase()] ?? 0) + 1;
    }
    final unique = quantities.keys.toList();
    const batchSize = 75;
    final total = unique.length;
    var processed = 0;

    for (var i = 0; i < unique.length; i += batchSize) {
      final batch = unique.sublist(i, (i + batchSize).clamp(0, unique.length));
      final payload = {
        'identifiers': batch.map((n) => {'name': n}).toList(),
      };
      final resp = await _post(
          Uri.parse('$_base/cards/collection'), payload);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        for (final cardJson in (data['data'] as List)) {
          final card = ScryfallCard.fromJson(
            cardJson as Map<String, dynamic>,
            quantity: quantities[(cardJson['name'] as String).toLowerCase()] ?? 1,
          );
          // Format filtering
          if (formatFilter == 'arena' && !card.isLegalInArena) {
            onLog?.call('Skipped (not on Arena): ${card.name}');
            continue;
          }
          if (formatFilter == 'mtgo' && !card.isLegalInMtgo) {
            onLog?.call('Skipped (not on MTGO): ${card.name}');
            continue;
          }
          results.add(card);
        }
        // Report not-found
        for (final name in (data['not_found'] as List? ?? [])) {
          onLog?.call('Not found: ${(name as Map)['name']}');
        }
      } else {
        onLog?.call('Batch error (HTTP ${resp.statusCode})');
      }
      processed += batch.length;
      onProgress?.call(processed / total);
    }
    return results;
  }

  // ── Full-text search ───────────────────────────────────────────────────────

  /// Scryfall syntax search — returns up to `maxPages` pages (175 cards/page).
  Future<List<ScryfallCard>> search(
    String query, {
    int maxPages = 3,
    String? formatFilter,
  }) async {
    final results = <ScryfallCard>[];
    String? nextPage = Uri.parse('$_base/cards/search')
        .replace(queryParameters: {
      'q': '$query${formatFilter != null ? " game:$formatFilter" : ""}',
      'order': 'name',
    }).toString();

    int page = 0;
    while (nextPage != null && page < maxPages) {
      final resp = await _get(Uri.parse(nextPage));
      if (resp.statusCode != 200) break;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      for (final c in (data['data'] as List)) {
        results.add(ScryfallCard.fromJson(c as Map<String, dynamic>));
      }
      nextPage = data['next_page'] as String?;
      page++;
    }
    return results;
  }

  // ── Discovery (Discovery Logic from Python discovery.py) ──────────────────

  /// Fetches a random commander card using Scryfall search.
  Future<Commander?> getRandomCommander({
    Set<String> colors = const {},
    String format = 'paper',
  }) async {
    String q = 'is:commander';
    if (colors.isNotEmpty) {
      q += ' color:${colors.join('')}';
    }
    if (format == 'arena') {
      q += ' game:arena';
    } else if (format == 'mtgo') {
      q += ' game:mtgo';
    }

    final uri = Uri.parse('$_base/cards/search').replace(queryParameters: {
      'q': q,
      'order': 'random',
    });

    final resp = await _get(uri);
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final cards = data['data'] as List?;
    if (cards == null || cards.isEmpty) return null;

    final picked = cards.first as Map<String, dynamic>;
    return _toCommander(picked);
  }

  /// Streams pages of commanders for a given set of filters.
  Stream<List<Commander>> browseCommanders({
    Set<String> colors = const {},
    String format = 'paper',
  }) async* {
    String q = 'is:commander';
    if (colors.isNotEmpty) {
      q += ' color:${colors.join('')}';
    }
    if (format == 'arena') {
      q += ' game:arena';
    } else if (format == 'mtgo') {
      q += ' game:mtgo';
    }

    String? nextUrl = Uri.parse('$_base/cards/search').replace(queryParameters: {
      'q': q,
      'order': 'name',
    }).toString();

    while (nextUrl != null) {
      final resp = await _get(Uri.parse(nextUrl));
      if (resp.statusCode != 200) break;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final cards = data['data'] as List?;
      if (cards != null) {
        yield cards.map((c) => _toCommander(c as Map<String, dynamic>)).toList();
      }
      nextUrl = data['next_page'] as String?;
    }
  }

  Commander _toCommander(Map<String, dynamic> card) {
    final imgUris = card['image_uris'] as Map<String, dynamic>?;
    return Commander(
      name: card['name'] as String? ?? '',
      slug: (card['name'] as String? ?? '').toLowerCase().replaceAll(RegExp(r"[^a-z0-9]+"), '-'),
      imageUri: imgUris?['normal'] as String?,
      colorIdentity: (card['color_identity'] as List?)?.cast<String>() ?? [],
    );
  }
}
