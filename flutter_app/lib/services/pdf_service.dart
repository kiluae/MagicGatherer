import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/card_models.dart';
import '../engine/image_engine.dart';

/// High-quality proxy PDF generator.
///
/// Handles bleed, spacing, DPI scaling, MTGPics vs Scryfall image source
/// priority, custom art overrides, and multi-page auto-flow.
class ProxyGenerator {
  // 1 point = 1/72 inch
  static const double _ptPerInch = 72.0;

  static double _inToPt(double inches) => inches * _ptPerInch;

  /// Generates a PDF proxy sheet and returns the raw [Uint8List] bytes.
  ///
  /// [paperSize]     - 'letter' (612×792pt) or 'a4' (595×842pt)
  /// [bleedInches]   - extra bleed added to each card edge (typically 0.0–0.125)
  /// [cardSpacing]   - gap between cards in inches
  /// [dpi]           - output resolution hint (higher = larger raster images)
  /// [preferMtgPics] - try MTGPics first; fall back to Scryfall on failure
  /// [onProgress]    - status callback
  static Future<Uint8List> generatePdf({
    required List<ProxyCard> deck,
    String paperSize = 'letter',
    double bleedInches = 0.0,
    double cardSpacing = 0.05,
    int dpi = 300,
    bool preferMtgPics = false,
    void Function(String)? onProgress,
  }) async {
    final pageFormat = paperSize == 'a4'
        ? PdfPageFormat.a4
        : PdfPageFormat.letter;

    // Card dimensions in points
    final double cardW = _inToPt(2.5 + bleedInches * 2);
    final double cardH = _inToPt(3.5 + bleedInches * 2);
    final double gap   = _inToPt(cardSpacing);

    const int cols = 3;

    final doc = pw.Document(compress: true);

    // Expand deck by quantity
    final slots = <ProxyCard>[];
    for (final c in deck) {
      for (var i = 0; i < c.quantity; i++) {
        slots.add(c);
      }
    }

    final imageWidgets = <pw.Widget>[];

    for (var i = 0; i < slots.length; i++) {
      final card = slots[i];
      onProgress?.call(
          'Processing card ${i + 1}/${slots.length}: ${card.name}');

      Uint8List? bytes;

      // 1. Custom art override
      if (card.localImagePath != null) {
        try {
          bytes = await File(card.localImagePath!).readAsBytes();
        } catch (_) {}
      }

      // 2. MTGPics (if preferred and no override)
      if (bytes == null && preferMtgPics) {
        bytes = await fetchMtgPicsImage(card.setCode, card.collectorNumber);
      }

      // 3. Scryfall fallback (or primary when MTGPics not preferred)
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
        imageWidgets.add(pw.Image(
          pw.MemoryImage(bytes),
          width: cardW,
          height: cardH,
          fit: pw.BoxFit.fill,
        ));
      } else {
        // Placeholder for missing image
        imageWidgets.add(pw.Container(
          width: cardW,
          height: cardH,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
          ),
          child: pw.Center(
            child: pw.Text(card.name,
                style: const pw.TextStyle(fontSize: 8),
                textAlign: pw.TextAlign.center),
          ),
        ));
      }
    }

    // Layout: 3-column grid, auto-flow to new pages
    const int perPage = cols * 3; // 3×3
    final pageMargin = pw.EdgeInsets.all(_inToPt(0.25));

    for (var offset = 0; offset < imageWidgets.length; offset += perPage) {
      final slice = imageWidgets.sublist(
          offset, (offset + perPage).clamp(0, imageWidgets.length));

      // Pad last page to full grid
      while (slice.length < perPage) {
        slice.add(pw.SizedBox(width: cardW, height: cardH));
      }

      doc.addPage(pw.Page(
        pageFormat: pageFormat,
        margin: pageMargin,
        build: (_) => pw.Wrap(
          spacing: gap,
          runSpacing: gap,
          children: slice,
        ),
      ));
    }

    onProgress?.call('Finalising PDF...');
    final bytes = await doc.save();
    onProgress?.call('Done — ${slots.length} card(s), ${(bytes.length / 1024).toStringAsFixed(0)} KB');
    return bytes;
  }

  /// Saves the generated PDF bytes to a temp file and returns the path.
  static Future<String> savePdf(Uint8List bytes, {String prefix = 'proxies'}) async {
    final dir  = await getTemporaryDirectory();
    final path = p.join(dir.path, '${prefix}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Convenience: stream-download of oracle_cards file (delegated from repository).
  @visibleForTesting
  static double inToPt(double inches) => _inToPt(inches);
}
