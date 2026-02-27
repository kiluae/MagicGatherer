import 'package:flutter/material.dart';
import '../models/card_models.dart';
import '../theme/dark_theme.dart';

/// Analytics dashboard: Mana Curve bar chart + Card Type breakdown.
/// Mirrors the Deck Doctor analytics window from deck_doctor.py.
class AnalyticsDashboard extends StatelessWidget {
  final List<ScryfallCard> cards;

  const AnalyticsDashboard({super.key, required this.cards});

  @override
  Widget build(BuildContext context) {
    final (curve, types, colors) = _analyze(cards);

    return Container(
      color: kBgBase,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel('Mana Curve'),
          const SizedBox(height: 6),
          SizedBox(height: 70, child: _ManaCurveChart(curve: curve)),
          const SizedBox(height: 14),
          _sectionLabel('Card Types'),
          const SizedBox(height: 6),
          _TypeBreakdown(types: types),
          const SizedBox(height: 14),
          _sectionLabel('Color Distribution'),
          const SizedBox(height: 6),
          _ColorBar(colors: colors),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(color: kTextMuted, fontSize: 11,
          fontWeight: FontWeight.w600));

  /// Returns (manaCurve, typeCounts, colorCounts)
  (Map<int, int>, Map<String, int>, Map<String, int>) _analyze(
      List<ScryfallCard> cards) {
    final curve  = <int, int>{};
    final types  = <String, int>{};
    final colors = <String, int>{};

    for (final c in cards) {
      // Mana curve: extract first number from mana cost if available
      // Approximate from type hints since CMC isn't in our model
      // (Scryfall search results do return cmc in JSON — future improvement)
      const cmc = 0; // placeholder — will be populated when we add cmc to model
      curve[cmc] = (curve[cmc] ?? 0) + 1;

      // Type breakdown
      for (final t in ['Creature', 'Instant', 'Sorcery', 'Enchantment', 'Artifact', 'Planeswalker', 'Land']) {
        if (c.typeLine.contains(t)) {
          types[t] = (types[t] ?? 0) + 1;
          break;
        }
      }

      // Color identity
      for (final col in c.colorIdentity) {
        colors[col] = (colors[col] ?? 0) + 1;
      }
    }
    return (curve, types, colors);
  }
}

class _ManaCurveChart extends StatelessWidget {
  final Map<int, int> curve;
  const _ManaCurveChart({required this.curve});

  @override
  Widget build(BuildContext context) {
    if (curve.isEmpty) {
      return const Center(child: Text('No data', style: TextStyle(color: kTextMuted, fontSize: 11)));
    }
    final maxVal = curve.values.fold(1, (a, b) => a > b ? a : b);
    final cmcs   = (curve.keys.toList()..sort());

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: cmcs.map((cmc) {
        final count = curve[cmc] ?? 0;
        final pct   = count / maxVal;
        return Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('$count', style: const TextStyle(color: kText, fontSize: 9)),
              const SizedBox(height: 2),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: (50 * pct).clamp(2.0, 50.0),
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: kAccent.withValues(alpha: 0.7 + 0.3 * pct),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ),
              const SizedBox(height: 2),
              Text(cmc == 7 ? '7+' : '$cmc',
                  style: const TextStyle(color: kTextMuted, fontSize: 9)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _TypeBreakdown extends StatelessWidget {
  final Map<String, int> types;
  const _TypeBreakdown({required this.types});

  static const _typeColors = {
    'Creature':     Color(0xFF22C55E),
    'Instant':      Color(0xFF3B82F6),
    'Sorcery':      Color(0xFF8B5CF6),
    'Enchantment':  Color(0xFFF59E0B),
    'Artifact':     Color(0xFF94A3B8),
    'Planeswalker': Color(0xFFF97316),
    'Land':         Color(0xFF84CC16),
  };

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) return const SizedBox.shrink();
    final total = types.values.fold(0, (a, b) => a + b);
    return Wrap(
      spacing: 8, runSpacing: 6,
      children: types.entries.map((e) {
        final pct = (e.value / total * 100).round();
        final color = _typeColors[e.key] ?? kTextMuted;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 4),
            Text('${e.key} $pct%',
                style: TextStyle(color: color, fontSize: 10)),
          ],
        );
      }).toList(),
    );
  }
}

class _ColorBar extends StatelessWidget {
  final Map<String, int> colors;
  const _ColorBar({required this.colors});

  static const _colorMap = {
    'W': Color(0xFFF9FAF4),
    'U': Color(0xFF0070BE),
    'B': Color(0xFF1A1917),
    'R': Color(0xFFD3202A),
    'G': Color(0xFF00733E),
    'C': Color(0xFF8E8E8E),
  };

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) return const SizedBox.shrink();
    final total = colors.values.fold(0, (a, b) => a + b);
    return Row(
      children: colors.entries.map((e) {
        final frac = e.value / total;
        return Flexible(
          flex: (frac * 100).round(),
          child: Tooltip(
            message: '${e.key}: ${e.value}',
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: _colorMap[e.key] ?? kTextMuted,
                border: Border.all(color: Colors.black26, width: 0.5),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
