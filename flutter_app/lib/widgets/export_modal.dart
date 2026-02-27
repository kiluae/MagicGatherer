import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/card_models.dart';
import '../services/export_service.dart';
import '../services/pdf_service.dart';
import '../theme/dark_theme.dart';

// ── Export Options ─────────────────────────────────────────────────────────────
/// Carries both the card-set filter and the set of outputs the user chose.
class ExportOptions {
  /// Which cards to include: 'paper' | 'arena' | 'mtgo'
  final String format;

  // Outputs (any combination is valid)
  final bool doJson;
  final bool doCsv;
  final bool doDecklist;
  final bool doImages;
  final bool doPdf;
  final bool doMtgoDek;
  final bool doArena; // copy Arena-legal subset to clipboard

  // PDF / image settings
  final bool   preferMtgPics;
  final String paperSize;
  final double bleedInches;
  final double cardSpacing;
  final int    dpi;

  // Content
  final bool includeBasicLands;

  const ExportOptions({
    this.format           = 'paper',
    this.doJson           = true,
    this.doCsv            = true,
    this.doDecklist       = true,
    this.doImages         = false,
    this.doPdf            = false,
    this.doMtgoDek        = false,
    this.doArena          = false,
    this.preferMtgPics    = false,
    this.paperSize        = 'letter',
    this.bleedInches      = 0.0,
    this.cardSpacing      = 0.05,
    this.dpi              = 300,
    this.includeBasicLands = false,
  });

  bool get needsImageSettings => doImages || doPdf;
}

// ── Entry point ────────────────────────────────────────────────────────────────
Future<void> showExportSelectionModal(
  BuildContext context, {
  List<ProxyCard> proxyDeck = const [],
  String format = 'paper',
  void Function(ExportOptions)? onOptions,
}) async {
  await showDialog<void>(
    context:            context,
    barrierDismissible: true,
    builder: (_) => _ExportModal(proxyDeck: proxyDeck, format: format, onOptions: onOptions),
  );
}

// ── Modal ──────────────────────────────────────────────────────────────────────
class _ExportModal extends StatefulWidget {
  final List<ProxyCard> proxyDeck;
  final String format;  // passed from gather screen — no need to repeat in modal
  final void Function(ExportOptions)? onOptions;
  const _ExportModal({required this.proxyDeck, this.format = 'paper', this.onOptions});
  @override
  State<_ExportModal> createState() => _ExportModalState();
}

class _ExportModalState extends State<_ExportModal> {
  // ── Output toggles (independent checkboxes) ────────────────────────────────
  bool _doJson     = true;
  bool _doCsv      = true;
  bool _doDecklist = true;
  bool _doImages   = false;
  bool _doPdf      = false;
  bool _doMtgoDek  = false;
  bool _doArena    = false;

  // ── Image / PDF settings (shown when images or PDF selected) ──────────────
  bool   _mtgPics  = false;
  String _paper    = 'letter';
  int    _dpi      = 300;
  double _bleed    = 0.0;
  double _spacing  = 0.05;

  // ── Content ────────────────────────────────────────────────────────────────
  bool _basicLands = false;

  // ── State ──────────────────────────────────────────────────────────────────
  bool   _isRunning = false;
  String _status    = '';

  bool get _needsImageSettings => _doImages || _doPdf;

  ExportOptions get _opts => ExportOptions(
    format:           widget.format, // from gather screen's Format Filter
    doJson:           _doJson,
    doCsv:            _doCsv,
    doDecklist:       _doDecklist,
    doImages:         _doImages,
    doPdf:            _doPdf,
    doMtgoDek:        _doMtgoDek,
    doArena:          _doArena,
    preferMtgPics:    _mtgPics,
    paperSize:        _paper,
    bleedInches:      _bleed,
    cardSpacing:      _spacing,
    dpi:              _dpi,
    includeBasicLands: _basicLands,
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kBgPane,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ───────────────────────────────────────────────────
              Row(children: [
                const Icon(Icons.auto_fix_high, color: kAccentLight, size: 22),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('Gather Your Magic',
                      style: TextStyle(
                          color: kText, fontSize: 17,
                          fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: kTextMuted),
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              const SizedBox(height: 20),

              // ── SECTION 1: Output Files (format chosen on main screen) ────
              _sectionLabel('OUTPUT FILES'),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [
                _outChip('JSON',            Icons.data_object,    _doJson,     (v) => setState(() => _doJson     = v)),
                _outChip('CSV',             Icons.table_chart,    _doCsv,      (v) => setState(() => _doCsv      = v)),
                _outChip('Decklist .txt',   Icons.description,    _doDecklist, (v) => setState(() => _doDecklist = v)),
                // When Images is turned off, PDF is also forced off
                _outChip('Images (folder)', Icons.image,          _doImages,   (v) => setState(() { _doImages = v; if (!v) _doPdf = false; })),
                // PDF Proxies is only available when Images is also checked
                _outChipConditional(
                  'PDF Proxies', Icons.picture_as_pdf, _doPdf,
                  enabled: _doImages,
                  disabledLabel: 'Requires Images',
                  onChanged: (v) => setState(() => _doPdf = v),
                ),
                _outChip('MTGO .dek',       Icons.gamepad,        _doMtgoDek,  (v) => setState(() => _doMtgoDek  = v)),
                _outChip('Arena Clipboard', Icons.shield,         _doArena,    (v) => setState(() => _doArena    = v)),
              ]),
              const SizedBox(height: 20),

              // ── SECTION 3: Image / PDF Settings (conditional) ────────────
              if (_needsImageSettings) ...[
                _sectionLabel('IMAGE SETTINGS'),
                const SizedBox(height: 8),
                // Image source
                Row(children: [
                  _srcBtn(false, 'Scryfall PNG', 'Fast · Standard'),
                  const SizedBox(width: 8),
                  _srcBtn(true,  'MTGPics',      'Ultra-HD · ~1s/card'),
                ]),
                if (_doPdf) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    _label('Paper:'),
                    const SizedBox(width: 8),
                    _miniDrop<String>(
                      value: _paper,
                      items: const {'letter': 'US Letter', 'a4': 'A4'},
                      onChanged: (v) => setState(() => _paper = v!),
                    ),
                    const SizedBox(width: 16),
                    _label('DPI:'),
                    const SizedBox(width: 8),
                    _miniDrop<int>(
                      value: _dpi,
                      items: const {300: '300', 600: '600', 900: '900', 1400: '1400'},
                      onChanged: (v) => setState(() => _dpi = v!),
                    ),
                  ]),
                  Row(children: [
                    _label('Bleed:'),
                    Expanded(
                      child: Slider(
                        value: _bleed, min: 0, max: 0.25, divisions: 5,
                        label: '${_bleed.toStringAsFixed(3)}"',
                        activeColor: kAccentLight,
                        onChanged: (v) => setState(() => _bleed = v),
                      ),
                    ),
                    _label('${_bleed.toStringAsFixed(2)}"'),
                  ]),
                  Row(children: [
                    _label('Gap:  '),
                    Expanded(
                      child: Slider(
                        value: _spacing, min: 0, max: 0.2, divisions: 8,
                        label: '${_spacing.toStringAsFixed(3)}"',
                        activeColor: kAccentLight,
                        onChanged: (v) => setState(() => _spacing = v),
                      ),
                    ),
                    _label('${_spacing.toStringAsFixed(2)}"'),
                  ]),
                ],
                const SizedBox(height: 20),
              ],

              // ── SECTION 4: Content ───────────────────────────────────────
              _sectionLabel('CONTENT'),
              const SizedBox(height: 8),
              _toggleRow(
                icon: Icons.grass,
                label: 'Include Basic Lands',
                sub: 'Auto-fills to 100 cards based on color identity',
                value: _basicLands,
                onChanged: (v) => setState(() => _basicLands = v),
              ),
              const SizedBox(height: 20),

              // Status
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_status,
                      style: const TextStyle(color: kTextMuted, fontSize: 11),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ),

              // ── Generate & Save ──────────────────────────────────────────
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kAccent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                icon: _isRunning
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.download, size: 18),
                label: Text(_isRunning ? 'Working...' : 'Generate & Save',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                onPressed: _isRunning ? null : _onStart,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sub-widgets ──────────────────────────────────────────────────────────────

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          color: kTextMuted, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.1));

  Widget _label(String t) =>
      Text(t, style: const TextStyle(color: kTextMuted, fontSize: 11));

  List<Widget> _formatOptions() => [
    _fmtRadio('paper', Icons.layers,   'Paper',      'All cards included'),
    _fmtRadio('arena', Icons.shield,   'Arena Only', 'Skips non-Arena cards'),
    _fmtRadio('mtgo',  Icons.gamepad,  'MTGO Only',  'Skips non-MTGO cards'),
  ];

  Widget _fmtRadio(String key, IconData icon, String label, String sub) {
    final active = _format == key;
    return GestureDetector(
      onTap: () => setState(() => _format = key),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(
            active ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: active ? kAccentLight : kTextMuted,
          ),
          const SizedBox(width: 10),
          Icon(icon, size: 14, color: active ? kAccentLight : kTextMuted),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: label,
                    style: TextStyle(
                        color: active ? kAccentLight : kText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: '  $sub',
                    style: const TextStyle(color: kTextMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _outChip(String label, IconData icon, bool value,
      ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: value ? kAccent.withValues(alpha: 0.18) : kBgCard,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
              color: value ? kAccentLight : kBorder,
              width: value ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            value ? Icons.check_box : Icons.check_box_outline_blank,
            size: 13,
            color: value ? kAccentLight : kTextMuted,
          ),
          const SizedBox(width: 5),
          Icon(icon, size: 12, color: value ? kAccentLight : kTextMuted),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: value ? kAccentLight : kTextMuted,
                  fontWeight:
                      value ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  /// Like _outChip but can be visually disabled with a hint label.
  Widget _outChipConditional(
    String label,
    IconData icon,
    bool value, {
    required bool enabled,
    required String disabledLabel,
    required ValueChanged<bool> onChanged,
  }) {
    if (!enabled) {
      // Greyed-out, non-interactive locked chip
      return Opacity(
        opacity: 0.35,
        child: Tooltip(
          message: disabledLabel,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: kBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.lock_outline, size: 11, color: kTextMuted),
              const SizedBox(width: 5),
              Icon(icon, size: 12, color: kTextMuted),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: kTextMuted,
                      fontWeight: FontWeight.normal)),
            ]),
          ),
        ),
      );
    }
    return _outChip(label, icon, value, onChanged);
  }

  Widget _srcBtn(bool isPics, String label, String sub) {
    final active = _mtgPics == isPics;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _mtgPics = isPics),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
          decoration: BoxDecoration(
            color: active ? kAccent.withValues(alpha: 0.15) : kBgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: active ? kAccentLight : kBorder,
                width: active ? 1.5 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: active ? kAccentLight : kText)),
            Text(sub,
                style: const TextStyle(fontSize: 9, color: kTextMuted)),
          ]),
        ),
      ),
    );
  }

  Widget _miniDrop<T>({
    required T value,
    required Map<T, String> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButton<T>(
      value: value,
      dropdownColor: kBgCard,
      style: const TextStyle(color: kText, fontSize: 12),
      underline: Container(height: 1, color: kBorder),
      items: items.entries
          .map((e) => DropdownMenuItem<T>(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _toggleRow({
    required IconData icon,
    required String label,
    required String sub,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(children: [
      Icon(icon, size: 16, color: value ? kAccentLight : kTextMuted),
      const SizedBox(width: 10),
      Expanded(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(
              fontSize: 12, color: value ? kAccentLight : kText,
              fontWeight: FontWeight.w500)),
          Text(sub, style: const TextStyle(fontSize: 10, color: kTextMuted)),
        ],
      )),
      Switch(value: value, activeColor: kAccentLight, onChanged: onChanged),
    ]);
  }

  // ── Action ───────────────────────────────────────────────────────────────────

  Future<void> _onStart() async {
    // Gather screen: return options to caller, which handles the ScryfallCard pipeline
    if (widget.onOptions != null) {
      widget.onOptions!(_opts);
      if (mounted) Navigator.pop(context);
      return;
    }

    // Deck Builder: direct export from ProxyCard deck
    if (widget.proxyDeck.isEmpty) {
      setState(() => _status = 'No cards in deck to export.');
      return;
    }

    setState(() { _isRunning = true; _status = 'Starting...'; });
    try {
      await _runDeckExport();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _runDeckExport() async {
    final deck = widget.proxyDeck;

    if (_doJson) {
      setState(() => _status = 'Saving JSON…');
      await ExportEngine.triggerSave(
        context: context, defaultName: 'deck.json',
        content: ExportEngine.toJSON(deck),
      );
    }
    if (_doCsv) {
      setState(() => _status = 'Saving CSV…');
      await ExportEngine.triggerSave(
        context: context, defaultName: 'deck.csv',
        content: ExportEngine.toCSV(deck),
      );
    }
    if (_doDecklist) {
      setState(() => _status = 'Saving decklist…');
      await ExportEngine.triggerSave(
        context: context, defaultName: 'decklist.txt',
        content: ExportEngine.toClipboard(deck),
      );
    }
    if (_doMtgoDek) {
      setState(() => _status = 'Saving MTGO .dek…');
      await ExportEngine.triggerSave(
        context: context, defaultName: 'deck.dek',
        content: ExportEngine.toMTGO(deck),
      );
    }
    if (_doArena) {
      setState(() => _status = 'Copying Arena clipboard…');
      final skipped = <String>[];
      final txt = ExportEngine.toArenaClipboard(deck, skipped);
      await Clipboard.setData(ClipboardData(text: txt));
      if (mounted) {
        final msg = skipped.isEmpty
            ? 'Arena clipboard copied!'
            : 'Arena copied · Skipped ${skipped.length}: ${skipped.take(3).join(', ')}${skipped.length > 3 ? '…' : ''}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }
    if (_doImages) {
      setState(() => _status = 'Dumping images…');
      await ExportEngine.saveImages(deck,
        preferMtgPics: _mtgPics,
        onProgress: (m) { if (mounted) setState(() => _status = m); },
      );
    }
    if (_doPdf) {
      setState(() => _status = 'Generating PDF…');
      final Uint8List pdfBytes = await ProxyGenerator.generatePdf(
        deck:          deck,
        paperSize:     _paper,
        bleedInches:   _bleed,
        cardSpacing:   _spacing,
        dpi:           _dpi,
        preferMtgPics: _mtgPics,
        onProgress: (m) { if (mounted) setState(() => _status = m); },
      );
      await ExportEngine.triggerSave(
        context: context, defaultName: 'proxies.pdf', bytes: pdfBytes);
    }

    if (mounted) Navigator.pop(context);
  }
}
