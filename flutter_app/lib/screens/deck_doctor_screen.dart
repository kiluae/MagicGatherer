import 'dart:async';
import 'package:flutter/material.dart';
import '../models/card_models.dart';
import '../services/edhrec_service.dart';
import '../services/scryfall_service.dart';
import '../theme/dark_theme.dart';
import '../widgets/card_preview_overlay.dart';
import '../widgets/analytics_dashboard.dart';

class DeckDoctorScreen extends StatefulWidget {
  final String initialCommander;
  final void Function(List<Map<String, dynamic>> cards, String commanderName)? onSendToGather;

  const DeckDoctorScreen({
    super.key,
    this.initialCommander = '',
    this.onSendToGather,
  });

  @override
  State<DeckDoctorScreen> createState() => _DeckDoctorScreenState();
}

class _DeckDoctorScreenState extends State<DeckDoctorScreen> {
  final _pasteCtrl      = TextEditingController();
  final _commanderCtrl  = TextEditingController();
  final _edhrec         = EdhrecService();
  final _scryfall       = ScryfallService();

  String _format = 'paper';

  // Analyzed deck
  List<ScryfallCard> _deckCards  = [];
  String _detectedCommander = '';

  // Recommendations
  List<EdhrecCard> _adds = [];
  List<ScryfallCard> _cuts = [];

  bool _analyzing   = false;
  bool _comparing   = false;
  String? _statusMsg;
  String? _errorMsg;

  // Hover preview
  String? _hoverImage;
  Offset  _hoverPos = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.initialCommander.isNotEmpty) {
      _commanderCtrl.text = widget.initialCommander;
    }
  }

  @override
  void dispose() {
    _pasteCtrl.dispose();
    _commanderCtrl.dispose();
    super.dispose();
  }

  // ── Deck Analysis ──────────────────────────────────────────────────────────

  Future<void> _analyzeAndCompare() async {
    final raw = _pasteCtrl.text.trim();
    final commanderInput = _commanderCtrl.text.trim();
    if (raw.isEmpty && commanderInput.isEmpty) {
      setState(() => _errorMsg = 'Paste a decklist and/or enter a commander.');
      return;
    }

    setState(() {
      _analyzing = true; _comparing = false;
      _adds = []; _cuts = []; _deckCards = [];
      _statusMsg = 'Parsing decklist...'; _errorMsg = null;
    });

    try {
      // 1. Parse the paste area for card names
      final lines = raw.split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => _stripQty(l.trim()))
          .toList();

      if (lines.isNotEmpty) {
        setState(() => _statusMsg = 'Fetching card data from Scryfall...');
        _deckCards = await _scryfall.getCollection(
            lines, formatFilter: _format);
        _detectedCommander = commanderInput.isNotEmpty
            ? commanderInput
            : _detectCommander(_deckCards);
        setState(() => _statusMsg = 'Deck loaded — ${_deckCards.length} cards.');
      } else {
        _detectedCommander = commanderInput;
      }

      // 2. EDHREC comparison
      if (_detectedCommander.isNotEmpty) {
        setState(() { _comparing = true; _statusMsg = 'Fetching EDHREC recommendations for $_detectedCommander...'; });
        final page = await _edhrec.getCommanderPage(_detectedCommander);
        if (page == null) throw Exception('Commander not found on EDHREC.');

        final allRecs  = page.toEdhrecCards();
        final deckNames = _deckCards.map((c) => c.name.toLowerCase()).toSet();

        // Adds: EDHREC suggests those NOT already in deck
        _adds = allRecs.where((r) => !deckNames.contains(r.name.toLowerCase())).toList();

        // Cuts: cards in deck that are NOT in any EDHREC cardview
        final edhrecNames = allRecs.map((r) => r.name.toLowerCase()).toSet();
        _cuts = _deckCards.where((c) => !edhrecNames.contains(c.name.toLowerCase())).toList();

        setState(() { _statusMsg = '${_adds.length} suggestions, ${_cuts.length} potential cuts.'; });
      } else {
        setState(() => _statusMsg = 'No commander detected — paste a decklist with a named commander.');
      }
    } catch (e) {
      setState(() => _errorMsg = 'Error: $e');
    } finally {
      setState(() { _analyzing = false; _comparing = false; });
    }
  }

  String _stripQty(String line) {
    final m = RegExp(r'^\d+[x]?\s+(.*)$').firstMatch(line);
    return m != null ? m.group(1)! : line;
  }

  String _detectCommander(List<ScryfallCard> cards) {
    // Heuristic: legendary creature, typically first line
    for (final c in cards) {
      if (c.typeLine.contains('Legendary') &&
          (c.typeLine.contains('Creature') || c.typeLine.contains('Planeswalker'))) {
        return c.name;
      }
    }
    return '';
  }

  // ── Gap Filler ─────────────────────────────────────────────────────────────

  /// Triggered when user double-clicks a recommendation card.
  /// Sends that card name to the Gather screen EDHREC field.
  void _onRecommendationDoubleTap(EdhrecCard card) {
    if (widget.onSendToGather != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gap filler: searching "${card.name}" in Gather...'))
      );
      // We send as a query to gather — the gather screen handles EDHREC lookup
      widget.onSendToGather!([], card.name);
    }
  }

  /// Send the full updated decklist to the exporter
  Future<void> _sendToExporter() async {
    if (_deckCards.isEmpty) return;
    widget.onSendToGather!(
      _deckCards.map((c) => c.toJson()).toList(),
      _detectedCommander,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Decklist sent to Gather!')));
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            _toolbar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: input + analytics
                  SizedBox(
                    width: 320,
                    child: Container(
                      color: kBgPane,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _label('Commander'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _commanderCtrl,
                                  decoration: const InputDecoration(
                                    hintText: 'e.g. Atraxa, Praetors\' Voice',
                                    prefixIcon: Icon(Icons.person_search),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _label('Format'),
                                _formatRow(),
                                const SizedBox(height: 12),
                                _label('Decklist'),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _pasteCtrl,
                                  maxLines: 10,
                                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: kText),
                                  decoration: const InputDecoration(
                                    hintText: '1 Sol Ring\n1 Command Tower\n...',
                                    contentPadding: EdgeInsets.all(10),
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Tooltip(
                                  message: 'Compare your deck against EDHREC average and get upgrade suggestions',
                                  child: ElevatedButton.icon(
                                    icon: _analyzing || _comparing
                                        ? const SizedBox(width: 16, height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Icon(Icons.compare, size: 16),
                                    label: Text(_analyzing || _comparing ? 'Analyzing...' : 'Analyze & Compare'),
                                    onPressed: _analyzing || _comparing ? null : _analyzeAndCompare,
                                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                                  ),
                                ),
                                if (_deckCards.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Tooltip(
                                    message: 'Open the Proxy Builder with this deck pre-loaded',
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.print, size: 15),
                                      label: const Text('Send to Exporter'),
                                      onPressed: _sendToExporter,
                                    ),
                                  ),
                                ],
                                if (_statusMsg != null) ...[
                                  const SizedBox(height: 10),
                                  Text(_statusMsg!, style: const TextStyle(color: kSuccess, fontSize: 12)),
                                ],
                                if (_errorMsg != null) ...[
                                  const SizedBox(height: 6),
                                  Text(_errorMsg!, style: const TextStyle(color: kError, fontSize: 12)),
                                ],
                              ],
                            ),
                          ),
                          // Analytics dashboard (mana curve + type breakdown)
                          if (_deckCards.isNotEmpty)
                            Expanded(
                              child: AnalyticsDashboard(cards: _deckCards),
                            ),
                        ],
                      ),
                    ),
                  ),
                  // Center: Recommendations (Add)
                  Expanded(
                    child: _recommendationColumn(
                      title: 'EDHREC Suggestions (${_adds.length})',
                      icon: Icons.add_circle_outline,
                      color: kSuccess,
                      child: _adds.isEmpty
                          ? _emptyHint('Run Analyze & Compare to see suggestions')
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _adds.length,
                              itemBuilder: (_, i) => _addCard(_adds[i]),
                            ),
                    ),
                  ),
                  // Right: Cuts
                  Expanded(
                    child: _recommendationColumn(
                      title: 'Potential Cuts (${_cuts.length})',
                      icon: Icons.remove_circle_outline,
                      color: kError,
                      child: _cuts.isEmpty
                          ? _emptyHint('Cards not found on EDHREC will appear here')
                          : ListView.builder(
                              padding: const EdgeInsets.all(8),
                              itemCount: _cuts.length,
                              itemBuilder: (_, i) => _cutCard(_cuts[i]),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_hoverImage != null)
          CardPreviewOverlay(imageUrl: _hoverImage!, position: _hoverPos),
      ],
    );
  }

  Widget _toolbar() => Container(
    color: kBgPane,
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    child: Row(
      children: [
        const Icon(Icons.medical_services, color: kAccentLight),
        const SizedBox(width: 10),
        Text('Deck Doctor',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold)),
        if (_detectedCommander.isNotEmpty) ...[
          const SizedBox(width: 16),
          Chip(
            label: Text(_detectedCommander, style: const TextStyle(fontSize: 12)),
            backgroundColor: kAccent.withOpacity(0.2),
            avatar: const Icon(Icons.person, size: 14, color: kAccentLight),
          ),
        ],
      ],
    ),
  );

  Widget _formatRow() => Row(
    children: ['paper', 'arena', 'mtgo'].map((f) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(f.capitalize(), style: const TextStyle(fontSize: 11)),
        selected: _format == f,
        onSelected: (_) => setState(() => _format = f),
        selectedColor: kAccent,
        backgroundColor: kBgCard,
        labelStyle: TextStyle(color: _format == f ? Colors.white : kTextMuted),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    )).toList(),
  );

  Widget _recommendationColumn({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) =>
    Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            border: Border(bottom: BorderSide(color: kBorder)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );

  Widget _addCard(EdhrecCard card) {
    return MouseRegion(
      onHover: (e) {
        if (card.imageUri != null) {
          setState(() { _hoverImage = card.imageUri; _hoverPos = e.position; });
        }
      },
      onExit: (_) => setState(() => _hoverImage = null),
      child: GestureDetector(
        onDoubleTap: () => _onRecommendationDoubleTap(card),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: kBgCard,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              // Symbol badge
              Container(
                width: 28, height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('[${card.symbol}]',
                    style: const TextStyle(color: kAccentLight, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(child: Text(card.name, style: const TextStyle(color: kText, fontSize: 12))),
              const Icon(Icons.double_arrow, size: 12, color: kTextMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cutCard(ScryfallCard card) {
    return MouseRegion(
      onHover: (e) {
        final url = card.bestImageUri;
        if (url.isNotEmpty) setState(() { _hoverImage = url; _hoverPos = e.position; });
      },
      onExit: (_) => setState(() => _hoverImage = null),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: kBgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            const Icon(Icons.remove_circle_outline, size: 14, color: kError),
            const SizedBox(width: 6),
            Expanded(child: Text(card.name, style: const TextStyle(color: kText, fontSize: 12))),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: kTextMuted, fontSize: 12, fontWeight: FontWeight.w600));

  Widget _emptyHint(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(msg, style: const TextStyle(color: kTextMuted, fontSize: 13),
            textAlign: TextAlign.center),
      ));
}

extension _StringCap on String {
  String capitalize() => isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
