import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/card_models.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../services/scryfall_repository.dart';
import '../services/scryfall_service.dart';
import '../services/edhrec_service.dart';

class DeckBuilderProvider extends ChangeNotifier {
  // ── Input state ───────────────────────────────────────────────────────────
  String rawText = '';

  // ── Parsed deck ───────────────────────────────────────────────────────────
  List<ProxyCard> parsedDeck = [];

  // ── Generation state ──────────────────────────────────────────────────────
  bool    isGenerating = false;
  bool    isFetching   = false;
  String  progressText = '';
  Uint8List? lastPdfBytes;

  // ── Scryfall / EDHREC services ────────────────────────────────────────────
  final _scryfall = ScryfallService();
  final _edhrec   = EdhrecService();

  // ── Parse (Pasted List tab) ──────────────────────────────────────────────
  void parseDecklist() {
    parsedDeck = DeckParser.parseTxt(rawText, globalCardPool);
    progressText = parsedDeck.isEmpty
        ? 'No cards matched — is the local database loaded?'
        : '${parsedDeck.fold(0, (s, c) => s + c.quantity)} cards '
            '(${parsedDeck.length} unique)';
    notifyListeners();
  }

  // ── Commander Lookup (EDHREC) ─────────────────────────────────────────────
  Future<void> fetchFromEdhrec(String commanderName) async {
    if (isFetching) return;
    isFetching   = true;
    progressText = 'Fetching EDHREC average for $commanderName…';
    notifyListeners();

    try {
      final page = await _edhrec.getCommanderPage(commanderName);
      if (page == null) {
        progressText = 'Commander not found on EDHREC.';
        return;
      }

      final cardNames = page.toEdhrecCards().map((c) => c.name).toList();
      progressText = 'Found ${cardNames.length} cards — querying Scryfall…';
      notifyListeners();

      final scryfallCards = await _scryfall.getCollection(
        cardNames,
        onLog: (msg) {
          progressText = msg;
          notifyListeners();
        },
        onProgress: (_) {},
      );

      // Match to globalCardPool for full oracle data, fallback to Scryfall result
      final lookup = <String, Map<String, dynamic>>{};
      for (final c in globalCardPool) {
        if (c is Map<String, dynamic>) {
          lookup[(c['name'] as String? ?? '').toLowerCase()] = c;
        }
      }

      parsedDeck = scryfallCards.map((sc) {
        final poolData = lookup[sc.name.toLowerCase()];
        return ProxyCard(
          scryfallData: poolData ?? sc.toJson(),
          quantity: sc.quantity,
        );
      }).toList();

      progressText =
          '${parsedDeck.fold(0, (s, c) => s + c.quantity)} cards fetched '
          '(${parsedDeck.length} unique) from EDHREC average';
    } catch (e) {
      progressText = 'Error: $e';
      debugPrint('[DeckBuilderProvider] fetchFromEdhrec error: $e');
    } finally {
      isFetching = false;
      notifyListeners();
    }
  }

  // ── Custom art override ───────────────────────────────────────────────────
  void setLocalImage(int index, String path) {
    if (index < 0 || index >= parsedDeck.length) return;
    parsedDeck[index].localImagePath = path;
    notifyListeners();
  }

  // ── Exports — all route through ExportEngine.saveFile ────────────────────
  Future<void> saveAsJSON() async {
    await ExportEngine.saveFile(
        fileName: 'deck.json',
        content: ExportEngine.toJSON(parsedDeck),
        bytes: null);
  }

  Future<void> saveAsCSV() async {
    await ExportEngine.saveFile(
        fileName: 'deck.csv',
        content: ExportEngine.toCSV(parsedDeck),
        bytes: null);
  }

  Future<void> saveAsMTGO() async {
    await ExportEngine.saveFile(
        fileName: 'deck.dek',
        content: ExportEngine.toMTGO(parsedDeck),
        bytes: null);
  }

  Future<({String text, List<String> skipped})> copyArenaClipboard() async {
    final skipped = <String>[];
    final text = ExportEngine.toArenaClipboard(parsedDeck, skipped);
    await Clipboard.setData(ClipboardData(text: text));
    return (text: text, skipped: skipped);
  }

  Future<void> copyToClipboard() =>
      Clipboard.setData(ClipboardData(text: ExportEngine.toClipboard(parsedDeck)));

  // ── PDF Generation (via Gather modal) ────────────────────────────────────
  Future<void> generateProxyPdf({
    String paperSize = 'letter',
    double bleedInches = 0.0,
    double cardSpacing = 0.05,
    int dpi = 300,
    bool preferMtgPics = false,
  }) async {
    if (parsedDeck.isEmpty || isGenerating) return;
    isGenerating = true;
    progressText = 'Starting PDF generation…';
    notifyListeners();

    try {
      final bytes = await ProxyGenerator.generatePdf(
        deck:          parsedDeck,
        paperSize:     paperSize,
        bleedInches:   bleedInches,
        cardSpacing:   cardSpacing,
        dpi:           dpi,
        preferMtgPics: preferMtgPics,
        onProgress: (msg) {
          progressText = msg;
          notifyListeners();
        },
      );
      lastPdfBytes = bytes;
      final saved = await ExportEngine.saveFile(
          fileName: 'proxies.pdf', content: '', bytes: bytes);
      progressText = saved ? 'PDF saved!' : 'Save cancelled.';
    } catch (e) {
      progressText = 'Error: $e';
      debugPrint('[DeckBuilderProvider] generateProxyPdf error: $e');
    } finally {
      isGenerating = false;
      notifyListeners();
    }
  }
}
