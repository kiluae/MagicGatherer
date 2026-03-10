import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../engine/deck_doctor_engine.dart';
import '../models/card_models.dart';
import '../providers/deck_builder_provider.dart';
import '../services/commander_cache_service.dart';
import '../services/export_service.dart';
import '../services/scryfall_repository.dart';
import '../theme/dark_theme.dart';
import '../widgets/card_preview_overlay.dart';
import '../widgets/fuzzy_search_field.dart';

class DeckDoctorScreen extends StatefulWidget {
  final String initialCommander;
  final void Function(List<Map<String, dynamic>> cards, String commanderName)?
      onSendToGather;

  const DeckDoctorScreen({
    super.key,
    this.initialCommander = '',
    this.onSendToGather,
  });

  @override
  State<DeckDoctorScreen> createState() => _DeckDoctorScreenState();
}

class _DeckDoctorScreenState extends State<DeckDoctorScreen> {
  final _commanderCtrl = TextEditingController();
  final _pasteCtrl     = TextEditingController();

  String _format = 'arena';
  List<String> _commanderNames = [];

  // ── Analysis State ──────────────────────────────────────────────────────
  List<ProxyCard> _activeDeck    = [];
  List<ProxyCard> _droppedCards  = [];
  DeckDiagnosis?  _diagnosis;
  Map<String, List<Map<String, dynamic>>> _suggestions = {};

  bool _analyzing = false;
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
    CommanderCacheService().getCommanders(onStatus: (_) {}).then((cmds) {
      if (mounted) {
        setState(
            () => _commanderNames = cmds.map((c) => c.name).toList());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-import from DeckBuilderProvider if available
    try {
      final provider = context.read<DeckBuilderProvider>();
      if (provider.parsedDeck.isNotEmpty && _activeDeck.isEmpty) {
        _activeDeck = List.of(provider.parsedDeck);
        _runDiagnosis();
      }
    } catch (_) {
      // DeckBuilderProvider not in tree — that's fine
    }
  }

  @override
  void dispose() {
    _commanderCtrl.dispose();
    _pasteCtrl.dispose();
    super.dispose();
  }

  // ── Analysis Logic ────────────────────────────────────────────────────────

  void _runDiagnosis() {
    if (_activeDeck.isEmpty) return;

    // Identify cards that are NOT legal in the selected format
    final kept    = <ProxyCard>[];
    final dropped = <ProxyCard>[];

    for (final card in _activeDeck) {
      final legalities =
          card.scryfallData['legalities'] as Map<String, dynamic>?;
      final games =
          (card.scryfallData['games'] as List?)?.cast<String>() ?? [];

      bool isLegal;
      if (_format == 'arena') {
        isLegal = games.contains('arena') ||
            (legalities != null &&
                legalities['timeless'] != null &&
                legalities['timeless'] != 'not_legal');
      } else if (_format == 'mtgo') {
        isLegal = games.contains('mtgo') ||
            card.scryfallData['mtgo_id'] != null ||
            (legalities != null &&
                legalities['vintage'] != null &&
                legalities['vintage'] != 'not_legal');
      } else {
        isLegal = true; // Paper — everything is legal
      }

      if (isLegal) {
        kept.add(card);
      } else {
        dropped.add(card);
      }
    }

    final diagnosis = DeckDoctorEngine.diagnose(kept);
    final suggestions = dropped.isNotEmpty
        ? DeckDoctorEngine.getSuggestions(dropped, formatFilter: _format)
        : <String, List<Map<String, dynamic>>>{};

    setState(() {
      _droppedCards = dropped;
      _diagnosis   = diagnosis;
      _suggestions = suggestions;
      _statusMsg   = '${kept.length} legal, ${dropped.length} dropped';
    });
  }

  Future<void> _analyzeFromPaste() async {
    final raw = _pasteCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _errorMsg = 'Paste a decklist first.');
      return;
    }

    setState(() {
      _analyzing = true;
      _errorMsg = null;
      _statusMsg = 'Parsing decklist...';
    });

    try {
      final result = DeckParser.parseTxt(raw, globalCardPool);
      _activeDeck = result.deck;

      if (_activeDeck.isEmpty) {
        setState(() {
          _statusMsg = 'No cards matched — is the local database loaded?';
          _analyzing = false;
        });
        return;
      }

      _runDiagnosis();
    } catch (e) {
      setState(() => _errorMsg = 'Error: $e');
    } finally {
      setState(() => _analyzing = false);
    }
  }

  void _swapSuggestion(String droppedName, Map<String, dynamic> replacement) {
    setState(() {
      _droppedCards.removeWhere(
          (c) => c.name.toLowerCase() == droppedName.toLowerCase());
      _activeDeck.add(ProxyCard(scryfallData: replacement, quantity: 1));
      _suggestions.remove(droppedName);
      _diagnosis = DeckDoctorEngine.diagnose(_activeDeck);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Swapped in ${replacement['name'] ?? 'card'} for $droppedName'),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
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
                  // Left: Input panel
                  SizedBox(
                    width: 320,
                    child: _inputPanel(),
                  ),
                  const VerticalDivider(width: 1),
                  // Right: Diagnosis + Prescription
                  Expanded(child: _resultsPanel()),
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
            Text('Format Surgeon',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            // Format chips
            ..._formatChips(),
          ],
        ),
      );

  List<Widget> _formatChips() =>
      ['arena', 'mtgo', 'paper'].map((f) {
        return Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(
            label: Text(f[0].toUpperCase() + f.substring(1),
                style: const TextStyle(fontSize: 11)),
            selected: _format == f,
            onSelected: (_) {
              setState(() => _format = f);
              if (_activeDeck.isNotEmpty) _runDiagnosis();
            },
            selectedColor: kAccent,
            backgroundColor: kBgCard,
            labelStyle:
                TextStyle(color: _format == f ? Colors.white : kTextMuted),
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        );
      }).toList();

  // ── Left Panel: Input ──────────────────────────────────────────────────────

  Widget _inputPanel() => Container(
        color: kBgPane,
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            _label('Commander (optional)'),
            const SizedBox(height: 6),
            FuzzySearchField(
              controller: _commanderCtrl,
              candidates: _commanderNames,
              hintText: "Atraxa, Praetors' Voice",
              onSelected: (_) {},
            ),
            const SizedBox(height: 14),
            _label('Paste Decklist'),
            const SizedBox(height: 6),
            TextField(
              controller: _pasteCtrl,
              maxLines: 12,
              style: const TextStyle(
                  fontFamily: 'monospace', fontSize: 11, color: kText),
              decoration: const InputDecoration(
                hintText: '1 Sol Ring\n1 Command Tower\n...',
                contentPadding: EdgeInsets.all(10),
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: _analyzing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high, size: 16),
              label: Text(_analyzing ? 'Analyzing...' : 'Analyze Deck'),
              onPressed: _analyzing ? null : _analyzeFromPaste,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
            if (_statusMsg != null) ...[
              const SizedBox(height: 10),
              Text(_statusMsg!,
                  style: const TextStyle(color: kSuccess, fontSize: 12)),
            ],
            if (_errorMsg != null) ...[
              const SizedBox(height: 6),
              Text(_errorMsg!,
                  style: const TextStyle(color: kError, fontSize: 12)),
            ],
          ],
        ),
      );

  // ── Right Panel: Diagnosis + Prescription ─────────────────────────────────

  Widget _resultsPanel() {
    if (_diagnosis == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.medical_services_outlined,
                size: 48, color: kTextMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Paste a decklist and hit Analyze,',
                style: TextStyle(color: kTextMuted, fontSize: 14)),
            const Text('or load one in the Proxy Builder tab first.',
                style: TextStyle(color: kTextMuted, fontSize: 11)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // ── Diagnosis Dashboard ───────────────────────────────────────────
        _diagnosisDashboard(),
        const Divider(height: 1),
        // ── Prescription: Dropped cards + suggestions ─────────────────────
        Expanded(child: _prescriptionPanel()),
      ],
    );
  }

  Widget _diagnosisDashboard() {
    final d = _diagnosis!;
    return Container(
      color: kBgPane,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          _statChip('Total', '${d.totalCards}/100', kAccentLight),
          _statChip('Dropped', '${_droppedCards.length}', kError),
          _statChip('Ramp', '${d.rampCount}', const Color(0xFF22C55E)),
          _statChip('Draw', '${d.drawCount}', const Color(0xFF3B82F6)),
          _statChip('Removal', '${d.removalCount}', const Color(0xFFF97316)),
          _statChip('Lands', '${d.landCount}', const Color(0xFF84CC16)),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(color: kTextMuted, fontSize: 10)),
          ],
        ),
      );

  Widget _prescriptionPanel() {
    if (_droppedCards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 48, color: Color(0xFF22C55E)),
            const SizedBox(height: 12),
            Text(
              _format == 'paper'
                  ? 'All cards are legal in Paper!'
                  : 'All cards are legal in ${_format == 'arena' ? 'MTG Arena' : 'MTGO'}!',
              style: const TextStyle(color: kText, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _droppedCards.length,
      itemBuilder: (_, i) => _droppedCardRow(_droppedCards[i]),
    );
  }

  Widget _droppedCardRow(ProxyCard card) {
    final suggestions = _suggestions[card.name] ?? [];
    final oracle = card.scryfallData['oracle_text'] as String? ?? '';
    final typeLine = card.scryfallData['type_line'] as String? ?? '';
    final roles = DeckDoctorEngine.getRoles(oracle, typeLine);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dropped card header
          Row(
            children: [
              const Icon(Icons.remove_circle, size: 16, color: kError),
              const SizedBox(width: 8),
              Expanded(
                child: Text(card.name,
                    style: const TextStyle(
                        color: kText,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              // Role tags
              ...roles.map((r) => Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _roleColor(r).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(r,
                        style: TextStyle(
                            color: _roleColor(r),
                            fontSize: 9,
                            fontWeight: FontWeight.bold)),
                  )),
            ],
          ),

          // Suggestion row
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Suggested replacements:',
                style: TextStyle(color: kTextMuted, fontSize: 10)),
            const SizedBox(height: 6),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                itemBuilder: (_, si) {
                  final s = suggestions[si];
                  final sName = s['name'] as String? ?? '';
                  return MouseRegion(
                    onHover: (e) {
                      final imgUris =
                          s['image_uris'] as Map<String, dynamic>?;
                      final url = imgUris?['normal'] as String?;
                      if (url != null) {
                        setState(() {
                          _hoverImage = url;
                          _hoverPos = e.position;
                        });
                      }
                    },
                    onExit: (_) => setState(() => _hoverImage = null),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: kAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: kAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(sName,
                              style: const TextStyle(
                                  color: kText, fontSize: 11)),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _swapSuggestion(card.name, s),
                            child: const Icon(Icons.add_circle,
                                size: 16, color: kAccentLight),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text('No replacements found in local database.',
                style: TextStyle(color: kTextMuted, fontSize: 10)),
          ],
        ],
      ),
    );
  }

  Color _roleColor(String role) => switch (role) {
        'Ramp'    => const Color(0xFF22C55E),
        'Draw'    => const Color(0xFF3B82F6),
        'Removal' => const Color(0xFFF97316),
        'Land'    => const Color(0xFF84CC16),
        _         => kTextMuted,
      };

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: kTextMuted, fontSize: 12, fontWeight: FontWeight.w600));
}
