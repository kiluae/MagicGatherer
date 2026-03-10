import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../models/card_models.dart';
import '../services/scryfall_service.dart';
import '../services/edhrec_service.dart';
import '../services/export_service.dart';
import '../services/app_settings.dart';
import '../services/commander_cache_service.dart';
import '../theme/dark_theme.dart';
import '../widgets/log_panel.dart';
import '../widgets/pdf_settings_dialog.dart';
import '../widgets/fuzzy_search_field.dart';
import '../widgets/export_modal.dart';

class GatherScreen extends StatefulWidget {
  final List<Map<String, dynamic>> initialCards;
  final String initialCommander;
  final VoidCallback? onClearPending;

  const GatherScreen({
    super.key,
    this.initialCards   = const [],
    this.initialCommander = '',
    this.onClearPending,
  });

  @override
  State<GatherScreen> createState() => _GatherScreenState();
}

class _GatherScreenState extends State<GatherScreen> {
  final _pasteController    = TextEditingController();
  final _edhrecController   = TextEditingController();
  final _scryfall           = ScryfallService();
  final _edhrec             = EdhrecService();
  final _exporter           = ExportService();
  final _cmdCache           = CommanderCacheService();

  // Commander names for fuzzy autocomplete
  List<String> _commanderNames = [];

  // Source tab
  int _sourceTab = 0; // 0=paste, 1=file, 2=edhrec

  // Format
  String _format = 'paper';

  // Export options — restored from AppSettings
  bool get _doJson    => AppSettings.instance.exportJson;
  bool get _doCsv     => AppSettings.instance.exportCsv;
  bool get _doDecklist => AppSettings.instance.exportDecklist;
  bool get _doImages  => AppSettings.instance.exportImages;
  bool get _doPdf     => AppSettings.instance.exportPdf;
  bool get _doMtgo    => AppSettings.instance.exportMtgo;
  bool get _doArena   => AppSettings.instance.exportArena;
  bool get _cropMarks => AppSettings.instance.drawCropMarks;

  // PDF settings
  PdfSettings _pdfSettings = const PdfSettings();

  // State
  bool    _isRunning = false;
  double  _progress  = 0;
  List<String> _execLog  = [];
  List<String> _errLog   = [];
  String? _loadedFilePath;

  // Pre-loaded cards (from Commander Roller / Format Surgeon)
  List<ScryfallCard> _preloadedCards = [];

  /// True when the current input tab actually has something to process.
  bool get _hasInput {
    if (_preloadedCards.isNotEmpty) return true;
    switch (_sourceTab) {
      case 0: return _pasteController.text.trim().isNotEmpty;   // Paste
      case 1: return _loadedFilePath != null;                   // File
      case 2: return _edhrecController.text.trim().isNotEmpty;  // EDHREC
      default: return false;
    }
  }

  @override
  void initState() {
    super.initState();
    // Restore persisted format
    _format = AppSettings.instance.format;
    _pdfSettings = PdfSettings(
      drawCropMarks: AppSettings.instance.drawCropMarks,
      bleedMm: AppSettings.instance.bleedMm,
    );
    // Load commander names for fuzzy autocomplete (fast — mostly from cache)
    _cmdCache.getCommanders(onStatus: _log).then((cmds) {
      setState(() => _commanderNames = cmds.map((c) => c.name).toList());
    });
    if (widget.initialCards.isNotEmpty) {
      _preloadedCards = widget.initialCards
          .map((m) => ScryfallCard.fromJson(m))
          .toList();
      _sourceTab = 0;
    }
    if (widget.initialCommander.isNotEmpty) {
      _edhrecController.text = widget.initialCommander;
      if (_preloadedCards.isEmpty) _sourceTab = 2;
    }
  }

  @override
  void dispose() {
    _pasteController.dispose();
    _edhrecController.dispose();
    super.dispose();
  }

  void _log(String msg)  => setState(() => _execLog.add(msg));
  void _err(String msg)  => setState(() => _errLog.add(msg));
  void _prog(double pct) => setState(() => _progress = pct);

  // Called by the modal with user's chosen export settings
  // [saveDir] is captured in the button closure before the modal opens.
  void _onOptionsChosen(String saveDir, ExportOptions opts) {
    _onGather(saveDir, opts);
  }

  Future<void> _onGather(String saveDir, [ExportOptions? opts]) async {
    // Format filter: modal opts override the on-screen radio selection
    final formatFilter = opts?.format ?? _format;

    setState(() {
      _isRunning = true;
      _progress  = 0;
      _execLog   = [];
      _errLog    = [];
    });

    try {
      late List<ScryfallCard> cards;

      if (_preloadedCards.isNotEmpty) {
        cards = _preloadedCards;
        _log('Using ${cards.length} pre-loaded cards.');
        widget.onClearPending?.call();
        setState(() => _preloadedCards = []);
      } else if (_sourceTab == 2) {
        final cmd = _edhrecController.text.trim();
        if (cmd.isEmpty) { _err('Enter a commander name.'); return; }
        _log('Fetching EDHREC deck for $cmd...');
        cards = await _scryfall.getCollection(
          await _edhrecCardsFor(cmd),
          onLog: _log, onProgress: _prog, formatFilter: formatFilter,
        );
      } else if (_sourceTab == 1 && _loadedFilePath != null) {
        final lines = await File(_loadedFilePath!).readAsLines();
        final names = lines.where((l) => l.trim().isNotEmpty).toList();
        _log('Loaded ${names.length} lines from file.');
        cards = await _scryfall.getCollection(
          names, onLog: _log, onProgress: _prog, formatFilter: formatFilter,
        );
      } else {
        final raw = _pasteController.text.trim();
        if (raw.isEmpty) { _err('Paste a decklist or choose another source.'); return; }
        final names = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
        cards = await _scryfall.getCollection(
          names, onLog: _log, onProgress: _prog, formatFilter: formatFilter,
        );
      }

      if (cards.isEmpty) { _err('No valid cards found.'); return; }
      _log('Fetched ${cards.length} cards.');

      final prefix = _safePrefix();

      // ── Run all selected outputs (any combination) ──────────────────────
      if (opts?.doJson ?? _doJson) {
        await _exporter.exportJson(cards, saveDir, prefix);
        _log('JSON exported.');
      }
      if (opts?.doCsv ?? _doCsv) {
        await _exporter.exportCsv(cards, saveDir, prefix);
        _log('CSV exported.');
      }
      if (opts?.doDecklist ?? _doDecklist) {
        await _exporter.exportDecklist(cards, saveDir, prefix);
        _log('Decklist exported.');
      }
      if (opts?.doImages ?? _doImages) {
        await _exporter.exportImages(cards, saveDir, prefix,
            onLog: _log, onProgress: _prog);
        _log('Images exported.');
      }
      if (opts?.doPdf ?? _doPdf) {
        await _exporter.exportPdf(cards, saveDir, prefix,
          pageFormat:    _pdfSettings.pageFormat,
          drawCropMarks: _cropMarks,
          onLog: _log, onProgress: _prog,
        );
        _log('PDF proxies exported.');
      }
      if (opts?.doMtgoDek ?? _doMtgo) {
        await _exporter.exportMtgoDek(cards, saveDir, prefix);
        _log('MTGO .dek exported.');
      }
      if (opts?.doArena ?? _doArena) {
        final str = _exporter.arenaClipboardString(cards);
        await Clipboard.setData(ClipboardData(text: str));
        _log('Arena string copied to clipboard!');
      }

      _prog(1.0);
      _log('✅ Gather complete! Saved to $saveDir');
    } catch (e, st) {
      _err('Error: $e');
      debugPrint('$e\n$st');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<List<String>> _edhrecCardsFor(String commanderName) async {
    final page = await _edhrec.getCommanderPage(commanderName);
    if (page == null) throw Exception('Commander not found on EDHREC.');
    return page.toEdhrecCards().map((c) => c.name).toList();
  }

  String _safePrefix() {
    final raw = _sourceTab == 2
        ? _edhrecController.text.trim()
        : _loadedFilePath != null
            ? _loadedFilePath!.split('/').last.replaceAll('.txt', '')
            : 'Gathered_Deck';
    return raw.replaceAll(RegExp(r'[\\/*?:"<>|]'), '').trim();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'dec', 'dek'],
    );
    if (result != null && result.files.single.path != null) {
      setState(() => _loadedFilePath = result.files.single.path);
    }
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Left column — input + options
        SizedBox(
          width: 380,
          child: Container(
            color: kBgPane,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _sectionHeader('1. Input Source'),
                _sourceSelector(),
                const SizedBox(height: 16),
                _sectionHeader('2. Format Filter'),
                _formatSelector(),
                const SizedBox(height: 20),
                _gatherButton(),
              ],
            ),
          ),
        ),
        // Right column — progress + logs
        Expanded(
          child: Container(
            color: kBgBase,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _appTitle(),
                const SizedBox(height: 16),
                if (_preloadedCards.isNotEmpty)
                  _preloadedBanner(),
                if (_isRunning || _progress > 0) ...[
                  LinearProgressIndicator(value: _progress == 0 ? null : _progress,
                      minHeight: 6),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: LogPanel(execLog: _execLog, errLog: _errLog),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _appTitle() => Row(
    children: [
      const Icon(Icons.auto_fix_high, color: kAccentLight, size: 28),
      const SizedBox(width: 10),
      Text('MagicGatherer', style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.bold, color: kText)),
      const Spacer(),
      IconButton(
        icon: const Icon(Icons.help_outline, color: kTextMuted),
        tooltip: 'Help',
        onPressed: _showHelp,
      ),
    ],
  );

  Widget _preloadedBanner() => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: kAccent.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: kAccent.withValues(alpha: 0.4)),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, color: kAccentLight, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(
          '${_preloadedCards.length} cards loaded from another screen. '
          'Hit Gather to export.',
          style: const TextStyle(color: kAccentLight, fontSize: 13),
        )),
        TextButton(
          onPressed: () => setState(() => _preloadedCards = []),
          child: const Text('Clear', style: TextStyle(color: kError)),
        ),
      ],
    ),
  );

  Widget _sourceSelector() {
    return Column(
      children: [
        // Tabs
        Row(
          children: [
            _sourceTab_(0, Icons.content_paste, 'Paste'),
            _sourceTab_(1, Icons.file_open_outlined, 'File'),
            _sourceTab_(2, Icons.person_search, 'EDHREC'),
          ],
        ),
        const SizedBox(height: 10),
        if (_sourceTab == 0)
          DropTarget(
            onDragDone: (detail) {
              if (detail.files.isNotEmpty) {
                File(detail.files.first.path).readAsString().then((s) {
                  setState(() => _pasteController.text = s);
                });
              }
            },
            child: TextField(
              controller: _pasteController,
              maxLines: 8,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: kText),
              decoration: const InputDecoration(
                hintText: '4 Lightning Bolt\n1 Sol Ring\n...\n\n(or drag & drop a .txt file here)',
              ),
            ),
          ),
        if (_sourceTab == 1)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: kBgCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    _loadedFilePath ?? 'No file selected',
                    style: TextStyle(
                      fontSize: 13,
                      color: _loadedFilePath != null ? kText : kTextMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _pickFile,
                child: const Text('Browse'),
              ),
            ],
          ),
        if (_sourceTab == 2)
          FuzzySearchField(
            controller: _edhrecController,
            candidates: _commanderNames,
            hintText: 'Commander name (e.g. Atraxa, Praetors\' Voice)',
            onSelected: (name) => setState(() {}),
          ),
      ],
    );
  }

  Widget _sourceTab_(int idx, IconData icon, String label) {
    final active = _sourceTab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _sourceTab = idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? kAccent : kBgCard,
            borderRadius: BorderRadius.circular(6),
          ),
          margin: const EdgeInsets.only(right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? Colors.white : kTextMuted),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(
                fontSize: 12, color: active ? Colors.white : kTextMuted,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formatSelector() => Column(
    children: [
      _formatRadio('Paper (all cards)', 'paper'),
      _formatRadio('Arena only (skip non-Arena cards)', 'arena'),
      _formatRadio('MTGO only (skip non-MTGO cards)', 'mtgo'),
    ],
  );

  Widget _formatRadio(String label, String value) => InkWell(
    onTap: () {
      setState(() => _format = value);
      AppSettings.instance.setFormat(value);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            _format == value ? Icons.radio_button_checked : Icons.radio_button_unchecked,
            size: 16,
            color: _format == value ? kAccentLight : kTextMuted,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(
            fontSize: 13,
            color: _format == value ? kText : kTextMuted,
          )),
        ],
      ),
    ),
  );



  Widget _gatherButton() => ElevatedButton.icon(
    icon: _isRunning
        ? const SizedBox(width: 18, height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
        : const Icon(Icons.auto_fix_high),
    label: Text(_isRunning ? 'Gathering...' : 'Gather your Magic'),
    onPressed: (_isRunning || !_hasInput)
        ? null
        : () async {
            final saveDir = await FilePicker.platform.getDirectoryPath(
              dialogTitle: 'Choose Output Folder',
            );
            if (saveDir == null) return;
            if (mounted) {
              showExportSelectionModal(
                context,
                format: _format,
                onOptions: (opts) => _onOptionsChosen(saveDir, opts),
              );
            }
          },
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
  );

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w600, color: kTextMuted,
    )),
  );


  void _showHelp() => showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: kBgPane,
      title: const Text('MagicGatherer Help'),
      content: const Text(
        '1. Choose Input: paste a decklist, load a .txt file, '
        'or enter a commander name to fetch from EDHREC.\n\n'
        '2. Select a Format: filter out non-legal cards for Arena or MTGO.\n\n'
        '3. Choose Outputs: PDF proxy sheets, card images, JSON/CSV, '
        'MTGO .dek, or Arena clipboard string.\n\n'
        '4. Hit "Gather your Magic" and select an output folder.\n\n'
        'Use Commander Roller to find a commander, '
        'and Format Surgeon for deck improvement recommendations.',
        style: TextStyle(fontSize: 13, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
