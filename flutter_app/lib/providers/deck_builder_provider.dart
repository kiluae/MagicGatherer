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

  // ── Extras toggle (for Card Browser) ──────────────────────────────────────
  bool showExtras = false;

  void toggleExtras(bool v) {
    showExtras = v;
    notifyListeners();
  }

  // ── Category counts (for diagnosis chips) ─────────────────────────────────
  // Only count actual deck cards (exclude tokens/emblems)
  List<ProxyCard> get _mainDeck => parsedDeck.where((c) => !c.isTokenOrEmblem).toList();

  int get mainDeckCount => _mainDeck.fold(0, (s, c) => s + c.quantity);
  int get tokenCount    => parsedDeck.where((c) => c.isTokenOrEmblem).fold(0, (s, c) => s + c.quantity);

  int get landCount     => _mainDeck.where((c) => c.isLand).fold(0, (s, c) => s + c.quantity);
  int get creatureCount => _mainDeck.where((c) => c.isCreature).fold(0, (s, c) => s + c.quantity);
  int get spellCount    => _mainDeck.where((c) => c.isSpell).fold(0, (s, c) => s + c.quantity);
  int get rampCount     => _mainDeck.where((c) => c.isRamp).fold(0, (s, c) => s + c.quantity);
  int get drawCount     => _mainDeck.where((c) => c.isDraw).fold(0, (s, c) => s + c.quantity);
  int get removalCount  => _mainDeck.where((c) => c.isRemoval).fold(0, (s, c) => s + c.quantity);
  int get wipeCount     => _mainDeck.where((c) => c.isWipe).fold(0, (s, c) => s + c.quantity);

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

  // ── Card Browser: format-aware search ─────────────────────────────────────

  List<Map<String, dynamic>> browserResults = [];

  /// Search [globalCardPool] for cards matching [query] that are legal in
  /// [selectedFormat]. Returns up to 50 results.
  void searchCardsForActiveFormat(String query) {
    if (query.trim().length < 2) {
      browserResults = [];
      notifyListeners();
      return;
    }

    final terms = query.toLowerCase().split(RegExp(r'\s+'));

    browserResults = globalCardPool.where((card) {
      // Exclude non-playable layouts unless extras are enabled
      if (!showExtras && !ProxyCard.isPlayableCard(card)) return false;

      final name = (card['name'] as String? ?? '').toLowerCase();
      // All search terms must appear in the card name
      if (!terms.every((t) => name.contains(t))) return false;

      // Format legality check
      final legalities = card['legalities'] as Map<String, dynamic>? ?? {};
      final games = (card['games'] as List?)?.cast<String>() ?? [];

      switch (selectedFormat) {
        case 'paper':
          return true;
        case 'arena':
          return games.contains('arena') ||
              (legalities['timeless'] != null &&
                  legalities['timeless'] != 'not_legal');
        case 'mtgo':
          return games.contains('mtgo') ||
              card['mtgo_id'] != null ||
              (legalities['vintage'] != null &&
                  legalities['vintage'] != 'not_legal');
        default:
          final status = legalities[selectedFormat];
          return status == 'legal' || status == 'restricted';
      }
    }).take(50).toList();

    notifyListeners();
  }

  /// Determine the max allowed copies of a card for the active format.
  int getMaxCopiesAllowed(Map<String, dynamic> cardData) {
    final typeLine = (cardData['type_line'] as String? ?? '').toLowerCase();
    final oracle   = (cardData['oracle_text'] as String? ?? '').toLowerCase();

    // Basic Lands — no limit
    if (typeLine.contains('basic') && typeLine.contains('land')) return 99;

    // Oracle text exceptions
    if (oracle.contains('any number of cards named')) return 99;
    if (oracle.contains('up to nine cards named'))    return 9;
    if (oracle.contains('up to seven cards named'))   return 7;

    // Singleton formats
    const singletons = ['commander', 'brawl', 'historicbrawl', 'duel'];
    if (singletons.contains(selectedFormat.toLowerCase())) return 1;

    // Default 60-card format limit
    return 4;
  }

  /// Add a card from the browser to the parsed deck.
  /// Enforces format-aware quantity caps. Returns null on success,
  /// or a warning string if the cap was hit.
  String? addCardToDeck(Map<String, dynamic> cardData) {
    final name = (cardData['name'] as String? ?? '').toLowerCase();
    final maxAllowed = getMaxCopiesAllowed(cardData);
    final existing = parsedDeck.where(
        (c) => c.name.toLowerCase() == name);

    if (existing.isNotEmpty) {
      if (existing.first.quantity < maxAllowed) {
        existing.first.quantity += 1;
      } else {
        notifyListeners();
        return 'Format limit: max $maxAllowed copies of '
            '${cardData['name']} in $selectedFormat.';
      }
    } else {
      parsedDeck.add(ProxyCard(scryfallData: cardData, quantity: 1));
    }
    notifyListeners();
    return null;
  }

  /// Decrement a card's quantity. If it hits 0, remove it entirely.
  void decrementCardQuantity(ProxyCard target) {
    final index = parsedDeck.indexWhere(
        (c) => c.name.toLowerCase() == target.name.toLowerCase());
    if (index == -1) return;
    if (parsedDeck[index].quantity > 1) {
      parsedDeck[index].quantity--;
    } else {
      parsedDeck.removeAt(index);
    }
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

  // ── Swap card printing ─────────────────────────────────────────────────────────
  void swapPrinting(int index, Map<String, dynamic> newPrintingData) {
    if (index < 0 || index >= parsedDeck.length) return;
    final qty = parsedDeck[index].quantity;
    parsedDeck[index] = ProxyCard(scryfallData: newPrintingData, quantity: qty);
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
