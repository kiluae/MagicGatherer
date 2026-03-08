import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/deck_builder_provider.dart';
import '../models/card_models.dart';
import '../services/commander_cache_service.dart';
import '../theme/dark_theme.dart';
import '../widgets/export_modal.dart';
import '../widgets/fuzzy_search_field.dart';

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
        SizedBox(width: 390, child: _LeftPane()),
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
  List<String> _commanderNames = [];

  @override
  void initState() {
    super.initState();
    _tabs     = TabController(length: 2, vsync: this);
    _pasteCtrl = TextEditingController();
    _cmdCtrl   = TextEditingController();
    // Load commander name list for fuzzy autocomplete
    CommanderCacheService().getCommanders(onStatus: (_) {}).then((cmds) {
      if (mounted) setState(() => _commanderNames = cmds.map((c) => c.name).toList());
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    _pasteCtrl.dispose();
    _cmdCtrl.dispose();
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
          // Header
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Deck Builder',
                    style: TextStyle(
                        color: kText,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 2),
                Text(
                    'Load a deck, parse it, then hit Gather Your Magic.',
                    style: TextStyle(color: kTextMuted, fontSize: 11)),
                SizedBox(height: 12),
              ],
            ),
          ),

          // Tab bar
          Container(
            color: kBgCard,
            child: TabBar(
              controller: _tabs,
              labelColor: kAccentLight,
              unselectedLabelColor: kTextMuted,
              indicatorColor: kAccentLight,
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(icon: Icon(Icons.person_search, size: 16), text: 'Commander Lookup'),
                Tab(icon: Icon(Icons.content_paste, size: 16), text: 'Pasted List'),
              ],
            ),
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CommanderTab(
                    ctrl: _cmdCtrl, commanderNames: _commanderNames),
                _PasteTab(ctrl: _pasteCtrl),
              ],
            ),
          ),

          // Status
          if (p.progressText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(p.progressText,
                  style: const TextStyle(color: kTextMuted, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),

        ],
      ),
    );
  }
}

// ── Tab A: Commander Lookup (EDHREC average list) ────────────────────────────

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
          const Text(
            'Enter a commander name to fetch the EDHREC average decklist.',
            style: TextStyle(color: kTextMuted, fontSize: 11),
          ),
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
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: p.isFetching
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.search, size: 18),
            label: Text(
                p.isFetching ? 'Fetching...' : 'Fetch EDHREC Average',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            onPressed: p.isFetching
                ? null
                : () {
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

// ── Tab B: Pasted List ───────────────────────────────────────────────────────

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
              maxLines: null,
              expands: true,
              style: const TextStyle(
                  color: kText, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '1x Sol Ring\n1x Command Tower\n...',
                hintStyle: TextStyle(color: kTextMuted, fontSize: 12),
                contentPadding: EdgeInsets.all(10),
                border: OutlineInputBorder(
                    borderSide: BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: kAccentLight)),
                filled: true,
                fillColor: kBgCard,
              ),
              onChanged: (v) =>
                  context.read<DeckBuilderProvider>().rawText = v,
            ),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.manage_search, size: 18),
            label: const Text('Parse List',
                style: TextStyle(fontWeight: FontWeight.bold)),
            onPressed: () {
              final provider = context.read<DeckBuilderProvider>();
              provider.rawText = ctrl.text;
              provider.parseDecklist();

              // Surface unrecognized cards via SnackBar
              if (provider.notFoundList.isNotEmpty) {
                final names = provider.notFoundList.take(10).join(', ');
                final extra = provider.notFoundList.length > 10
                    ? ' and ${provider.notFoundList.length - 10} more'
                    : '';
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Could not find: $names$extra',
                      style: const TextStyle(fontSize: 12),
                    ),
                    backgroundColor: Colors.orange.shade800,
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ── Quick Export Strip ───────────────────────────────────────────────────────


// ── Right Pane: Card List + Gather Button ────────────────────────────────────

class _RightPane extends StatelessWidget {
  const _RightPane();

  @override
  Widget build(BuildContext context) {
    final p = context.watch<DeckBuilderProvider>();

    return Container(
      color: kBgBase,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Card list
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
                            style: TextStyle(
                                color: kTextMuted, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text(
                            'Use Commander Lookup or paste a list on the left.',
                            style: TextStyle(
                                color: kTextMuted, fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: p.parsedDeck.length,
                    itemBuilder: (ctx, i) =>
                        _CardRow(index: i, card: p.parsedDeck[i]),
                  ),
          ),
          const Divider(height: 1),

          // Status + Gather button
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
                        style: const TextStyle(
                            color: kTextMuted, fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        (p.isGenerating || p.parsedDeck.isEmpty)
                            ? kBgCard
                            : kAccent,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: p.isGenerating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.auto_fix_high, size: 20),
                  label: Text(
                      p.isGenerating
                          ? 'Gathering...'
                          : 'Gather Your Magic',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14)),
                  onPressed: (p.isGenerating || p.parsedDeck.isEmpty)
                      ? null
                      : () => showExportSelectionModal(
                            context,
                            proxyDeck: p.parsedDeck,
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card Row ─────────────────────────────────────────────────────────────────

class _CardRow extends StatelessWidget {
  final int index;
  final ProxyCard card;
  const _CardRow({required this.index, required this.card});

  @override
  Widget build(BuildContext context) {
    final hasOverride = card.localImagePath != null;
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: kBgCard,
        child: Text('${card.quantity}',
            style: const TextStyle(color: kText, fontSize: 12)),
      ),
      title: Text(card.name,
          style: const TextStyle(color: kText, fontSize: 12)),
      subtitle: Text(
          '${card.setCode.toUpperCase()} · CMC ${card.cmc}'
          ' · \$${card.usdPrice}',
          style: const TextStyle(color: kTextMuted, fontSize: 10)),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (hasOverride)
          const Tooltip(
            message: 'Custom art override set',
            child: Icon(Icons.check_circle, size: 14, color: Colors.green),
          ),
        IconButton(
          icon: Icon(
            hasOverride
                ? Icons.image
                : Icons.add_photo_alternate_outlined,
            size: 18,
            color: kTextMuted,
          ),
          tooltip: 'Set custom art image',
          onPressed: () async {
            final result = await FilePicker.platform.pickFiles(
                type: FileType.image, allowMultiple: false);
            if (!context.mounted) return;
            if (result != null && result.files.single.path != null) {
              context
                  .read<DeckBuilderProvider>()
                  .setLocalImage(index, result.files.single.path!);
            }
          },
        ),
      ]),
    );
  }
}
