import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../engine/deck_doctor_engine.dart';
import '../providers/deck_builder_provider.dart';
import '../models/card_models.dart';
import '../services/commander_cache_service.dart';
import '../services/scryfall_repository.dart';
import '../theme/dark_theme.dart';
import '../widgets/card_hover_wrapper.dart';
import '../widgets/export_modal.dart';
import '../widgets/fuzzy_search_field.dart';

/// Extract best image URL from raw Scryfall JSON.
String _cardImageUrl(Map<String, dynamic> data) {
  final imgs = data['image_uris'] as Map<String, dynamic>?;
  if (imgs != null) return imgs['normal'] as String? ?? imgs['png'] as String? ?? '';
  // Double-faced cards: use front face
  final faces = data['card_faces'] as List?;
  if (faces != null && faces.isNotEmpty) {
    final fImgs = (faces[0] as Map<String, dynamic>)['image_uris'] as Map<String, dynamic>?;
    return fImgs?['normal'] as String? ?? fImgs?['png'] as String? ?? '';
  }
  return '';
}

class DeckBuilderScreen extends StatelessWidget {
  const DeckBuilderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => DeckBuilderProvider(),
      child: const _DeckBuilderBody(),
    );
  }
}

class _DeckBuilderBody extends StatelessWidget {
  const _DeckBuilderBody();

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 360, child: _LeftPane()),
        VerticalDivider(thickness: 1, width: 1),
        Expanded(child: _RightPane()),
      ],
    );
  }
}

// ── Left Pane: Commander Lookup | Pasted List ────────────────────────────────

class _LeftPane extends StatefulWidget {
  const _LeftPane();
  @override
  State<_LeftPane> createState() => _LeftPaneState();
}

class _LeftPaneState extends State<_LeftPane>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  late final TextEditingController _pasteCtrl;
  late final TextEditingController _cmdCtrl;
  late final TextEditingController _browseCtrl;
  List<String> _commanderNames = [];

  @override
  void initState() {
    super.initState();
    _tabs       = TabController(length: 3, vsync: this);
    _pasteCtrl  = TextEditingController();
    _cmdCtrl    = TextEditingController();
    _browseCtrl = TextEditingController();
    CommanderCacheService().getCommanders(onStatus: (_) {}).then((cmds) {
      if (mounted) setState(() => _commanderNames = cmds.map((c) => c.name).toList());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pasteCtrl.dispose();
    _cmdCtrl.dispose();
    _browseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DeckBuilderProvider>();

    return Container(
      color: kBgPane,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deck Builder',
                    style: TextStyle(
                        color: kText, fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text('Load a deck, browse cards, then hit Gather Your Magic.',
                    style: TextStyle(color: kTextMuted, fontSize: 11)),
                SizedBox(height: 12),
              ],
            ),
          ),
          Container(
            color: kBgCard,
            child: TabBar(
              controller: _tabs,
              labelColor: kAccentLight,
              unselectedLabelColor: kTextMuted,
              indicatorColor: kAccentLight,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Icons.person_search, size: 14), text: 'Commander'),
                Tab(icon: Icon(Icons.content_paste, size: 14), text: 'Import'),
                Tab(icon: Icon(Icons.search, size: 14), text: 'Browse'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CommanderTab(ctrl: _cmdCtrl, commanderNames: _commanderNames),
                _PasteTab(ctrl: _pasteCtrl),
                _BrowseTab(ctrl: _browseCtrl),
              ],
            ),
          ),
          if (p.progressText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(p.progressText,
                  style: const TextStyle(color: kTextMuted, fontSize: 11),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
  }
}

// ── Tab A: Commander Lookup ─────────────────────────────────────────────────

class _CommanderTab extends StatelessWidget {
  final TextEditingController ctrl;
  final List<String> commanderNames;
  const _CommanderTab({required this.ctrl, required this.commanderNames});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DeckBuilderProvider>();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Enter a commander name to fetch the EDHREC average decklist.',
              style: TextStyle(color: kTextMuted, fontSize: 11)),
          const SizedBox(height: 10),
          FuzzySearchField(
            controller: ctrl,
            candidates: commanderNames,
            hintText: "Atraxa, Praetors' Voice",
            onSelected: (_) {},
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent, foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: p.isFetching
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 18),
            label: Text(p.isFetching ? 'Fetching...' : 'Fetch EDHREC Average',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: p.isFetching ? null : () {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              context.read<DeckBuilderProvider>().fetchFromEdhrec(name);
            },
          ),
        ],
      ),
    );
  }
}

// ── Tab B: Pasted List ──────────────────────────────────────────────────────

class _PasteTab extends StatelessWidget {
  final TextEditingController ctrl;
  const _PasteTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              maxLines: null, expands: true,
              style: const TextStyle(color: kText, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '1x Sol Ring\n1x Command Tower\n...',
                hintStyle: TextStyle(color: kTextMuted, fontSize: 12),
                contentPadding: EdgeInsets.all(10),
                border: OutlineInputBorder(borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: kAccentLight)),
                filled: true, fillColor: kBgCard,
              ),
              onChanged: (v) => context.read<DeckBuilderProvider>().rawText = v,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent, foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text('Parse List', style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final provider = context.read<DeckBuilderProvider>();
              provider.rawText = ctrl.text;
              provider.parseDecklist();
              if (provider.notFoundList.isNotEmpty) {
                final names = provider.notFoundList.take(10).join(', ');
                final extra = provider.notFoundList.length > 10
                    ? ' and ${provider.notFoundList.length - 10} more' : '';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Could not find: $names$extra',
                      style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.orange.shade800,
                  duration: const Duration(seconds: 6),
                ));
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Tab C: Card Browser ─────────────────────────────────────────────────────

class _BrowseTab extends StatelessWidget {
  final TextEditingController ctrl;
  const _BrowseTab({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DeckBuilderProvider>();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Search cards legal in ${_formatLabel(p.selectedFormat)}',
            style: const TextStyle(color: kTextMuted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            style: const TextStyle(color: kText, fontSize: 12),
            decoration: InputDecoration(
              hintText: 'Search by name...',
              hintStyle: const TextStyle(color: kTextMuted, fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18, color: kTextMuted),
              suffixIcon: ctrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16, color: kTextMuted),
                      onPressed: () {
                        ctrl.clear();
                        p.searchCardsForActiveFormat('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: const OutlineInputBorder(borderSide: BorderSide(color: kBorder)),
              enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: kBorder)),
              focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: kAccentLight)),
              filled: true,
              fillColor: kBgCard,
            ),
            onChanged: (v) => p.searchCardsForActiveFormat(v),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Include Tokens & Extras',
                style: TextStyle(color: kTextMuted, fontSize: 11)),
            value: p.showExtras,
            onChanged: (val) {
              p.toggleExtras(val);
              p.searchCardsForActiveFormat(ctrl.text);
            },
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          if (p.browserResults.isNotEmpty)
            Text('${p.browserResults.length} results',
                style: const TextStyle(color: kTextMuted, fontSize: 10)),
          const SizedBox(height: 4),
          Expanded(
            child: p.browserResults.isEmpty
                ? Center(
                    child: Text(
                      ctrl.text.length < 2
                          ? 'Type at least 2 characters to search'
                          : 'No cards found',
                      style: const TextStyle(color: kTextMuted, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: p.browserResults.length,
                    itemBuilder: (_, i) {
                      final card = p.browserResults[i];
                      final name = card['name'] as String? ?? '';
                      final type = card['type_line'] as String? ?? '';
                      final cmc  = card['cmc'] as num? ?? 0;

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 0),
                        title: Text(name,
                            style: const TextStyle(color: kText, fontSize: 11)),
                        subtitle: Text('$type · CMC $cmc',
                            style: const TextStyle(color: kTextMuted, fontSize: 9)),
                        trailing: IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              size: 18, color: kAccentLight),
                          tooltip: 'Add to deck',
                          onPressed: () {
                            final warning = p.addCardToDeck(card);
                            if (!context.mounted) return;
                            if (warning != null) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(warning,
                                    style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.orange.shade800,
                                duration: const Duration(seconds: 3),
                              ));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Added $name to deck',
                                    style: const TextStyle(fontSize: 12)),
                                backgroundColor: Colors.green.shade700,
                                duration: const Duration(seconds: 1),
                              ));
                            }
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(String f) => switch (f) {
    'arena'     => 'Arena',
    'mtgo'      => 'MTGO',
    'paper'     => 'Paper',
    'commander' => 'Commander',
    'standard'  => 'Standard',
    'pioneer'   => 'Pioneer',
    'modern'    => 'Modern',
    'historic'  => 'Historic',
    'brawl'     => 'Brawl',
    'pauper'    => 'Pauper',
    _           => f,
  };
}

// ── Right Pane: Analytical Dashboard ────────────────────────────────────────

class _RightPane extends StatelessWidget {
  const _RightPane();

  static const _formats = [
    'paper', 'arena', 'mtgo', 'commander', 'standard',
    'pioneer', 'modern', 'historic', 'brawl', 'pauper',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DeckBuilderProvider>();

    return Container(
      color: kBgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Format Chips ─────────────────────────────────────────────────
          Container(
            color: kBgPane,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _formats.map((f) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(_formatLabel(f), style: const TextStyle(fontSize: 11)),
                    selected: p.selectedFormat == f,
                    onSelected: (_) => p.setFormat(f),
                    selectedColor: kAccent,
                    backgroundColor: kBgCard,
                    labelStyle: TextStyle(
                        color: p.selectedFormat == f ? Colors.white : kTextMuted),
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                )).toList(),
              ),
            ),
          ),

          // ── Diagnosis Dashboard ──────────────────────────────────────────
          if (p.parsedDeck.isNotEmpty) _DiagnosisBanner(provider: p),

          const Divider(height: 1),

          // ── Smart Card List ──────────────────────────────────────────────
          Expanded(
            child: p.parsedDeck.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.style_outlined,
                            size: 48, color: kTextMuted.withValues(alpha: 0.4)),
                        const SizedBox(height: 12),
                        const Text('No deck loaded.',
                            style: TextStyle(color: kTextMuted, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text('Use Commander Lookup or paste a list on the left.',
                            style: TextStyle(color: kTextMuted, fontSize: 11)),
                      ],
                    ),
                  )
                : _SmartCardList(provider: p),
          ),
          const Divider(height: 1),

          // ── Gather Button ─────────────────────────────────────────────────
          Container(
            color: kBgPane,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (p.progressText.isNotEmpty && p.isGenerating)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(p.progressText,
                        style: const TextStyle(color: kTextMuted, fontSize: 11),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        (p.isGenerating || p.parsedDeck.isEmpty) ? kBgCard : kAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: p.isGenerating
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_fix_high, size: 20),
                  label: Text(
                      p.isGenerating ? 'Gathering...' : 'Gather Your Magic',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: (p.isGenerating || p.parsedDeck.isEmpty)
                      ? null
                      : () => showExportSelectionModal(context, proxyDeck: p.parsedDeck),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatLabel(String f) => switch (f) {
    'arena'     => 'Arena',
    'mtgo'      => 'MTGO',
    'paper'     => 'Paper',
    'commander' => 'Commander',
    'standard'  => 'Standard',
    'pioneer'   => 'Pioneer',
    'modern'    => 'Modern',
    'historic'  => 'Historic',
    'brawl'     => 'Brawl',
    'pauper'    => 'Pauper',
    _           => f,
  };
}

// ── Diagnosis Banner (Interactive Filter Chips) ─────────────────────────────

class _DiagnosisBanner extends StatelessWidget {
  final DeckBuilderProvider provider;
  const _DiagnosisBanner({required this.provider});

  @override
  Widget build(BuildContext context) {
    final dropped = provider.droppedCards.length;
    final active  = provider.activeFilter;

    return Container(
      color: kBgPane,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _chip('Total',     '${provider.mainDeckCount}',  kAccentLight,          active, provider),
            _chip('Lands',     '${provider.landCount}',      const Color(0xFF84CC16), active, provider),
            _chip('Creatures', '${provider.creatureCount}',  const Color(0xFF22C55E), active, provider),
            _chip('Spells',    '${provider.spellCount}',     const Color(0xFF8B5CF6), active, provider),
            _chip('Ramp',      '${provider.rampCount}',      const Color(0xFF22C55E), active, provider),
            _chip('Draw',      '${provider.drawCount}',      const Color(0xFF3B82F6), active, provider),
            _chip('Removal',   '${provider.removalCount}',   const Color(0xFFF97316), active, provider),
            _chip('Wipe',      '${provider.wipeCount}',      const Color(0xFFEF4444), active, provider),
            if (provider.tokenCount > 0)
              _chip('Tokens',  '${provider.tokenCount}',     Colors.amber,          active, provider),
            if (dropped > 0)
              _chip('Dropped', '$dropped', const Color(0xFFEF4444), active, provider),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String count, Color color, String active,
      DeckBuilderProvider provider) {
    final selected = active == label;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text('$label: $count', style: TextStyle(
          fontSize: 10,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? Colors.white : color,
        )),
        selected: selected,
        onSelected: (_) => provider.setFilter(selected ? 'Total' : label),
        selectedColor: color.withValues(alpha: 0.35),
        backgroundColor: kBgCard,
        side: BorderSide(color: selected ? color : kBorder, width: selected ? 1.5 : 0.5),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }
}

// ── Smart Card List (with filter) ───────────────────────────────────────────

class _SmartCardList extends StatelessWidget {
  final DeckBuilderProvider provider;
  const _SmartCardList({required this.provider});

  @override
  Widget build(BuildContext context) {
    final format      = provider.selectedFormat;
    final suggestions = provider.suggestions;
    final filter      = provider.activeFilter;

    // Apply heuristic filter
    final displayedDeck = provider.parsedDeck.where((card) {
      switch (filter) {
        case 'Total':     return true;
        case 'Lands':     return card.isLand;
        case 'Creatures': return card.isCreature;
        case 'Spells':    return card.isSpell;
        case 'Ramp':      return card.isRamp;
        case 'Draw':      return card.isDraw;
        case 'Removal':   return card.isRemoval;
        case 'Wipe':      return card.isWipe;
        case 'Dropped':   return !card.isLegalIn(format);
        default:          return true;
      }
    }).toList();

    if (displayedDeck.isEmpty) {
      return Center(
        child: Text('No $filter cards found.',
            style: const TextStyle(color: kTextMuted, fontSize: 13)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: displayedDeck.length,
      itemBuilder: (ctx, i) {
        final card  = displayedDeck[i];
        final legal = card.isLegalIn(format);

        if (legal) {
          return _LegalCardRow(
            index: provider.parsedDeck.indexOf(card),
            card: card,
          );
        } else {
          return _IllegalCardRow(
            card: card,
            suggestions: suggestions[card.name] ?? [],
            onSwap: (replacement) =>
                provider.swapSuggestion(card.name, replacement),
          );
        }
      },
    );
  }
}

// ── Legal Card Row ──────────────────────────────────────────────────────────

class _LegalCardRow extends StatelessWidget {
  final int index;
  final ProxyCard card;
  const _LegalCardRow({required this.index, required this.card});

  @override
  Widget build(BuildContext context) {
    final p = context.read<DeckBuilderProvider>();
    final imgUrl = _cardImageUrl(card.scryfallData);
    final maxAllowed = p.getMaxCopiesAllowed(card.scryfallData);
    final isOverLimit = card.quantity > maxAllowed;

    return CardHoverWrapper(
      imageUrl: imgUrl,
      child: ListTile(
        dense: true,
        title: Text(card.name, style: const TextStyle(color: kText, fontSize: 12)),
        subtitle: Text(
            '${card.setCode.toUpperCase()} · CMC ${card.cmc} · \$${card.usdPrice}',
            style: const TextStyle(color: kTextMuted, fontSize: 10)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_mosaic, size: 16, color: kTextMuted),
            tooltip: 'Select printing',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => _showPrintingSelector(context, p, index, card),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline,
                size: 18, color: Color(0xFFEF4444)),
            tooltip: 'Remove one',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () => p.decrementCardQuantity(card),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('${card.quantity}',
                style: TextStyle(
                    color: isOverLimit ? const Color(0xFFEF4444) : kText,
                    fontSize: 13,
                    fontWeight: FontWeight.bold)),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                size: 18, color: Color(0xFF22C55E)),
            tooltip: 'Add one',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
            onPressed: () {
              final warning = p.addCardToDeck(card.scryfallData);
              if (warning != null && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(warning, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.orange.shade800,
                  duration: const Duration(seconds: 3),
                ));
              }
            },
          ),
        ]),
      ),
    );
  }

  void _showPrintingSelector(
      BuildContext context, DeckBuilderProvider provider,
      int cardIndex, ProxyCard card) {
    final oracleId = card.scryfallData['oracle_id'] as String? ?? '';
    showDialog(
      context: context,
      builder: (ctx) => _PrintingSelectorDialog(
          oracleId: oracleId,
          onSelected: (printing) {
            provider.swapPrinting(cardIndex, printing);
            Navigator.of(ctx).pop();
          }),
    );
  }
}

// ── Illegal Card Row + Prescription ─────────────────────────────────────────

class _IllegalCardRow extends StatelessWidget {
  final ProxyCard card;
  final List<Map<String, dynamic>> suggestions;
  final void Function(Map<String, dynamic>) onSwap;

  const _IllegalCardRow({
    required this.card,
    required this.suggestions,
    required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final oracle   = card.scryfallData['oracle_text'] as String? ?? '';
    final typeLine = card.typeLine;
    final roles    = DeckDoctorEngine.getRoles(oracle, typeLine);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Row(children: [
            const Icon(Icons.warning_amber_rounded, size: 16,
                color: Color(0xFFEF4444)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(card.name, style: const TextStyle(
                  color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            ...roles.map((r) => Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: _roleColor(r).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(r, style: TextStyle(
                  color: _roleColor(r), fontSize: 8, fontWeight: FontWeight.bold)),
            )),
          ]),

          // Suggestion row
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: suggestions.length,
                itemBuilder: (_, si) {
                  final s     = suggestions[si];
                  final sName = s['name'] as String? ?? '';
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: kAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: kAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(sName, style: const TextStyle(color: kText, fontSize: 10)),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          onSwap(s);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Swapped in $sName for ${card.name}'),
                            backgroundColor: Colors.green.shade700,
                            duration: const Duration(seconds: 2),
                          ));
                        },
                        child: const Icon(Icons.add_circle, size: 14, color: kAccentLight),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 4),
            const Text('No replacements found',
                style: TextStyle(color: kTextMuted, fontSize: 9)),
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
}

// ── Printing Selector Dialog ────────────────────────────────────────────────

class _PrintingSelectorDialog extends StatefulWidget {
  final String oracleId;
  final void Function(Map<String, dynamic>) onSelected;

  const _PrintingSelectorDialog({
    required this.oracleId,
    required this.onSelected,
  });

  @override
  State<_PrintingSelectorDialog> createState() =>
      _PrintingSelectorDialogState();
}

class _PrintingSelectorDialogState extends State<_PrintingSelectorDialog> {
  List<Map<String, dynamic>>? _printings;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final results = await ScryfallRepository.fetchPrintings(widget.oracleId);
    if (mounted) setState(() { _printings = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBgPane,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: kBgCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Row(children: [
                Icon(Icons.auto_awesome_mosaic, color: kAccentLight, size: 20),
                SizedBox(width: 8),
                Text('Select Printing',
                    style: TextStyle(color: kText, fontSize: 14,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
            const Divider(height: 1),

            // Grid
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : (_printings == null || _printings!.isEmpty)
                      ? const Center(child: Text('No printings found.',
                          style: TextStyle(color: kTextMuted)))
                      : GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.715,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: _printings!.length,
                          itemBuilder: (_, i) {
                            final p = _printings![i];
                            final setName = p['set_name'] as String? ?? '';
                            final setCode = (p['set'] as String? ?? '').toUpperCase();
                            final imgUrl = _cardImageUrl(p);

                            return InkWell(
                              onTap: () => widget.onSelected(p),
                              borderRadius: BorderRadius.circular(8),
                              child: Column(children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: imgUrl,
                                      fit: BoxFit.cover,
                                      width: double.infinity,
                                      placeholder: (_, __) => Container(
                                          color: kBgCard,
                                          child: const Center(child:
                                              CircularProgressIndicator(
                                                  strokeWidth: 2))),
                                      errorWidget: (_, __, ___) => Container(
                                          color: kBgCard,
                                          child: const Icon(
                                              Icons.image_not_supported,
                                              color: kTextMuted)),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('$setCode · $setName',
                                    style: const TextStyle(
                                        color: kTextMuted, fontSize: 8),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              ]),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
