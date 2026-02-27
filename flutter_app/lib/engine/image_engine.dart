import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

// ── Scryfall High-Res Helper ──────────────────────────────────────────────────

/// Returns the best available Scryfall image URL for a raw card JSON map.
/// Priority: `png` → `large` → `normal`.
/// Handles double-faced cards (card_faces) safely.
String getScryfallHighRes(Map<String, dynamic> card) {
  // Direct image_uris present
  final imgUris = card['image_uris'] as Map<String, dynamic>?;
  if (imgUris != null) {
    return (imgUris['png'] ?? imgUris['large'] ?? imgUris['normal'])
            as String? ??
        '';
  }

  // Double-faced card — use front face image
  final faces = card['card_faces'] as List?;
  if (faces != null && faces.isNotEmpty) {
    final front = faces[0] as Map<String, dynamic>;
    final faceUris = front['image_uris'] as Map<String, dynamic>?;
    if (faceUris != null) {
      return (faceUris['png'] ?? faceUris['large'] ?? faceUris['normal'])
              as String? ??
          '';
    }
  }
  return '';
}

// ── MTGPics Scraper ────────────────────────────────────────────────────────────

const _scrapeHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      ' (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml',
};

/// Fetches card art bytes from mtgpics.com for a given set + collector number.
/// Returns `null` if not found or on any error.
///
/// ⚠️ MANDATORY 1-second delay before each request to prevent IP bans.
Future<Uint8List?> fetchMtgPicsImage(
    String setCode, String collectorNumber) async {
  // Rate-limit compliance — non-negotiable for mtgpics.com
  await Future.delayed(const Duration(seconds: 1));

  try {
    final pageUrl =
        'https://www.mtgpics.com/card?ref=${setCode.toLowerCase()}$collectorNumber';
    final pageResp =
        await http.get(Uri.parse(pageUrl), headers: _scrapeHeaders);
    if (pageResp.statusCode != 200) return null;

    final document = html_parser.parse(pageResp.body);

    // MTGPics stores the full-res art in an <img> inside div.card_pic
    final imgEl = document.querySelector('div.card_pic img') ??
        document.querySelector('img[src*="/pics/"]');
    if (imgEl == null) return null;

    String? src = imgEl.attributes['src'];
    if (src == null || src.isEmpty) return null;

    // Resolve relative URLs
    if (src.startsWith('/')) {
      src = 'https://www.mtgpics.com$src';
    }

    await Future.delayed(const Duration(seconds: 1)); // second delay for image fetch
    final imgResp = await http.get(Uri.parse(src), headers: _scrapeHeaders);
    if (imgResp.statusCode != 200) return null;
    return imgResp.bodyBytes;
  } catch (_) {
    return null;
  }
}
