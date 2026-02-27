import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';

/// WUBRG + Colorless color pip selector.
class ColorPipSelector extends StatelessWidget {
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  const ColorPipSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  static const _pips = [
    _Pip('W', Color(0xFFF9FAF4), Color(0xFF222222)),
    _Pip('U', Color(0xFF0070BE), Colors.white),
    _Pip('B', Color(0xFF1A1917), Colors.white),
    _Pip('R', Color(0xFFD3202A), Colors.white),
    _Pip('G', Color(0xFF00733E), Colors.white),
    _Pip('C', Color(0xFF8E8E8E), Colors.white),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _pips.map((pip) {
        final active = selected.contains(pip.code);
        return GestureDetector(
          onTap: () {
            final next = Set<String>.from(selected);
            if (active) next.remove(pip.code); else next.add(pip.code);
            onChanged(next);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width:  28, height: 28,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color:  pip.bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? Colors.white : kBorder,
                width: active ? 2.5 : 1,
              ),
              boxShadow: active
                  ? [BoxShadow(color: pip.bg.withOpacity(0.6), blurRadius: 8)]
                  : null,
            ),
            child: Center(
              child: Text(pip.code,
                  style: TextStyle(
                    color: pip.fg,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  )),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _Pip {
  final String code;
  final Color  bg;
  final Color  fg;
  const _Pip(this.code, this.bg, this.fg);
}
