import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/card_models.dart';

/// Caches the full Scryfall commander list locally.
///
/// Refresh strategy: on startup, call Scryfall's commander search with
/// `page=1&per_page=1` to read `total_cards`. If that count matches the
/// stored count, the local cache is still valid — skip the download.
/// If the count differs (new sets released), re-download the full list.
class CommanderCacheService {
  static const _cacheFile  = 'commanders_cache.json';
  static const _metaFile   = 'commanders_meta.json';
  static const _headers    = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'application/json',
  };
  static const _query      = 'is:commander legal:commander';

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns cached commanders (refreshes only if Scryfall count changed).
  Future<List<Commander>> getCommanders({
    void Function(String msg)? onStatus,
  }) async {
    final cacheDir  = await _cacheDir();
    final cacheF    = File('$cacheDir/$_cacheFile');
    final metaF     = File('$cacheDir/$_metaFile');

    // 1. Check live count from Scryfall (cheap — 1-card page)
    final liveCount = await _fetchLiveCount();
    final storedCount = await _loadStoredCount(metaF);

    if (liveCount != null && storedCount == liveCount && cacheF.existsSync()) {
      // Cache is still valid
      onStatus?.call('Commander cache up to date ($liveCount commanders).');
      return _loadCache(cacheF);
    }

    // 2. Count mismatch (or no cache) → full download
    onStatus?.call('Updating commander list from Scryfall '
        '(${storedCount ?? 0} → ${liveCount ?? '?'} commanders)...');
    final commanders = await _downloadAll(onStatus: onStatus);

    // 3. Persist
    await _saveCache(cacheF, commanders);
    if (liveCount != null) await _saveMeta(metaF, liveCount);

    return commanders;
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  /// Fetches just the first card to read `total_cards` (the checksum).
  Future<int?> _fetchLiveCount() async {
    try {
      final uri = Uri.parse('https://api.scryfall.com/cards/search')
          .replace(queryParameters: {'q': _query, 'page': '1'});
      final resp = await http.get(uri, headers: _headers);
      if (resp.statusCode != 200) return null;
      return (jsonDecode(resp.body) as Map)['total_cards'] as int?;
    } catch (e) {
      // onStatus not available in this scope
      return null; // Offline — fall back to cache
    }
  }

  Future<int?> _loadStoredCount(File metaF) async {
    if (!metaF.existsSync()) return null;
    try {
      final m = jsonDecode(await metaF.readAsString()) as Map;
      return m['total_cards'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveMeta(File metaF, int count) async {
    await metaF.writeAsString(jsonEncode({'total_cards': count}));
  }

  /// Downloads all Scryfall commander pages.
  Future<List<Commander>> _downloadAll({
    void Function(String msg)? onStatus,
  }) async {
    final commanders = <Commander>[];
    String? nextPage = Uri.parse('https://api.scryfall.com/cards/search')
        .replace(queryParameters: {'q': _query, 'order': 'name'})
        .toString();
    int page = 0;

    while (nextPage != null) {
      await Future.delayed(const Duration(milliseconds: 100)); // rate limit
      final resp = await http.get(Uri.parse(nextPage), headers: _headers);
      if (resp.statusCode != 200) break;

      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      for (final c in (data['data'] as List)) {
        final m = c as Map<String, dynamic>;
        final imgs = m['image_uris'] as Map<String, dynamic>?;
        commanders.add(Commander(
          name: m['name'] as String? ?? '',
          slug: (m['name'] as String? ?? '')
              .toLowerCase().replaceAll("'", '').replaceAll(',', '').replaceAll(' ', '-'),
          imageUri: imgs?['normal'] as String?,
          colorIdentity: (m['color_identity'] as List?)?.cast<String>() ?? [],
        ));
      }

      page++;
      onStatus?.call('Downloaded page $page (${commanders.length} commanders so far)...');
      nextPage = data['next_page'] as String?;
    }

    return commanders;
  }

  Future<List<Commander>> _loadCache(File f) async {
    final list = jsonDecode(await f.readAsString()) as List;
    return list.map((m) => Commander(
      name:          (m as Map)['name'] as String,
      slug:          m['slug'] as String,
      imageUri:      m['image_uri'] as String?,
      colorIdentity: (m['color_identity'] as List?)?.cast<String>() ?? [],
    )).toList();
  }

  Future<void> _saveCache(File f, List<Commander> commanders) async {
    await f.writeAsString(jsonEncode(commanders.map((c) => {
      'name': c.name,
      'slug': c.slug,
      'image_uri': c.imageUri,
      'color_identity': c.colorIdentity,
    }).toList()));
  }

  Future<String> _cacheDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/magicgatherer');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }
}
