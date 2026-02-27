import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';

/// Fuzzy autocomplete search field.
/// Uses the same char-by-char subsequence matching as the Python FuzzyProxyModel.
/// [candidates] is the full list to filter (e.g. commander names from cache).
class FuzzySearchField extends StatefulWidget {
  final String hintText;
  final List<String> candidates;
  final TextEditingController? controller;
  final ValueChanged<String>? onSelected;
  final ValueChanged<String>? onChanged;

  const FuzzySearchField({
    super.key,
    required this.candidates,
    this.hintText = 'Search...',
    this.controller,
    this.onSelected,
    this.onChanged,
  });

  @override
  State<FuzzySearchField> createState() => _FuzzySearchFieldState();
}

class _FuzzySearchFieldState extends State<FuzzySearchField> {
  late TextEditingController _ctrl;
  final _layerLink = LayerLink();
  OverlayEntry? _overlay;
  List<String> _matches = [];

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? TextEditingController();
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _removeOverlay();
    if (widget.controller == null) _ctrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!mounted) return;
    final query = _ctrl.text.trim();
    widget.onChanged?.call(query);
    if (query.isEmpty) { _removeOverlay(); return; }

    final results = widget.candidates
        .where((c) => _fuzzyMatch(query.toLowerCase(), c.toLowerCase()))
        .take(12)
        .toList();

    setState(() => _matches = results);
    if (results.isEmpty) { _removeOverlay(); return; }
    _showOverlay();
  }

  /// Subsequence (char-by-char) fuzzy match — same algorithm as Python FuzzyProxyModel.
  static bool _fuzzyMatch(String needle, String haystack) {
    int ni = 0, hi = 0;
    while (ni < needle.length && hi < haystack.length) {
      if (needle[ni] == haystack[hi]) ni++;
      hi++;
    }
    return ni == needle.length;
  }

  void _showOverlay() {
    _removeOverlay();
    _overlay = OverlayEntry(builder: (_) => _buildDropdown());
    Overlay.of(context).insert(_overlay!);
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _select(String name) {
    _ctrl.text = name;
    _ctrl.selection = TextSelection.collapsed(offset: name.length);
    _removeOverlay();
    widget.onSelected?.call(name);
  }

  Widget _buildDropdown() {
    return Positioned(
      width: 400,
      child: CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 46),
        child: Material(
          color: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kBorder),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 12)],
            ),
            child: ListView.builder(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _matches.length,
              itemBuilder: (_, i) => InkWell(
                onTap: () => _select(_matches[i]),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: _highlighted(_matches[i], _ctrl.text.trim()),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Renders matching characters in accent colour.
  Widget _highlighted(String candidate, String query) {
    if (query.isEmpty) {
      return Text(candidate, style: const TextStyle(color: kText, fontSize: 13));
    }
    final spans = <TextSpan>[];
    int qi = 0;
    final ql = query.toLowerCase();
    for (var i = 0; i < candidate.length; i++) {
      final ch = candidate[i];
      if (qi < ql.length && ch.toLowerCase() == ql[qi]) {
        spans.add(TextSpan(
          text: ch,
          style: const TextStyle(color: kAccentLight, fontWeight: FontWeight.bold),
        ));
        qi++;
      } else {
        spans.add(TextSpan(text: ch, style: const TextStyle(color: kText)));
      }
    }
    return RichText(text: TextSpan(children: spans, style: const TextStyle(fontSize: 13)));
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _ctrl,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.person_search),
          suffixIcon: _ctrl.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 16),
                  tooltip: 'Clear search',
                  onPressed: () { _ctrl.clear(); _removeOverlay(); },
                )
              : null,
        ),
      ),
    );
  }
}
