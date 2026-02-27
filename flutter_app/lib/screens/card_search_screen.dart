import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/card_models.dart';
import '../services/scryfall_service.dart';
import '../services/scryfall_repository.dart';
import '../theme/dark_theme.dart';
import '../widgets/card_preview_overlay.dart';

class CardSearchScreen extends StatefulWidget {
  const CardSearchScreen({super.key});

  @override
  State<CardSearchScreen> createState() => _CardSearchScreenState();
}

class _CardSearchScreenState extends State<CardSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _scryfall   = ScryfallService();

  List<ScryfallCard> _results   = [];
  bool  _loading    = false;
  String? _errorMsg;

  // Hover preview
  String? _hoverImage;
  Offset  _hoverPos = Offset.zero;

  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 2) {
      if (_results.isNotEmpty) setState(() => _results = []);
      return;
    }

    // Instant local search from offline pool
    final localHits = ScryfallRepository.searchLocalCards(query);
    if (localHits.isNotEmpty) {
      final localCards = localHits
          .map((m) => ScryfallCard.fromJson(m))
          .toList();
      setState(() { _results = localCards; _errorMsg = null; });
    }

    // Also queue a debounced Scryfall API search for deeper results
    _debounce = Timer(
      const Duration(milliseconds: 700),
      () => _search(query),
    );
  }

  Future<void> _search(String query) async {
    setState(() { _loading = true; _errorMsg = null; });
    try {
      final cards = await _scryfall.search(query.trim(), maxPages: 2);
      setState(() => _results = cards);
    } catch (e) {
      // Keep local results visible; show a soft warning
      setState(() => _errorMsg = 'Scryfall unreachable — showing local results only.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            // Search bar
            Container(
              color: kBgPane,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  const Icon(Icons.search, color: kAccentLight),
                  const SizedBox(width: 10),
                  Text('Card Search',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 24),
                    Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: _onSearchChanged,
                      onSubmitted: _search,
                      decoration: InputDecoration(
                        hintText: 'Type any words: "sol ring", "bolt", "t:instant o:destroy"',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _loading
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 16, height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2)))
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Status bar
            if (_errorMsg != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text(_errorMsg!,
                    style: const TextStyle(color: kError, fontSize: 12)),
              )
            else if (_results.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                child: Text('${_results.length} result(s)',
                    style: const TextStyle(color: kTextMuted, fontSize: 11)),
              ),

            // Empty state or card grid
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.search, size: 60, color: kTextMuted),
                          const SizedBox(height: 12),
                          Text('Type a card name or Scryfall query above',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyLarge
                                  ?.copyWith(color: kTextMuted)),
                          const SizedBox(height: 6),
                          const Text(
                              'e.g.  sol ring  or  t:instant o:destroy',
                              style:
                                  TextStyle(color: kTextMuted, fontSize: 12)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 265 / 370,
                      ),
                      itemCount: _results.length,
                      itemBuilder: (_, i) => _cardTile(_results[i]),
                    ),
            ),
          ],
        ),
        if (_hoverImage != null)
          CardPreviewOverlay(imageUrl: _hoverImage!, position: _hoverPos),
      ],
    );
  }

  Widget _cardTile(ScryfallCard card) {
    final url = card.bestImageUri;
    return MouseRegion(
      onHover: (e) {
        if (url.isNotEmpty) {
          setState(() { _hoverImage = url; _hoverPos = e.position; });
        }
      },
      onExit: (_) => setState(() => _hoverImage = null),
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: '${card.name}\n${card.typeLine}',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: url.isEmpty
              ? Container(
                  color: kBgCard,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(card.name, textAlign: TextAlign.center,
                          style: const TextStyle(color: kText, fontSize: 11)),
                    ),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    color: kBgCard,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: kBgCard,
                    child: Center(
                      child: Text(card.name, textAlign: TextAlign.center,
                          style: const TextStyle(color: kText, fontSize: 10)),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
