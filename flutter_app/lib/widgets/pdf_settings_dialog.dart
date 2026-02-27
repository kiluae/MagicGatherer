import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import '../theme/dark_theme.dart';

/// PDF proxy settings — paper size, bleed, cut guides.
class PdfSettings {
  final PdfPageFormat pageFormat;
  final bool drawCropMarks;
  final double bleedMm;

  const PdfSettings({
    this.pageFormat  = PdfPageFormat.letter,
    this.drawCropMarks = true,
    this.bleedMm     = 0.0,
  });
}

class PdfSettingsDialog extends StatefulWidget {
  final PdfSettings initial;
  const PdfSettingsDialog({super.key, required this.initial});

  @override
  State<PdfSettingsDialog> createState() => _PdfSettingsDialogState();
}

class _PdfSettingsDialogState extends State<PdfSettingsDialog> {
  late PdfPageFormat _format;
  late bool   _crops;
  late double _bleed;

  static final _formats = <String, PdfPageFormat>{
    'US Letter': PdfPageFormat.letter,
    'US Legal':  PdfPageFormat.legal,
    'Tabloid':   PdfPageFormat(11 * PdfPageFormat.inch, 17 * PdfPageFormat.inch),
    'A4':        PdfPageFormat.a4,
    'A3':        PdfPageFormat.a3,
    'A2':        PdfPageFormat(16.54 * PdfPageFormat.inch, 23.39 * PdfPageFormat.inch),
    'A1':        PdfPageFormat(23.39 * PdfPageFormat.inch, 33.11 * PdfPageFormat.inch),
  };

  @override
  void initState() {
    super.initState();
    _format = widget.initial.pageFormat;
    _crops  = widget.initial.drawCropMarks;
    _bleed  = widget.initial.bleedMm;
  }

  String get _currentLabel => _formats.entries
      .firstWhere((e) => e.value == _format,
          orElse: () => _formats.entries.first)
      .key;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: kBgPane,
      title: const Row(children: [
        Icon(Icons.tune, color: kAccentLight, size: 20),
        SizedBox(width: 8),
        Text('PDF Proxy Settings'),
      ]),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Paper size
            _label('Paper Size'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _currentLabel,
              decoration: const InputDecoration(isDense: true),
              dropdownColor: kBgCard,
              items: _formats.keys
                  .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _format = _formats[v]!);
              },
            ),
            const SizedBox(height: 20),

            // Bleed edge
            _label('Bleed Edge: ${_bleed.toStringAsFixed(1)} mm'),
            Slider(
              value: _bleed,
              min: 0, max: 5,
              divisions: 10,
              activeColor: kAccent,
              label: '${_bleed.toStringAsFixed(1)} mm',
              onChanged: (v) => setState(() => _bleed = v),
            ),
            const SizedBox(height: 8),

            // Cut guides
            Row(
              children: [
                Checkbox(
                  value: _crops,
                  onChanged: (v) => setState(() => _crops = v ?? true),
                ),
                const Text('Draw cut guides / crop marks'),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
            context,
            PdfSettings(
              pageFormat:    _format,
              drawCropMarks: _crops,
              bleedMm:       _bleed,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: kTextMuted, fontSize: 12,
          fontWeight: FontWeight.w600));
}
