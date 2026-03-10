import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/card_models.dart';

// ── Shared in-memory card pool ────────────────────────────────────────────────
/// Loaded from the oracle_cards bulk download. Populated by [syncDatabase].
List<Map<String, dynamic>> globalCardPool = [];

// ── Scryfall-compliant headers ─────────────────────────────────────────────────
const _headers = {
  'User-Agent': 'MagicGatherer/3.0.0',
  'Accept': 'application/json',
};

// ── Repository ─────────────────────────────────────────────────────────────────
class ScryfallRepository {
  /// Syncs the local oracle_cards database against Scryfall's Bulk Data API.
  ///
  /// 1. Fetches the bulk-data index to get the current `updated_at` timestamp
  ///    and the dynamic `download_uri`.
  /// 2. Compares against local `metadata.json`.
  ///    - Match → loads the existing `oracle_cards.json` from disk.
  ///    - Mismatch → streams the new file to disk, saves metadata, then loads.
  static Future<void> syncDatabase(void Function(String) onProgress) async {
    // Step 1: Fetch bulk-data index
    onProgress('Checking MTG database version...');
    final indexResp = await http.get(
      Uri.parse('https://api.scryfall.com/bulk-data'),
      headers: _headers,
    );
    if (indexResp.statusCode != 200) {
      onProgress('Failed to reach Scryfall (HTTP ${indexResp.statusCode}).');
      await _loadLocalPool(onProgress);
      return;
    }

    final index   = jsonDecode(indexResp.body) as Map<String, dynamic>;
    final objects = (index['data'] as List).cast<Map<String, dynamic>>();
    final bulk    = objects.firstWhere(
      (o) => o['type'] == 'oracle_cards',
      orElse: () => <String, dynamic>{},
    );

    if (bulk.isEmpty) {
      onProgress('Could not find oracle_cards bulk object.');
      await _loadLocalPool(onProgress);
      return;
    }

    final String updatedAt   = bulk['updated_at']   as String? ?? '';
    final String downloadUri = bulk['download_uri'] as String? ?? '';

    // Step 2: Compare timestamps
    final dir          = await getApplicationDocumentsDirectory();
    final metaFile     = File('${dir.path}/metadata.json');
    String? savedStamp;
    if (await metaFile.exists()) {
      try {
        final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        savedStamp = meta['updated_at'] as String?;
      } catch (_) {}
    }

    if (savedStamp == updatedAt) {
      // Local data is current
      onProgress('Loading local MTG database...');
      await _loadLocalPool(onProgress);
      return;
    }

    // Step 3: Stream new bulk file to disk
    onProgress('Downloading latest MTG database... This may take a moment.');
    final request = http.Request('GET', Uri.parse(downloadUri))
      ..headers.addAll(_headers);
    final streamedResp = await http.Client().send(request);

    final oracleFile = File('${dir.path}/oracle_cards.json');
    final sink       = oracleFile.openWrite();
    await streamedResp.stream.pipe(sink);
    await sink.close();

    // Save updated timestamp
    await metaFile.writeAsString(jsonEncode({'updated_at': updatedAt}));

    // Step 4: Load newly saved file into globalCardPool
    onProgress('Indexing MTG cards...');
    await _loadLocalPool(onProgress);
  }

  /// Loads `oracle_cards.json` from disk into [globalCardPool].
  static Future<void> _loadLocalPool(void Function(String) onProgress) async {
    try {
      final dir        = await getApplicationDocumentsDirectory();
      final oracleFile = File('${dir.path}/oracle_cards.json');
      if (!await oracleFile.exists()) {
        onProgress('No local database found. Please connect to download.');
        return;
      }
      final raw  = await oracleFile.readAsString();
      final list = jsonDecode(raw) as List;
      globalCardPool = list.cast<Map<String, dynamic>>();
      onProgress('Database ready (${globalCardPool.length} cards).');
    } catch (e) {
      onProgress('Error loading local database: $e');
    }
  }

  /// Multi-term, order-independent substring search against [globalCardPool].
  ///
  /// Splits [query] on whitespace and returns cards whose names contain
  /// ALL terms (case-insensitive). Returns at most 100 results.
  static List<Map<String, dynamic>> searchLocalCards(String query) {
    if (query.trim().isEmpty) return [];
    final terms = query
        .toLowerCase()
        .split(' ')
        .where((t) => t.isNotEmpty)
        .toList();
    return globalCardPool.where((card) {
      if (!ProxyCard.isPlayableCard(card)) return false;
      final name = (card['name'] as String? ?? '').toLowerCase();
      return terms.every((term) => name.contains(term));
    }).take(100).toList();
  }

  /// Fetch all official printings of a card by its oracle ID.
  /// Includes extras (tokens, emblems, art series) via `include:extras`.
  /// Falls back to exact name search for cards without an oracle_id.
  static Future<List<Map<String, dynamic>>> fetchPrintings(
      String oracleId, {String cardName = ''}) async {
    if (oracleId.isEmpty && cardName.isEmpty) return [];
    try {
      final query = oracleId.isNotEmpty
          ? 'oracleid:$oracleId'
          : '!"$cardName"';
      final url = Uri.parse(
          'https://api.scryfall.com/cards/search'
          '?order=released&q=$query+include:extras&unique=prints');
      final resp = await http.get(url, headers: _headers);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return List<Map<String, dynamic>>.from(data['data'] ?? []);
      }
    } catch (e) {
      // Silently fail — caller handles empty list
    }
    return [];
  }
}
