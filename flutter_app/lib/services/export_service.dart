import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import '../models/card_models.dart';
import '../engine/image_engine.dart';

/// Handles all file exports: PDF proxies, CSV, JSON, MTGO .dek, Arena clipboard string.
class ExportService {
  static const _cardW = 2.5 * PdfPageFormat.inch;
  static const _cardH = 3.5 * PdfPageFormat.inch;

  // ── PDF Proxy Sheet ────────────────────────────────────────────────────────

  /// Generates a PDF proxy sheet and returns the saved file path.
  Future<String> exportPdf(
    List<ScryfallCard> cards,
    String saveDir,
    String prefix, {
    PdfPageFormat pageFormat = PdfPageFormat.letter,
    bool drawCropMarks = true,
    void Function(String msg)? onLog,
    void Function(double pct)? onProgress,
  }) async {
    final doc = pw.Document();
    final imageWidgets = <pw.Widget>[];

    // Expand by quantity and collect both faces of DFCs
    final expanded = <ScryfallCard>[];
    for (final card in cards) {
      for (var i = 0; i < card.quantity; i++) {
        expanded.add(card);
      }
    }

    for (var i = 0; i < expanded.length; i++) {
      final card = expanded[i];
      onProgress?.call(0.1 + 0.7 * (i / expanded.length));

      final urls = _imageUrls(card);
      for (final url in urls) {
        try {
          final resp = await http.get(Uri.parse(url));
          if (resp.statusCode == 200) {
            final img = pw.MemoryImage(resp.bodyBytes);
            imageWidgets.add(pw.Image(img,
                width: _cardW, height: _cardH, fit: pw.BoxFit.fill));
          }
        } catch (_) {
          onLog?.call('Could not download image for ${card.name}');
        }
      }
    }

    // Layout: 3×3 grid per page
    const cols = 3;
    const rows = 3;
    const perPage = cols * rows;

    for (var p0 = 0; p0 < imageWidgets.length; p0 += perPage) {
      final slice = imageWidgets.sublist(
          p0, (p0 + perPage).clamp(0, imageWidgets.length));

      // Pad to full grid
      while (slice.length < perPage) {
        slice.add(pw.SizedBox(width: _cardW, height: _cardH));
      }

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        margin: const pw.EdgeInsets.all(18),
        build: (_) => pw.GridView(
          crossAxisCount: cols,
          childAspectRatio: _cardW / _cardH,
          children: slice,
        ),
      ));
    }

    final outPath = p.join(saveDir, '$prefix.pdf');
    final file = File(outPath);
    await file.writeAsBytes(await doc.save());
    onLog?.call('PDF saved: $outPath');
    onProgress?.call(1.0);
    return outPath;
  }

  // ── CSV ────────────────────────────────────────────────────────────────────

  Future<String> exportCsv(
      List<ScryfallCard> cards, String saveDir, String prefix) async {
    final buf = StringBuffer();
    buf.writeln('quantity,name,type_line,color_identity,games');
    for (final c in cards) {
      buf.writeln(
        '${c.quantity},"${c.name}","${c.typeLine}",'
        '"${c.colorIdentity.join('')}","${c.games.join('/')}"',
      );
    }
    final path = p.join(saveDir, '$prefix.csv');
    await File(path).writeAsString(buf.toString());
    return path;
  }

  // ── JSON ───────────────────────────────────────────────────────────────────

  Future<String> exportJson(
      List<ScryfallCard> cards, String saveDir, String prefix) async {
    final path = p.join(saveDir, '$prefix.json');
    const encoder = JsonEncoder.withIndent('  ');
    await File(path).writeAsString(
        encoder.convert(cards.map((c) => c.toJson()).toList()));
    return path;
  }

  // ── MTGO .dek (XML) ────────────────────────────────────────────────────────

  Future<String> exportMtgoDek(
      List<ScryfallCard> cards, String saveDir, String prefix) async {
    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<Deck xmlns:xsd="http://www.w3.org/2001/XMLSchema"'
               ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
      ..writeln('  <NetDeckID>0</NetDeckID>')
      ..writeln('  <PreconstructedDeckID>0</PreconstructedDeckID>');
    for (final c in cards) {
      // Use Scryfall mtgo_id if present, else 0 (MTGO will match by Name)
      final catId = c.mtgoId ?? 0;
      final name  = c.name
          .replaceAll('&', '&amp;')
          .replaceAll('"', '&quot;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;');
      for (var i = 0; i < c.quantity; i++) {
        sb.writeln('  <Cards CatID="$catId" Quantity="1"'
            ' Sideboard="false" Name="$name" />');
      }
    }
    sb.writeln('</Deck>');
    final path = p.join(saveDir, '$prefix.dek');
    await File(path).writeAsString(sb.toString());
    return path;
  }

  // ── Arena clipboard string ─────────────────────────────────────────────────

  String arenaClipboardString(List<ScryfallCard> cards) {
    final buf = StringBuffer();
    for (final c in cards) {
      buf.writeln('${c.quantity} ${c.name}');
    }
    return buf.toString().trim();
  }

  // ── Decklist text file ────────────────────────────────────────────────────

  Future<String> exportDecklist(
      List<ScryfallCard> cards, String saveDir, String prefix) async {
    final buf = StringBuffer();
    for (final c in cards) {
      buf.writeln('${c.quantity} ${c.name}');
    }
    final path = p.join(saveDir, '$prefix.txt');
    await File(path).writeAsString(buf.toString());
    return path;
  }

  // ── Image folder export ────────────────────────────────────────────────────

  Future<void> exportImages(
    List<ScryfallCard> cards,
    String saveDir,
    String prefix, {
    void Function(String msg)? onLog,
    void Function(double pct)? onProgress,
  }) async {
    final imgDir = Directory(p.join(saveDir, '${prefix}_images'));
    if (!imgDir.existsSync()) imgDir.createSync(recursive: true);

    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      onProgress?.call(i / cards.length);
      final urls = _imageUrls(card);
      for (var fi = 0; fi < urls.length; fi++) {
        try {
          final resp = await http.get(Uri.parse(urls[fi]));
          if (resp.statusCode == 200) {
            final faceSuffix = urls.length > 1 ? '_face$fi' : '';
            final filename = '${_sanitize(card.name)}$faceSuffix.png';
            await File(p.join(imgDir.path, filename))
                .writeAsBytes(resp.bodyBytes);
          }
        } catch (e) {
          onLog?.call('Image error for ${card.name}: $e');
        }
      }
    }
    onProgress?.call(1.0);
    onLog?.call('Images saved to ${imgDir.path}');
  }

  String _sanitize(String name) =>
      name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();


  List<String> _imageUrls(ScryfallCard card) {
    // DFC: both faces
    if (card.cardFaces != null) {
      return card.cardFaces!
          .map((f) => f.bestImageUri)
          .where((u) => u.isNotEmpty)
          .toList();
    }
    final url = card.bestImageUri;
    return url.isNotEmpty ? [url] : [];
  }
}

// ── Deck Parser ────────────────────────────────────────────────────────────────

/// Parses a plain-text decklist (one card per line, formats like "1x Sol Ring",
/// "1 Sol Ring", or "Sol Ring") against the offline [globalCardPool].
class DeckParser {
  static final _lineRe = RegExp(r'^(\d+)[xX]?\s+(.+)$');

  /// Returns a [ProxyCard] list, skipping lines that don't match any card name.
  static List<ProxyCard> parseTxt(
      String txt, List<dynamic> globalCardPool) {
    // Build a fast lowercase-name lookup from the pool
    final lookup = <String, Map<String, dynamic>>{};
    for (final card in globalCardPool) {
      if (card is Map<String, dynamic>) {
        final name = (card['name'] as String? ?? '').toLowerCase();
        lookup[name] = card;
      }
    }

    final results = <ProxyCard>[];
    for (final rawLine in txt.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('//')) continue;

      int qty = 1;
      String cardName = line;

      final m = _lineRe.firstMatch(line);
      if (m != null) {
        qty      = int.tryParse(m.group(1)!) ?? 1;
        cardName = m.group(2)!.trim();
      }

      final data = lookup[cardName.toLowerCase()];
      if (data != null) {
        results.add(ProxyCard(scryfallData: data, quantity: qty));
      }
    }
    return results;
  }
}

// ── Export Engine (ProxyCard pipeline) ────────────────────────────────────────

/// Static export helpers operating on [ProxyCard] lists.
/// Produces strings ready to write to file or copy to clipboard.
class ExportEngine {
  /// Standard MTGO XML `.dek` format with real CatIDs from Scryfall mtgo_id.
  static String toMTGO(List<ProxyCard> deck) {
    String xmlEsc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');

    final sb = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<Deck xmlns:xsd="http://www.w3.org/2001/XMLSchema"'
          ' xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">')
      ..writeln('  <NetDeckID>0</NetDeckID>')
      ..writeln('  <PreconstructedDeckID>0</PreconstructedDeckID>');
    for (final c in deck) {
      final catId = (c.scryfallData['mtgo_id'] as int?) ?? 0;
      for (var i = 0; i < c.quantity; i++) {
        sb.writeln('  <Cards CatID="$catId" Quantity="1"'
            ' Sideboard="false" Name="${xmlEsc(c.name)}" />');
      }
    }
    sb.writeln('</Deck>');
    return sb.toString();
  }

  /// CSV — data-dense: Quantity, Name, ManaCost, TypeLine, Colors, CMC, Set, Price, ArenaLegal.
  static String toCSV(List<ProxyCard> deck) {
    final sb = StringBuffer()
      ..writeln(
          'Quantity,Name,ManaCost,TypeLine,OracleText,Colors,CMC,Set,Rarity,PriceUSD,ArenaLegal');
    for (final c in deck) {
      final d = c.scryfallData;
      final name       = _csvEsc(c.name);
      final manaCost   = _csvEsc(d['mana_cost']   as String? ?? '');
      final typeLine   = _csvEsc(d['type_line']   as String? ?? '');
      final oracle     = _csvEsc(d['oracle_text'] as String? ?? '');
      final colors     = ((d['colors'] as List?)?.join('')) ?? '';
      final rarity     = d['rarity']   as String? ?? '';
      final arenaLegal = ((d['legalities'] as Map?)?['arena'] == 'legal').toString();
      sb.writeln(
          '${c.quantity},$name,$manaCost,$typeLine,$oracle,$colors,${c.cmc},'
          '"${c.setCode}",$rarity,${c.usdPrice},$arenaLegal');
    }
    return sb.toString();
  }

  /// JSON — full Scryfall data + quantity, with key fields promoted to top level.
  static String toJSON(List<ProxyCard> deck) {
    final list = deck.map((c) {
      final d = c.scryfallData;
      return {
        'quantity':         c.quantity,
        'name':             c.name,
        'mana_cost':        d['mana_cost'],
        'type_line':        d['type_line'],
        'oracle_text':      d['oracle_text'],
        'colors':           d['colors'],
        'color_identity':   d['color_identity'],
        'cmc':              c.cmc,
        'set':              c.setCode,
        'rarity':           d['rarity'],
        'collector_number': c.collectorNumber,
        'prices':           d['prices'],
        'arena_legality':   (d['legalities'] as Map?)?['arena'],
        'scryfall_uri':     d['scryfall_uri'],
      };
    }).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Plain-text Arena clipboard — skips non-Arena cards, returns a skip report.
  ///
  /// [report] is populated with the names of cards omitted due to Arena
  /// ineligibility. Caller should surface this to the user.
  static String toArenaClipboard(
      List<ProxyCard> deck, List<String> incompatibleCards) {
    incompatibleCards.clear();
    final sb = StringBuffer();
    for (final c in deck) {
      final legalities = c.scryfallData['legalities'] as Map?;
      final arenaLegal = legalities?['arena'] == 'legal';
      final typeLine   = c.scryfallData['type_line'] as String? ?? '';
      final isBasicLand = typeLine.contains('Basic Land');

      if (arenaLegal || isBasicLand) {
        sb.writeln('${c.quantity} ${c.name}');
      } else {
        incompatibleCards.add(c.name);
      }
    }
    return sb.toString().trim();
  }

  /// Plain-text clipboard list ("Nx Name") — no Arena filter.
  static String toClipboard(List<ProxyCard> deck) =>
      deck.map((c) => '${c.quantity}x ${c.name}').join('\n');

  /// Opens a native directory picker and batch-downloads card images.
  ///
  /// Creates `<chosen folder>/Images/` and saves each card as `card_name.png`.
  /// Uses MTGPics (1s delay) when [preferMtgPics] is true, falls back to Scryfall.
  static Future<bool> saveImages(
    List<ProxyCard> deck, {
    bool preferMtgPics = false,
    void Function(String)? onProgress,
  }) async {
    final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose Image Dump Folder');
    if (dir == null) return false;

    // Create Images sub-folder
    final imgDir = Directory('$dir/Images');
    imgDir.createSync(recursive: true);

    for (var i = 0; i < deck.length; i++) {
      final card = deck[i];
      onProgress?.call('Fetching ${i + 1}/${deck.length}: ${card.name}');

      Uint8List? bytes;

      // Custom art override
      if (card.localImagePath != null) {
        try { bytes = await File(card.localImagePath!).readAsBytes(); } catch (_) {}
      }

      // MTGPics first (if preferred)
      if (bytes == null && preferMtgPics) {
        bytes = await fetchMtgPicsImage(card.setCode, card.collectorNumber);
      }

      // Scryfall fallback
      if (bytes == null) {
        final url = getScryfallHighRes(card.scryfallData);
        if (url.isNotEmpty) {
          try {
            await Future.delayed(const Duration(milliseconds: 100));
            final resp = await http.get(Uri.parse(url));
            if (resp.statusCode == 200) bytes = resp.bodyBytes;
          } catch (_) {}
        }
      }

      if (bytes != null) {
        final safeName = card.name.replaceAll(RegExp(r'[\\/*?:"<>|]'), '');
        await File('${imgDir.path}/$safeName.png').writeAsBytes(bytes);
      } else {
        onProgress?.call('  ⚠ No image found for ${card.name}');
      }
    }
    onProgress?.call('Image dump complete → ${imgDir.path}');
    return true;
  }

  // ── File Save ─────────────────────────────────────────────────────────────

  /// Bulletproof "Save As" that always surfaces feedback via SnackBar.
  ///
  /// Shows a success message with the chosen path, or an error message on
  /// any failure. [content] is used for text files; [bytes] for binary files.
  static Future<void> triggerSave({
    required BuildContext context,
    required String defaultName,
    String? content,
    List<int>? bytes,
  }) async {
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: defaultName,
      );
      if (outputPath == null) return; // user cancelled — no feedback needed
      final file = File(outputPath);
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      } else if (content != null) {
        await file.writeAsString(content);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to $outputPath'),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export Error: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  /// Silent "Save As" — returns true/false, no UI feedback.
  /// Use [triggerSave] for interactive flows.
  static Future<bool> saveFile({
    required String fileName,
    required String content,
    required List<int>? bytes,
  }) async {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Your Magic:',
      fileName: fileName,
    );
    if (outputPath == null) return false;
    final file = File(outputPath);
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    } else {
      await file.writeAsString(content);
    }
    return true;
  }


  static String _csvEsc(String s) {
    final escaped = s.replaceAll('"', '""');
    return '"$escaped"';
  }
}
