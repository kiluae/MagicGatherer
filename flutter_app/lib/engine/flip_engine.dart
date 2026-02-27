import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;

/// Pure-Dart headless engine — zero Flutter imports.
class CommanderFlipEngine {
  static const _base = 'https://api.scryfall.com';
  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };

  final http.Client _client;
  CommanderFlipEngine({http.Client? client}) : _client = client ?? http.Client();

  // ── MTG Lore Name Dictionary ───────────────────────────────────────────────

  static String getIdentityName(String identity) {
    const names = <String, String>{
      'c': 'Colorless',
      'W': 'Mono-White', 'U': 'Mono-Blue', 'B': 'Mono-Black',
      'R': 'Mono-Red',   'G': 'Mono-Green',
      'WU': 'Azorius',  'UB': 'Dimir',   'BR': 'Rakdos',
      'RG': 'Gruul',    'WG': 'Selesnya','WB': 'Orzhov',
      'UR': 'Izzet',    'BG': 'Golgari', 'WR': 'Boros',
      'UG': 'Simic',
      'WUB': 'Esper',  'UBR': 'Grixis', 'BRG': 'Jund',
      'WRG': 'Naya',   'WUG': 'Bant',   'WBG': 'Abzan',
      'WUR': 'Jeskai', 'UBG': 'Sultai', 'WBR': 'Mardu',
      'URG': 'Temur',
      'WUBR': 'Yore-Tiller', 'UBRG': 'Glint-Eye',
      'WBRG': 'Dune-Brood',  'WURG': 'Ink-Treader',
      'WUBG': 'Witch-Maw',
      'WUBRG': 'Five-Color',
    };
    return names[identity] ?? 'Unknown Combination';
  }

  // ── EDHREC URL Generator ───────────────────────────────────────────────────

  static String generateEdhrecUrl(String commanderName) {
    final formatted = commanderName
        .toLowerCase()
        .replaceAll(RegExp(r"[^a-z0-9\s-]"), '')
        .replaceAll(RegExp(r'\s+'), '-');
    return 'https://edhrec.com/commanders/$formatted';
  }

  // ── API Query ──────────────────────────────────────────────────────────────

  /// Fetches commanders from Scryfall.
  ///
  /// [poolTier]: controls the Scryfall ordering / population source.
  ///   'edhrec_top'    → order:edhrec dir:asc  (Most Popular)
  ///   'edhrec_fringe' → order:edhrec dir:desc (Least Popular)
  ///   'new'           → order:released dir:desc
  ///   'chaos'         → order:random
  ///
  /// [localSort]: client-side sort applied after fetch.
  ///   Stored in provider; UI uses this label only (engine sorts via poolTier).
  ///
  /// [allowPartialColors]: false → id=$identity (exact), true → id<=$identity.
  /// [maxReturns]: 0 = All (return entire first page).
  Future<List<Map<String, dynamic>>> fetchCommanders({
    required String identity,
    required int maxCmc,
    required String poolTier,
    required String localSort,
    required int maxReturns,
    required bool allowPartialColors,
    required bool includePartners,
  }) async {
    final String sortQuery = switch (poolTier) {
      'edhrec_top'    => 'order:edhrec+dir:asc',
      'edhrec_fringe' => 'order:edhrec+dir:desc',
      'new'           => 'order:released+dir:desc',
      'chaos'         => 'order:random',
      _               => 'order:edhrec+dir:asc',
    };

    // Build color/partner clause — must be grouped so is:commander applies
    // to BOTH sides of the OR.
    final String colorQuery;
    if (allowPartialColors) {
      colorQuery = 'id<=$identity';
    } else if (includePartners) {
      colorQuery = '(id=$identity OR (is:partner id<=$identity))';
    } else {
      colorQuery = 'id=$identity';
    }

    final String finalQuery =
        'q=is:commander+$colorQuery+cmc<=$maxCmc+$sortQuery';
    final url = '$_base/cards/search?$finalQuery';

    final resp = await _client.get(Uri.parse(url), headers: _headers);
    if (resp.statusCode != 200) return [];

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = (json['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

    // For chaos, Scryfall already randomised the order; for all other tiers,
    // cryptographically shuffle the full page so we never surface the same
    // top-N cards repeatedly.
    data.shuffle(Random.secure());

    final parsed = <Map<String, dynamic>>[];
    for (final card in data) {
      final imageUrl = _imageUrl(card);
      if (imageUrl == null) continue;
      parsed.add({...card, '__image_url': imageUrl});
    }

    return maxReturns == 0 ? parsed : parsed.take(maxReturns).toList();
  }

  // ── Image Helpers ──────────────────────────────────────────────────────────

  String? _imageUrl(Map<String, dynamic> card) {
    if (card['image_uris'] != null) {
      return card['image_uris']['normal'] as String?;
    }
    if (card['card_faces'] != null) {
      final faces = card['card_faces'] as List?;
      if (faces != null && faces.isNotEmpty) {
        final front = faces[0] as Map<String, dynamic>;
        if (front['image_uris'] != null) {
          return front['image_uris']['normal'] as String?;
        }
      }
    }
    return null;
  }
}
