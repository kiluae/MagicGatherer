import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../engine/deck_doctor_engine.dart';
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
  List<String> notFoundList = [];

  // ── Format filter ─────────────────────────────────────────────────────────
  String selectedFormat = 'paper';

  void setFormat(String f) {
    selectedFormat = f;
    notifyListeners();
  }

  // ── Category filter ───────────────────────────────────────────────────────
  String activeFilter = 'Total';

  void setFilter(String f) {
    activeFilter = f;
    notifyListeners();
  }

  // ── Category counts (for diagnosis chips) ─────────────────────────────────
  int get landCount     => parsedDeck.where((c) => c.isLand).fold(0, (s, c) => s + c.quantity);
  int get creatureCount => parsedDeck.where((c) => c.isCreature).fold(0, (s, c) => s + c.quantity);
  int get spellCount    => parsedDeck.where((c) => c.isSpell).fold(0, (s, c) => s + c.quantity);
  int get rampCount     => parsedDeck.where((c) => c.isRamp).fold(0, (s, c) => s + c.quantity);
  int get drawCount     => parsedDeck.where((c) => c.isDraw).fold(0, (s, c) => s + c.quantity);
  int get removalCount  => parsedDeck.where((c) => c.isRemoval).fold(0, (s, c) => s + c.quantity);
  int get wipeCount     => parsedDeck.where((c) => c.isWipe).fold(0, (s, c) => s + c.quantity);

  // ── Computed: legality-driven views ────────────────────────────────────────
  List<ProxyCard> get legalCards =>
      parsedDeck.where((c) => c.isLegalIn(selectedFormat)).toList();

  List<ProxyCard> get droppedCards =>
      parsedDeck.where((c) => !c.isLegalIn(selectedFormat)).toList();

  DeckDiagnosis get diagnosis => DeckDoctorEngine.diagnose(legalCards);

  Map<String, List<Map<String, dynamic>>> get suggestions =>
      droppedCards.isNotEmpty
          ? DeckDoctorEngine.getSuggestions(droppedCards,
              formatFilter: selectedFormat)
          : {};

  /// Swap a dropped card for a suggested replacement.
  void swapSuggestion(String droppedName, Map<String, dynamic> replacement) {
    parsedDeck.removeWhere(
        (c) => c.name.toLowerCase() == droppedName.toLowerCase());
    parsedDeck.add(ProxyCard(scryfallData: replacement, quantity: 1));
    notifyListeners();
  }

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
    final result = DeckParser.parseTxt(rawText, globalCardPool);
    parsedDeck   = result.deck;
    notFoundList = result.notFound;

    if (parsedDeck.isEmpty) {
      progressText = 'No cards matched — is the local database loaded?';
    } else {
      final total = parsedDeck.fold(0, (s, c) => s + c.quantity);
      progressText = '$total cards (${parsedDeck.length} unique)';
      if (notFoundList.isNotEmpty) {
        progressText += ' · ${notFoundList.length} not found';
      }
    }
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
        lookup[(c['name'] as String? ?? '').toLowerCase()] = c;
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
