import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists user settings across sessions, mirroring Python's config.py.
/// Keys match the Python config state keys for easy reference.
class AppSettings extends ChangeNotifier {
  static AppSettings? _instance;
  static AppSettings get instance => _instance!;

  static Future<AppSettings> load() async {
    _instance = AppSettings._();
    await _instance!._load();
    return _instance!;
  }

  AppSettings._();

  // ── State ──────────────────────────────────────────────────────────────────
  String format        = 'paper';
  String paperSize     = 'US Letter';
  bool   exportJson    = true;
  bool   exportCsv     = false;
  bool   exportDecklist = false;
  bool   exportImages  = false;
  bool   exportPdf     = true;
  bool   exportMtgo    = false;
  bool   exportArena   = false;
  bool   drawCropMarks = true;
  double bleedMm       = 0.0;

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    format         = p.getString('format')      ?? 'paper';
    paperSize      = p.getString('paper_size')  ?? 'US Letter';
    exportJson     = p.getBool('export_json')   ?? true;
    exportCsv      = p.getBool('export_csv')    ?? false;
    exportDecklist = p.getBool('export_decklist') ?? false;
    exportImages   = p.getBool('export_images') ?? false;
    exportPdf      = p.getBool('export_pdf')    ?? true;
    exportMtgo     = p.getBool('export_mtgo')   ?? false;
    exportArena    = p.getBool('export_arena')  ?? false;
    drawCropMarks  = p.getBool('draw_crop_marks') ?? true;
    bleedMm        = p.getDouble('bleed_mm')    ?? 0.0;
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('format',           format);
    await p.setString('paper_size',       paperSize);
    await p.setBool('export_json',        exportJson);
    await p.setBool('export_csv',         exportCsv);
    await p.setBool('export_decklist',    exportDecklist);
    await p.setBool('export_images',      exportImages);
    await p.setBool('export_pdf',         exportPdf);
    await p.setBool('export_mtgo',        exportMtgo);
    await p.setBool('export_arena',       exportArena);
    await p.setBool('draw_crop_marks',    drawCropMarks);
    await p.setDouble('bleed_mm',         bleedMm);
    notifyListeners();
  }

  void setFormat(String v)       { format = v;         save(); }
  void setPaperSize(String v)    { paperSize = v;       save(); }
  void setExportJson(bool v)     { exportJson = v;      save(); }
  void setExportCsv(bool v)      { exportCsv = v;       save(); }
  void setExportDecklist(bool v) { exportDecklist = v;  save(); }
  void setExportImages(bool v)   { exportImages = v;    save(); }
  void setExportPdf(bool v)      { exportPdf = v;       save(); }
  void setExportMtgo(bool v)     { exportMtgo = v;      save(); }
  void setExportArena(bool v)    { exportArena = v;     save(); }
  void setDrawCropMarks(bool v)  { drawCropMarks = v;   save(); }
  void setBleedMm(double v)      { bleedMm = v;         save(); }
}
