import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../engine/flip_engine.dart';
import '../providers/flip_provider.dart';
import '../theme/dark_theme.dart';

// Entry point — keeps the same class name so home_screen.dart needs no changes.
class CommanderRollerScreen extends StatelessWidget {
  final void Function(List<Map<String, dynamic>>, String)? onSendToGather;
  final void Function(String)? onSendToDoctor;

  const CommanderRollerScreen({
    super.key,
    this.onSendToGather,
    this.onSendToDoctor,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => FlipProvider(),
      child: _FlipBody(
          onSendToGather: onSendToGather,
          onSendToDoctor: onSendToDoctor),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _FlipBody extends StatelessWidget {
  final void Function(List<Map<String, dynamic>>, String)? onSendToGather;
  final void Function(String)? onSendToDoctor;
  const _FlipBody({this.onSendToGather, this.onSendToDoctor});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 230,
            child: Container(
              color: kBgPane,
              padding: const EdgeInsets.all(16),
              child: const _ControlPanel(),
            ),
          ),
          SizedBox(
            width: 270,
            child: Container(
              decoration: const BoxDecoration(
                color: kBgCard,
                border: Border(
                    left: BorderSide(color: kBorder),
                    right: BorderSide(color: kBorder)),
              ),
              child: _MasterList(
                  onSendToGather: onSendToGather,
                  onSendToDoctor: onSendToDoctor),
            ),
          ),
          const Expanded(child: _DetailPanel()),
        ],
      );
}

// ── Control Panel ─────────────────────────────────────────────────────────────
class _ControlPanel extends StatelessWidget {
  const _ControlPanel();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FlipProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Title
        Text('Commander Flip',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold, color: kAccentLight)),
        const SizedBox(height: 20),

        // Coin identity picker
        _sectionLabel('Color Identity'),
        const SizedBox(height: 10),
        _CoinRow(provider: provider),
        const SizedBox(height: 6),
        // Legend
        const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.circle, size: 7, color: kTextMuted),
          SizedBox(width: 3),
          Text('= off  ', style: TextStyle(color: kTextMuted, fontSize: 9)),
          Icon(Icons.circle, size: 7, color: kAccentLight),
          SizedBox(width: 3),
          Text('= on  ', style: TextStyle(color: kTextMuted, fontSize: 9)),
          Icon(Icons.autorenew, size: 9, color: kAccentLight),
          SizedBox(width: 3),
          Text('= flipping', style: TextStyle(color: kTextMuted, fontSize: 9)),
        ]),
        const SizedBox(height: 20),

        _sectionLabel('Format'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: provider.formatFilter,
          dropdownColor: kBgCard,
          style: const TextStyle(color: kText, fontSize: 12),
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true),
          items: const [
            DropdownMenuItem(value: 'paper', child: Text('Paper (All)')),
            DropdownMenuItem(value: 'arena', child: Text('MTG Arena Legal')),
            DropdownMenuItem(value: 'mtgo',  child: Text('MTGO Legal')),
          ],
          onChanged: (v) { if (v != null) provider.setFormatFilter(v); },
        ),
        const SizedBox(height: 10),

        // Pool Tier dropdown
        _sectionLabel('Pool'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: provider.poolTier,
          dropdownColor: kBgCard,
          style: const TextStyle(color: kText, fontSize: 12),
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true),
          items: const [
            DropdownMenuItem(value: 'edhrec_top',    child: Text('EDHREC Top 100')),
            DropdownMenuItem(value: 'edhrec_fringe', child: Text('EDHREC Bottom 100')),
            DropdownMenuItem(value: 'new',           child: Text('New Arrivals')),
            DropdownMenuItem(value: 'chaos',         child: Text('Total Chaos')),
          ],
          onChanged: (v) { if (v != null) provider.setPoolTier(v); },
        ),
        const SizedBox(height: 10),

        // Sort By (local display ordering)
        _sectionLabel('Sort By'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: provider.localSort,
          dropdownColor: kBgCard,
          style: const TextStyle(color: kText, fontSize: 12),
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true),
          items: const [
            DropdownMenuItem(value: 'edhrec',  child: Text('EDHREC Rank')),
            DropdownMenuItem(value: 'cmc',     child: Text('Mana Value')),
            DropdownMenuItem(value: 'price',   child: Text('Price (USD)')),
            DropdownMenuItem(value: 'random',  child: Text('Shuffled')),
          ],
          onChanged: (v) { if (v != null) provider.changeLocalSort(v); },
        ),
        const SizedBox(height: 10),

        // Amount
        _sectionLabel('Amount'),
        const SizedBox(height: 6),
        DropdownButtonFormField<int>(
          initialValue: provider.maxReturns,
          dropdownColor: kBgCard,
          style: const TextStyle(color: kText, fontSize: 12),
          decoration: const InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true),
          items: const [
            DropdownMenuItem(value: 5,  child: Text('5')),
            DropdownMenuItem(value: 10, child: Text('10')),
            DropdownMenuItem(value: 15, child: Text('15')),
            DropdownMenuItem(value: 20, child: Text('20')),
            DropdownMenuItem(value: 0,  child: Text('All')),
          ],
          onChanged: (v) { if (v != null) provider.setMaxReturns(v); },
        ),
        const SizedBox(height: 14),

        // Allow partial colors toggle
        Theme(
          data: Theme.of(context).copyWith(
            switchTheme: SwitchThemeData(
              thumbColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected) ? kAccentLight : kTextMuted),
              trackColor: WidgetStateProperty.resolveWith(
                  (s) => s.contains(WidgetState.selected)
                      ? kAccent.withValues(alpha: 0.5)
                      : kBgCard),
            ),
          ),
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Allow All Partials',
                style: TextStyle(color: kText, fontSize: 12,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(
              provider.allowPartialColors
                  ? 'Includes subsets (id<=)'
                  : 'Includes non-partner mono/dual commanders.',
              style: const TextStyle(color: kTextMuted, fontSize: 10),
            ),
            value: provider.allowPartialColors,
            onChanged: (_) => provider.togglePartialColors(),
          ),
        ),

        // Include Partners/Backgrounds toggle
        // (disabled when allowPartialColors is on — id<= already covers them)
        Opacity(
          opacity: provider.allowPartialColors ? 0.38 : 1.0,
          child: SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Include Partners & Backgrounds',
                style: TextStyle(color: kText, fontSize: 12,
                    fontWeight: FontWeight.w500)),
            subtitle: Text(
              provider.allowPartialColors
                  ? 'Covered by Allow All Partials'
                  : provider.includePartners
                      ? 'Fills missing colors — crucial for 4-Color.'
                      : 'Exact commanders only.',
              style: const TextStyle(color: kTextMuted, fontSize: 10),
            ),
            value: provider.includePartners,
            // Disable when allowPartialColors is on
            onChanged: provider.allowPartialColors
                ? null
                : (_) => provider.togglePartners(),
          ),
        ),

        if (provider.errorMessage != null) ...[
          Text(provider.errorMessage!,
              style: const TextStyle(color: kError, fontSize: 10),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
        ],

        // ── Primary: Randomize & Flip ────────────────────────────────────
        Tooltip(
          message: 'Pick a random commander matching your color filters',
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            icon: provider.isFlipping
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.casino, size: 20),
            label: Text(provider.isFlipping ? 'Flipping...' : 'Randomize & Flip',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            onPressed: provider.isFlipping
                ? null
                : () => provider.startRandomFlip(),
          ),
        ),
        const SizedBox(height: 8),

        // ── Secondary: Fetch Selected ─────────────────────────────────────
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: kAccentLight,
            minimumSize: const Size.fromHeight(40),
            side: BorderSide(
                color: provider.isLoading
                    ? kBorder
                    : kAccentLight),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
          icon: provider.isLoading
              ? const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: kAccentLight))
              : const Icon(Icons.search, size: 16),
          label: Text(
              provider.isLoading ? 'Fetching...' : 'Fetch Selected',
              style: const TextStyle(fontSize: 13)),
          onPressed: provider.isLoading
              ? null
              : () => provider.fetchCurrentSelection(),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          color: kTextMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8));
}

// ── Coin Row ──────────────────────────────────────────────────────────────────
class _CoinRow extends StatelessWidget {
  final FlipProvider provider;
  const _CoinRow({required this.provider});

  static const _meta = [
    ('W', '☀️'),
    ('U', '💧'),
    ('B', '💀'),
    ('R', '🔥'),
    ('G', '🌲'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: _meta.map((m) {
        final code   = m.$1;
        final emoji  = m.$2;
        final active = provider.coins[code] ?? false;

        final Color fill   = active ? kAccent             : kBgCard;
        final Color border = active ? kAccentLight         : const Color(0xFF555570);
        final double glow  = active ? 10.0                 : 0.0;

        return Expanded(
          child: Center(
            child: InkWell(
              onTap: provider.isFlipping
                  ? null
                  : () => context.read<FlipProvider>().toggleCoin(code),
              borderRadius: BorderRadius.circular(20),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                  border: Border.all(color: border, width: active ? 2.5 : 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: kAccentLight.withValues(
                            alpha: active ? 0.55 : 0.0),
                        blurRadius: glow,
                        spreadRadius: active ? 1.5 : 0),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(emoji,
                        style: const TextStyle(fontSize: 14, height: 1.0)),
                    Text(code,
                        style: TextStyle(
                            color: active ? Colors.white : kTextMuted,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            height: 1.1)),
                    ],
                ),          // Column
              ),            // AnimatedContainer
            ),              // InkWell
          ),                // Center
        );                  // Expanded
      }).toList(),
    );
  }
}

// ── Master List ───────────────────────────────────────────────────────────────
class _MasterList extends StatelessWidget {
  final void Function(List<Map<String, dynamic>>, String)? onSendToGather;
  final void Function(String)? onSendToDoctor;
  const _MasterList({this.onSendToGather, this.onSendToDoctor});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FlipProvider>();

    if (provider.isFlipping || provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.results.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.casino, color: kTextMuted, size: 48),
            SizedBox(height: 12),
            Text('Flip to discover commanders!',
                style: TextStyle(color: kTextMuted, fontSize: 13),
                textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
              color: kBgPane,
              border: Border(bottom: BorderSide(color: kBorder))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(builder: (context) {
                final p = context.watch<FlipProvider>();
                final suffix = p.allowPartialColors &&
                        p.currentIdentityName != 'Colorless'
                    ? 'Identity & Partials'
                    : 'Commanders';
                final header =
                    '${p.currentIdentityName} $suffix (${p.results.length})';
                return Text(header,
                    style: const TextStyle(
                        color: kText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold));
              }),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: provider.results.length,
            itemBuilder: (ctx, i) {
              final item = provider.results[i];
              final isSelected =
                  provider.selectedCommander?['id'] == item['id'];
              return _Tile(
                card: item,
                isSelected: isSelected,
                onTap: () =>
                    context.read<FlipProvider>().selectCommander(item),
                onSendToGather: onSendToGather != null
                    ? () => onSendToGather!(
                        [], item['name'] as String? ?? '')
                    : null,
                onSendToDoctor: onSendToDoctor != null
                    ? () =>
                        onSendToDoctor!(item['name'] as String? ?? '')
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final Map<String, dynamic> card;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onSendToGather;
  final VoidCallback? onSendToDoctor;
  const _Tile(
      {required this.card,
      required this.isSelected,
      required this.onTap,
      this.onSendToGather,
      this.onSendToDoctor});

  @override
  Widget build(BuildContext context) {
    final name     = card['name']      as String? ?? 'Unknown';
    final typeLine = card['type_line'] as String? ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isSelected
            ? kAccent.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isSelected ? kAccent : Colors.transparent),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: kText.withValues(
                                alpha: isSelected ? 1.0 : 0.7),
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if (typeLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(typeLine,
                          style: const TextStyle(
                              color: kTextMuted, fontSize: 10),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ],
                ),
              ),
              if (isSelected &&
                  (onSendToGather != null || onSendToDoctor != null))
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      size: 14, color: kTextMuted),
                  itemBuilder: (_) => [
                    if (onSendToDoctor != null)
                      const PopupMenuItem(
                          value: 'doctor',
                          child: Text('Send to Doctor')),
                    if (onSendToGather != null)
                      const PopupMenuItem(
                          value: 'gather',
                          child: Text('Send to Gather')),
                  ],
                  onSelected: (v) {
                    if (v == 'doctor') onSendToDoctor?.call();
                    if (v == 'gather') onSendToGather?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Detail Panel ──────────────────────────────────────────────────────────────
class _DetailPanel extends StatelessWidget {
  const _DetailPanel();
  @override
  Widget build(BuildContext context) {
    final cmdr = context.watch<FlipProvider>().selectedCommander;
    return Container(
      color: kBgBase,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: child),
        child: cmdr == null
            ? const _EmptyDetail()
            : _CardDetail(key: ValueKey(cmdr['id']), card: cmdr),
      ),
    );
  }
}

class _EmptyDetail extends StatelessWidget {
  const _EmptyDetail();
  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, size: 80, color: kTextMuted),
            SizedBox(height: 16),
            Text('Flip to see commander art',
                style: TextStyle(color: kTextMuted, fontSize: 14)),
          ],
        ),
      );
}

class _CardDetail extends StatelessWidget {
  final Map<String, dynamic> card;
  const _CardDetail({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final imageUrl = card['__image_url'] as String? ?? '';
    final name     = card['name']        as String? ?? '';
    final typeLine = card['type_line']   as String? ?? '';
    final oracle   = card['oracle_text'] as String? ?? '';
    final manaCost = card['mana_cost']   as String? ?? '';

    return Column(
      children: [
        Expanded(
          flex: 7,
          child: imageUrl.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        const Center(child: CircularProgressIndicator()),
                    errorWidget: (_, __, ___) => const Center(
                        child: Icon(Icons.broken_image,
                            size: 60, color: kTextMuted)),
                  ),
                )
              : const Center(
                  child: Icon(Icons.image_not_supported,
                      size: 60, color: kTextMuted)),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: const BoxDecoration(
              color: kBgPane,
              border: Border(top: BorderSide(color: kBorder))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: const TextStyle(
                          color: kText,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                ),
                if (manaCost.isNotEmpty)
                  Text(manaCost,
                      style: const TextStyle(
                          color: kTextMuted, fontSize: 12)),
              ]),
              if (typeLine.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(typeLine,
                    style: const TextStyle(
                        color: kTextMuted, fontSize: 12)),
              ],
              if (oracle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(oracle,
                    style: const TextStyle(
                        color: kText, fontSize: 11, height: 1.5),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 12),
              // ── Action Row ─────────────────────────────────────────────
              Consumer<FlipProvider>(
                builder: (ctx, p, _) {
                  final cmdr = p.selectedCommander;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: [
                      // 1. Import to Gather exporter
                      Tooltip(
                        message: 'Send this commander deck to the Gather screen for export',
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kAccent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.download, size: 14),
                          label: const Text('Import to Exporter'),
                          onPressed: cmdr == null
                              ? null
                              : () {
                                  // final name = cmdr['name'] as String? ?? '';
                                },
                        ),
                      ),
                      // 2. View on EDHREC
                      Tooltip(
                        message: 'Open this commander on EDHREC.com in your browser',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kAccentLight,
                            side: const BorderSide(color: kAccentLight),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            textStyle: const TextStyle(fontSize: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.open_in_browser, size: 14),
                          label: const Text('View on EDHREC'),
                          onPressed: cmdr == null
                              ? null
                              : () => launchUrl(
                                  Uri.parse(CommanderFlipEngine
                                      .generateEdhrecUrl(
                                          cmdr['name'] as String? ?? '')),
                                  mode: LaunchMode.externalApplication),
                        ),
                      ),
                      // 3. View on Scryfall
                      Tooltip(
                        message: 'View this card on Scryfall.com',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kTextMuted,
                            side: const BorderSide(color: kBorder),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            textStyle: const TextStyle(fontSize: 11),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6)),
                          ),
                          icon: const Icon(Icons.search, size: 14),
                          label: const Text('View on Scryfall'),
                          onPressed: cmdr == null
                              ? null
                              : () {
                                  final uri = cmdr['scryfall_uri'] as String?;
                                  if (uri != null && uri.isNotEmpty) {
                                    launchUrl(Uri.parse(uri),
                                        mode: LaunchMode.externalApplication);
                                  }
                                },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
