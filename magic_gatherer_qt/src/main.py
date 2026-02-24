import sys
import os
import logging
import traceback
sys.path.append(os.path.dirname(os.path.abspath(__file__)))
import json
import time
from pathlib import Path
import requests
from PyQt5.QtWidgets import (QApplication, QSplashScreen, QMainWindow, QWidget,
                             QVBoxLayout, QHBoxLayout, QLineEdit, QCompleter, QListView,
                             QTextEdit, QPushButton, QCheckBox, QComboBox, QFileDialog, QMessageBox,
                             QGroupBox, QRadioButton, QButtonGroup, QGridLayout, QProgressBar, QLabel,
                             QDialog, QTabWidget, QSpinBox, QDoubleSpinBox)
from PyQt5.QtGui import QPixmap, QStandardItemModel, QStandardItem, QCursor
from PyQt5.QtCore import QThread, pyqtSignal, Qt, QPoint, QTimer
from ui_core import StyledPane, HeaderLabel, BodyLabel, ErrorTicker, CrossfadeImage, PANE_BG, CANVAS_BG, ACCENT_COLOR, FuzzyProxyModel, HoverPreviewManager, CardPreviewWindow
from discovery import DiscoveryWidget
from image_fetcher import ImageFetchThread
from deck_doctor import DeckDoctorWindow
from exporters import export_json, export_csv
from logic import gather_cards, export_images, export_pdf, export_mtgo_dek, generate_arena_clipboard
from api import safe_get, safe_post

CACHE_DIR = Path.home() / ".magicgatherer" / "cache"
COMMANDERS_JSON_PATH = CACHE_DIR / "commanders.json"
USER_AGENT = {"User-Agent": "MagicGatherer/3.0.0"}

def get_cached_image(url: str, filename: str) -> Path:
    """Downloads JPEGs once, saves to CACHE_DIR and returns the local path."""
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    filepath = CACHE_DIR / filename
    if not filepath.exists():
        response = requests.get(url, headers=USER_AGENT)
        response.raise_for_status()
        with open(filepath, 'wb') as f:
            f.write(response.content)
        time.sleep(0.1)  # Respect rate limit
    return filepath

class SmartChecksumThread(QThread):
    progress_update = pyqtSignal(str)
    fetch_complete = pyqtSignal(list)

    def run(self):
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        self.progress_update.emit("Checking Scryfall for new commanders...")
        
        url = "https://api.scryfall.com/cards/search"
        params = {"q": "is:commander"}
        
        try:
            # 1. Single GET to check total_cards
            resp = requests.get(url, params=params, headers=USER_AGENT)
            resp.raise_for_status()
            data = resp.json()
            total_cards = data.get("total_cards", 0)
            
            # 2. Compare to local commanders.json and check 7-day TTL
            local_total = -1
            commanders = []
            if COMMANDERS_JSON_PATH.exists():
                file_mtime = COMMANDERS_JSON_PATH.stat().st_mtime
                # 604800 seconds = 7 days
                if time.time() - file_mtime < 604800:
                    with open(COMMANDERS_JSON_PATH, "r", encoding="utf-8") as f:
                        cached_data = json.load(f)
                        commanders = cached_data.get("data", [])
                        if commanders:
                            self.progress_update.emit("Cache is still fresh (< 7 days).")
                            time.sleep(0.5)
                            self.fetch_complete.emit(commanders)
                            return
                            
                # If TTL expired or missing, still try to load local_total for total_cards match
                with open(COMMANDERS_JSON_PATH, "r", encoding="utf-8") as f:
                    cached_data = json.load(f)
                    local_total = cached_data.get("total_cards", -1)
                    commanders = cached_data.get("data", [])

            # 3. Match: bypass
            if total_cards == local_total and commanders:
                self.progress_update.emit("Local cache is up to date!")
                time.sleep(0.5) # brief pause for visual UX on splash
                self.fetch_complete.emit(commanders)
                return
                
            # 4. Mismatch: paginate
            self.progress_update.emit(f"Mismatch found. Fetching {total_cards} commanders...")
            all_commanders = []
            has_more = True
            current_url = f"{url}?q=is:commander"
            
            while has_more:
                r = requests.get(current_url, headers=USER_AGENT)
                r.raise_for_status()
                page_data = r.json()
                
                # Extract names for autocomplete
                for card in page_data.get("data", []):
                    all_commanders.append(card.get("name"))
                
                has_more = page_data.get("has_more", False)
                if has_more:
                    current_url = page_data.get("next_page")
                    time.sleep(0.1) # Strict enforcement
            
            # Remove duplicates and sort
            all_commanders = sorted(list(set(all_commanders)))
            
            cache_payload = {
                "total_cards": total_cards,
                "data": all_commanders
            }
            with open(COMMANDERS_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(cache_payload, f)
                
            self.progress_update.emit("Download complete. Starting application...")
            time.sleep(0.5)
            self.fetch_complete.emit(all_commanders)
            
        except Exception as e:
            self.progress_update.emit(f"Error fetching data: {e}")
            time.sleep(2)
            self.fetch_complete.emit([]) # fallback empty



class StapleFetchThread(QThread):
    staple_fetched = pyqtSignal(dict)
    finished_fetching = pyqtSignal()
    
    def __init__(self, commander_name):
        super().__init__()
        self.commander_name = commander_name
        
    def run(self):
        # 1. Fetch Commander exact to get color identity
        try:
            url = "https://api.scryfall.com/cards/named"
            resp = safe_get(url, params={"exact": self.commander_name})
            resp.raise_for_status()
            commander = resp.json()
            
            self.staple_fetched.emit(commander) # Emit commander first to set identity
            
            # 2. Fetch EDHREC staples for this color identity
            identity = "".join(commander.get("color_identity", []))
            if not identity:
                identity = "c"
                
            query = f"id<={identity} -is:commander sort=edhrec"
            search_url = "https://api.scryfall.com/cards/search"
            r = safe_get(search_url, params={"q": query})
            r.raise_for_status()
            
            # 3. Emit first page of staples (top 40-50 approx)
            staples = r.json().get("data", [])
            for st in staples:
                self.staple_fetched.emit(st)
                
        except Exception as e:
            print(f"Deck Doctor fetch error: {e}")
            
        self.finished_fetching.emit()

class DeckAnalysisThread(QThread):
    cards_fetched = pyqtSignal(list)
    error_occurred = pyqtSignal(str)
    
    def __init__(self, raw_text):
        super().__init__()
        self.raw_text = raw_text
        
    def run(self):
        try:
            lines = self.raw_text.strip().split('\n')
            parsed_names = []
            for line in lines:
                line = line.strip()
                if not line: continue
                # Strip leading quantities and trailing set codes
                # "1 Sol Ring (C19) 23" -> "Sol Ring"
                # regex: optional digits/x at start, extract everything up to first parenthesis
                import re
                match = re.match(r'^(?:[0-9]+x?\s+)?([^\(]+)', line)
                if match:
                    name = match.group(1).strip()
                    parsed_names.append(name)
                    
            if not parsed_names:
                self.cards_fetched.emit([])
                return
                
            all_cards = []
            # Scryfall limits to 75 identifiers per POST
            chunk_size = 75
            for i in range(0, len(parsed_names), chunk_size):
                chunk = parsed_names[i:i+chunk_size]
                payload = {"identifiers": [{"name": name} for name in chunk]}
                
                resp = safe_post("https://api.scryfall.com/cards/collection", json=payload)
                resp.raise_for_status()
                data = resp.json()
                all_cards.extend(data.get("data", []))
                
            self.cards_fetched.emit(all_cards)
        except Exception as e:
            self.error_occurred.emit(str(e))

class GatherWorker(QThread):
    log_added = pyqtSignal(str)
    progress_made = pyqtSignal(float)
    finished_ok = pyqtSignal()
    error_occurred = pyqtSignal(str)

    def __init__(self, deck_data, save_dir, prefix, options):
        super().__init__()
        self.deck_data = deck_data
        self.save_dir = Path(save_dir)
        self.prefix = prefix
        self.options = options

    def run(self):
        try:
            if not self.deck_data:
                self.error_occurred.emit("No deck data provided to export.")
                return

            def log_wrap(msg): self.log_added.emit(msg)
            def prog_wrap(val): self.progress_made.emit(val)

            # deck_data is already parsed Scryfall card dicts — export directly
            opts = self.options
            save_dir = self.save_dir
            prefix = self.prefix
            save_dir.mkdir(parents=True, exist_ok=True)

            from exporters import (
                export_json, export_csv, export_mtgo_dek,
                export_images, export_pdf, generate_arena_clipboard, sanitize_filename
            )
            safe_prefix = sanitize_filename(prefix)

            if opts.get("json"):
                export_json(self.deck_data, save_dir, safe_prefix)
                log_wrap("JSON Exported.")
            if opts.get("csv"):
                export_csv(self.deck_data, save_dir, safe_prefix)
                log_wrap("CSV Exported.")
            if opts.get("mtgo"):
                export_mtgo_dek(self.deck_data, save_dir / f"{safe_prefix}.dek")
                log_wrap("MTGO .dek Exported.")
            if opts.get("arena"):
                arena_str = generate_arena_clipboard(self.deck_data)
                from PyQt5.QtWidgets import QApplication
                QApplication.clipboard().setText(arena_str)
                log_wrap("MTG Arena string copied to clipboard!")

            if opts.get("img") or opts.get("pdf"):
                export_images(self.deck_data, save_dir, safe_prefix, log_wrap, prog_wrap, 20, 80)
                if opts.get("pdf"):
                    export_pdf(self.deck_data, save_dir, safe_prefix, log_wrap, opts.get("pdf_settings"))
                    log_wrap("PDF Proxies Generated.")

            prog_wrap(100.0)
            self.finished_ok.emit()
        except Exception as e:
            self.error_occurred.emit(str(e))


def create_groupbox(title: str) -> QGroupBox:
    gb = QGroupBox(title)
    gb.setStyleSheet(f"""
        QGroupBox {{
            background-color: {PANE_BG};
            border: 1px solid #4C4C4C;
            border-radius: 6px;
            margin-top: 12px;
            padding-top: 20px;
            color: #E0E0E0;
            font-weight: bold;
        }}
        QGroupBox::title {{
            subcontrol-origin: margin;
            left: 10px;
            padding: 0 4px 0 4px;
        }}
    """)
    return gb
            
class PdfSettingsDialog(QDialog):
    def __init__(self, parent=None, current_settings=None):
        super().__init__(parent)
        self.setWindowTitle("Advanced PDF Settings")
        self.resize(400, 600)
        self.setStyleSheet(f"background-color: {CANVAS_BG}; color: white;")
        layout = QVBoxLayout(self)
        
        self.tabs = QTabWidget()
        self.tabs.setStyleSheet(f"QTabBar::tab {{ background-color: {PANE_BG}; padding: 8px 16px; border: 1px solid #4C4C4C; }} QTabBar::tab:selected {{ background-color: {ACCENT_COLOR}; }}")
        
        # --- TAB 1: Layout ---
        tab_layout = QWidget()
        l_layout = QVBoxLayout(tab_layout)
        
        gb_page = create_groupbox("Page Size")
        v_page = QVBoxLayout(gb_page)
        self.combo_paper = QComboBox()
        self.combo_paper.addItems(["US Letter", "A4", "A3", "Legal", "A5", "Tabloid"])
        self.combo_paper.setStyleSheet(f"background-color: {PANE_BG}; padding: 4px;")
        v_page.addWidget(self.combo_paper)
        l_layout.addWidget(gb_page)
        
        gb_grid = create_groupbox("Grid Size")
        h_grid = QHBoxLayout(gb_grid)
        self.spin_cols = QSpinBox()
        self.spin_cols.setRange(1, 10)
        self.spin_cols.setValue(3)
        self.spin_rows = QSpinBox()
        self.spin_rows.setRange(1, 10)
        self.spin_rows.setValue(3)
        h_grid.addWidget(QLabel("Columns:"))
        h_grid.addWidget(self.spin_cols)
        h_grid.addWidget(QLabel("Rows:"))
        h_grid.addWidget(self.spin_rows)
        l_layout.addWidget(gb_grid)
        
        gb_bleed = create_groupbox("Bleed Settings")
        v_bleed = QVBoxLayout(gb_bleed)
        self.chk_bleed = QCheckBox("Enable Bleed Edge")
        self.spin_bleed = QDoubleSpinBox()
        self.spin_bleed.setRange(0, 10)
        self.spin_bleed.setValue(1.0)
        self.spin_bleed.setSuffix(" mm")
        v_bleed.addWidget(self.chk_bleed)
        v_bleed.addWidget(self.spin_bleed)
        l_layout.addWidget(gb_bleed)
        
        self.tabs.addTab(tab_layout, "Layout")
        
        # --- TAB 2: Card ---
        tab_card = QWidget()
        c_layout = QVBoxLayout(tab_card)
        
        gb_space = create_groupbox("Card Spacing")
        v_space = QVBoxLayout(gb_space)
        self.spin_space_x = QDoubleSpinBox()
        self.spin_space_x.setRange(0, 50)
        self.spin_space_x.setValue(0.0)
        self.spin_space_x.setSuffix(" mm (Horizontal)")
        self.spin_space_y = QDoubleSpinBox()
        self.spin_space_y.setRange(0, 50)
        self.spin_space_y.setValue(0.0)
        self.spin_space_y.setSuffix(" mm (Vertical)")
        v_space.addWidget(self.spin_space_x)
        v_space.addWidget(self.spin_space_y)
        c_layout.addWidget(gb_space)
        
        gb_offset = create_groupbox("Global Print Offset")
        v_offset = QVBoxLayout(gb_offset)
        self.spin_off_x = QDoubleSpinBox()
        self.spin_off_x.setRange(-100, 100)
        self.spin_off_x.setValue(0.0)
        self.spin_off_x.setSuffix(" mm")
        self.spin_off_y = QDoubleSpinBox()
        self.spin_off_y.setRange(-100, 100)
        self.spin_off_y.setValue(0.0)
        self.spin_off_y.setSuffix(" mm")
        v_offset.addWidget(QLabel("Horizontal Offset:"))
        v_offset.addWidget(self.spin_off_x)
        v_offset.addWidget(QLabel("Vertical Offset:"))
        v_offset.addWidget(self.spin_off_y)
        c_layout.addWidget(gb_offset)
        
        self.tabs.addTab(tab_card, "Card")
        
        # --- TAB 3: Guides & DPI ---
        tab_guides = QWidget()
        g_layout = QVBoxLayout(tab_guides)
        
        gb_guide = create_groupbox("Crop Guides")
        v_guide = QVBoxLayout(gb_guide)
        self.chk_guides = QCheckBox("Enable Crop Guides")
        self.chk_guides.setChecked(True)
        self.combo_guides = QComboBox()
        self.combo_guides.addItems(["Corners", "Full Outline", "Edges"])
        self.combo_guides.setStyleSheet(f"background-color: {PANE_BG}; padding: 4px;")
        v_guide.addWidget(self.chk_guides)
        v_guide.addWidget(self.combo_guides)
        g_layout.addWidget(gb_guide)
        
        gb_dpi = create_groupbox("Render Quality")
        v_dpi = QVBoxLayout(gb_dpi)
        self.combo_dpi = QComboBox()
        self.combo_dpi.addItems(["300 (Fastest)", "600 (Fast)", "900 (Sharp)", "1200 (High Quality)", "1489 (Max)"])
        self.combo_dpi.setCurrentIndex(2) # Default 900
        self.combo_dpi.setStyleSheet(f"background-color: {PANE_BG}; padding: 4px;")
        v_dpi.addWidget(self.combo_dpi)
        g_layout.addWidget(gb_dpi)
        
        self.tabs.addTab(tab_guides, "Guides")
        
        layout.addWidget(self.tabs)
        
        btn_box = QHBoxLayout()
        btn_box.addStretch()
        btn_save = QPushButton("Save Settings")
        btn_save.setStyleSheet(f"background-color: {ACCENT_COLOR}; color: white; padding: 8px 16px; border-radius: 4px;")
        btn_save.clicked.connect(self.accept)
        btn_box.addWidget(btn_save)
        layout.addLayout(btn_box)
        
        if current_settings:
            self.load_settings(current_settings)
            
    def load_settings(self, s):
        self.combo_paper.setCurrentText(s.get("paper_size", "US Letter"))
        self.spin_cols.setValue(s.get("cols", 3))
        self.spin_rows.setValue(s.get("rows", 3))
        self.chk_bleed.setChecked(s.get("bleed_enabled", False))
        self.spin_bleed.setValue(s.get("bleed_mm", 1.0))
        self.spin_space_x.setValue(s.get("space_x", 0.0))
        self.spin_space_y.setValue(s.get("space_y", 0.0))
        self.spin_off_x.setValue(s.get("off_x", 0.0))
        self.spin_off_y.setValue(s.get("off_y", 0.0))
        self.chk_guides.setChecked(s.get("guides_enabled", True))
        self.combo_guides.setCurrentText(s.get("guide_type", "Corners"))
        self.combo_dpi.setCurrentText(str(s.get("dpi_preset", "900 (Sharp)")))
        
    def get_settings(self):
        dpi_str = self.combo_dpi.currentText().split(' ')[0]
        return {
            "paper_size": self.combo_paper.currentText(),
            "cols": self.spin_cols.value(),
            "rows": self.spin_rows.value(),
            "bleed_enabled": self.chk_bleed.isChecked(),
            "bleed_mm": self.spin_bleed.value(),
            "space_x": self.spin_space_x.value(),
            "space_y": self.spin_space_y.value(),
            "off_x": self.spin_off_x.value(),
            "off_y": self.spin_off_y.value(),
            "guides_enabled": self.chk_guides.isChecked(),
            "guide_type": self.combo_guides.currentText(),
            "dpi": int(dpi_str),
            "dpi_preset": self.combo_dpi.currentText()
        }



class DiscoveryWindow(QMainWindow):
    def __init__(self, parent=None):
        super().__init__()
        if parent:
            self.setParent(parent)
            self.setWindowFlags(Qt.Window)
        self.setWindowTitle("MagicGatherer - Deck Roller 🎲")
        self.resize(500, 600)
        self.setStyleSheet(f"background-color: {CANVAS_BG};")
        
        self.widget = DiscoveryWidget()
        self.setCentralWidget(self.widget)

class MainWindow(QMainWindow):
    def __init__(self, commanders):
        super().__init__()
        self.setWindowTitle("MagicGatherer v3.0")
        self.resize(1000, 800)
        self.setStyleSheet(f"background-color: {CANVAS_BG};")
        
        # Auxiliary Windows
        self.discovery_window = DiscoveryWindow(self)
        self.discovery_window.widget.preview_requested.connect(self.on_preview_requested)
        self.discovery_window.widget.build_requested.connect(self.on_build_requested)
        self.discovery_window.widget.export_requested.connect(self.on_export_requested)
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QVBoxLayout(main_widget)
        main_layout.setContentsMargins(16, 16, 16, 16)
        main_layout.setSpacing(16)
        
        # Helper to create styled group boxes
        def create_groupbox(title):
            gb = QGroupBox(title)
            gb.setStyleSheet(f"""
                QGroupBox {{
                    color: white;
                    border: 1px solid #4C4C4C;
                    border-radius: 4px;
                    margin-top: 1ex;
                    font-size: 13px;
                }}
                QGroupBox::title {{
                    subcontrol-origin: margin;
                    left: 10px;
                    padding: 0 3px 0 3px;
                }}
            """)
            return gb

        # --- 1. Select Input Source ---
        gb_input = create_groupbox("1. Select Input Source")
        layout_input = QVBoxLayout(gb_input)
        layout_input.setContentsMargins(16, 24, 16, 16)
        layout_input.setSpacing(12)
        
        self.radio_paste = QRadioButton("Paste List")
        self.radio_file = QRadioButton("Local File:")
        self.radio_edhrec = QRadioButton("EDHREC Commander:")
        self.radio_paste.setChecked(True)
        
        self.input_group = QButtonGroup()
        self.input_group.addButton(self.radio_paste)
        self.input_group.addButton(self.radio_file)
        self.input_group.addButton(self.radio_edhrec)
        
        # Paste Text Area
        self.paste_area = QTextEdit()
        self.paste_area.setFixedHeight(100)
        self.paste_area.setPlaceholderText("Paste your decklist here...")
        self.paste_area.setStyleSheet(f"""
            QTextEdit {{
                background-color: {PANE_BG};
                color: rgba(255, 255, 255, 178);
                border: 1px solid #2C2C2C;
                border-radius: 4px;
                padding: 8px;
                font-family: monospace;
            }}
        """)
        
        # File selector row
        row_file = QHBoxLayout()
        row_file.addWidget(self.radio_file)
        self.file_input = QLineEdit()
        self.file_input.setReadOnly(True)
        self.file_input.setStyleSheet(f"background-color: {PANE_BG}; color: white; border: 1px solid #2C2C2C; border-radius: 4px; padding: 4px;")
        self.btn_browse = QPushButton("Browse")
        self.btn_browse.setStyleSheet("background-color: #3C3C3C; color: rgba(255, 255, 255, 150); border: 1px solid #2C2C2C; border-radius: 4px; padding: 4px 12px;")
        self.btn_browse.clicked.connect(self.browse_file)
        row_file.addWidget(self.file_input, stretch=1)
        row_file.addWidget(self.btn_browse)
        
        # EDHREC selector row
        row_edhrec = QHBoxLayout()
        row_edhrec.addWidget(self.radio_edhrec)
        self.search_input = QLineEdit()
        self.search_input.setStyleSheet(f"background-color: {PANE_BG}; color: white; border: 1px solid #2C2C2C; border-radius: 4px; padding: 4px;")
        
        # EDHREC Autocomplete bounds
        self.source_model = QStandardItemModel()
        for c in commanders:
            self.source_model.appendRow(QStandardItem(c))
        self.proxy_model = FuzzyProxyModel()
        self.proxy_model.setSourceModel(self.source_model)
        self.completer = QCompleter(self.proxy_model, self)
        self.completer.setCompletionMode(QCompleter.PopupCompletion)
        self.completer.setCaseSensitivity(Qt.CaseInsensitive)
        popup = QListView()
        popup.setStyleSheet(f"""
            QListView {{
                background-color: {PANE_BG};
                color: white;
                border: 1px solid #2C2C2C;
                selection-background-color: #4C4C4C;
                padding: 4px;
            }}
            QListView::item {{
                font-weight: 600;
                padding: 6px;
                color: rgba(255, 255, 255, 200);
            }}
        """)
        self.completer.setPopup(popup)
        self.search_input.setCompleter(self.completer)
        self.search_input.textChanged.connect(self.update_filter)
        self.completer.activated.connect(self.on_completer_activated)
        
        # Attach HoverPreviewManager to the completer list view
        self.preview_manager = HoverPreviewManager(popup, self.fetch_image)
        
        row_edhrec.addWidget(self.search_input, stretch=1)
        
        # Dynamic visibility
        def toggle_inputs():
            self.paste_area.setEnabled(self.radio_paste.isChecked())
            self.file_input.setEnabled(self.radio_file.isChecked())
            self.btn_browse.setEnabled(self.radio_file.isChecked())
            self.search_input.setEnabled(self.radio_edhrec.isChecked())
        
        self.radio_paste.toggled.connect(toggle_inputs)
        self.radio_file.toggled.connect(toggle_inputs)
        self.radio_edhrec.toggled.connect(toggle_inputs)
        toggle_inputs()
        
        layout_input.addWidget(self.radio_paste)
        layout_input.addWidget(self.paste_area)
        layout_input.addLayout(row_file)
        layout_input.addLayout(row_edhrec)
        
        # Deck Doctor / Deck Roller buttons
        self.btn_analyze = QPushButton("🩺 Launch Deck Doctor")
        self.btn_analyze.setStyleSheet(f"""
            QPushButton {{
                background-color: #007AFF;
                color: white;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #0056b3;
            }}
        """)
        self.btn_analyze.clicked.connect(self.on_launch_deckdoctor)
        
        self.btn_roller = QPushButton("🎲 Launch Deck Roller")
        self.btn_roller.setStyleSheet(f"""
            QPushButton {{
                background-color: #007AFF;
                color: white;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #0056b3;
            }}
        """)
        self.btn_roller.clicked.connect(self.on_launch_deckroller)
        
        self.btn_help = QPushButton("❓ Help")
        self.btn_help.setStyleSheet(f"""
            QPushButton {{
                background-color: #2C2C2C;
                color: {ACCENT_COLOR};
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #4C4C4C;
            }}
        """)
        self.btn_help.clicked.connect(self.show_help)
        
        self.btn_export_logs = QPushButton("📄 Export Logs")
        self.btn_export_logs.setStyleSheet(f"""
            QPushButton {{
                background-color: #2C2C2C;
                color: #A3C095;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #4C4C4C;
            }}
        """)
        self.btn_export_logs.clicked.connect(self.export_logs)
        
        btn_row = QHBoxLayout()
        btn_row.addWidget(self.btn_analyze)
        btn_row.addWidget(self.btn_roller)
        btn_row.addWidget(self.btn_export_logs)
        btn_row.addWidget(self.btn_help)
        layout_input.addLayout(btn_row)
        
        main_layout.addWidget(gb_input)
        
        # --- 2. Select Format ---
        gb_format = create_groupbox("2. Select Format")
        layout_fmt = QVBoxLayout(gb_format)
        layout_fmt.setContentsMargins(16, 20, 16, 16)
        layout_fmt.setSpacing(8)
        
        self.radio_paper = QRadioButton("Paper (Every exact card)")
        self.radio_arena = QRadioButton("Arena Only (Skip non-Arena cards)")
        self.radio_mtgo = QRadioButton("MTGO Only (Skip non-MTGO cards)")
        self.radio_paper.setChecked(True)
        
        layout_fmt.addWidget(self.radio_paper)
        layout_fmt.addWidget(self.radio_arena)
        layout_fmt.addWidget(self.radio_mtgo)
        main_layout.addWidget(gb_format)
        
        # --- 3. Output Options ---
        gb_output = create_groupbox("3. Output Options")
        layout_out = QVBoxLayout(gb_output)
        layout_out.setContentsMargins(16, 24, 16, 16)
        
        grid_out = QGridLayout()
        grid_out.setVerticalSpacing(16)
        
        self.chk_json = QCheckBox("JSON Data")
        self.chk_csv = QCheckBox("CSV Spreadsheet")
        self.chk_mtgo = QCheckBox("MTGO .dek XML")
        self.chk_arena = QCheckBox("Copy to Arena Clipboard")
        self.chk_txt = QCheckBox("Decklist Textfile")
        
        self.chk_img = QCheckBox("High-Res PNGs")
        self.chk_pdf = QCheckBox("PDF Print Proxies")
        self.chk_csv.setChecked(True)
        self.chk_img.setChecked(True)
        self.chk_pdf.setChecked(True)
        
        self.chk_pdf.toggled.connect(self.toggle_pdf_options)
        self.chk_img.stateChanged.connect(self.on_img_toggled)
        
        self.combo_pdf_pad = QPushButton("⚙️ Advanced PDF Settings...")
        self.combo_pdf_pad.setStyleSheet(f"background-color: #3C3C3C; color: white; border: 1px solid #2C2C2C; padding: 4px 8px; border-radius: 4px;")
        self.combo_pdf_pad.clicked.connect(self.open_pdf_settings)
        
        self.pdf_settings_cache = {
            "paper_size": "US Letter",
            "cols": 3, "rows": 3,
            "bleed_enabled": False, "bleed_mm": 1.0,
            "space_x": 0.0, "space_y": 0.0,
            "off_x": 0.0, "off_y": 0.0,
            "guides_enabled": True, "guide_type": "Corners",
            "dpi": 900, "dpi_preset": "900 (Sharp)"
        }
        
        # Row 1 (Data)
        grid_out.addWidget(self.chk_json, 0, 0)
        grid_out.addWidget(self.chk_csv, 0, 1)
        grid_out.addWidget(self.chk_mtgo, 0, 2)
        grid_out.addWidget(self.chk_arena, 0, 3)
        grid_out.addWidget(self.chk_txt, 0, 4)
        
        # Row 2 (Media)
        grid_out.addWidget(self.chk_img, 1, 0)
        grid_out.addWidget(self.chk_pdf, 1, 1)
        grid_out.addWidget(self.combo_pdf_pad, 1, 2)
        
        layout_out.addLayout(grid_out)
        main_layout.addWidget(gb_output)
        
        # --- Big Export Button ---
        self.btn_export = QPushButton("Gather your Magic")
        self.btn_export.setStyleSheet(f"""
            QPushButton {{
                background-color: #333333;
                color: white;
                border-radius: 4px;
                padding: 16px;
                font-size: 18px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #1A1A1A;
            }}
        """)
        self.btn_export.clicked.connect(self.on_gather_clicked)
        main_layout.addWidget(self.btn_export)
        
        # Progress Bar visualizer
        self.progress_bar = QProgressBar()
        self.progress_bar.setFixedHeight(4)
        self.progress_bar.setTextVisible(False)
        self.progress_bar.setStyleSheet("""
            QProgressBar {
                border: none;
                background-color: #2C2C2C;
            }
            QProgressBar::chunk {
                background-color: #007AFF;
            }
        """)
        main_layout.addWidget(self.progress_bar)
        
        # --- 4. Console Logs ---
        gb_console = create_groupbox("Console Log")
        layout_console = QHBoxLayout(gb_console)
        layout_console.setContentsMargins(12, 16, 12, 12)
        
        self.log_exec = QTextEdit()
        self.log_exec.setReadOnly(True)
        self.log_exec.setStyleSheet(f"background-color: black; color: #4CAF50; border: 1px solid #2C2C2C; font-family: monospace; font-size: 12px;")
        self.log_exec.setText("Execution logs will appear here...")
        
        self.log_err = QTextEdit()
        self.log_err.setReadOnly(True)
        self.log_err.setStyleSheet(f"background-color: #1A0D0D; color: #F44336; border: 1px solid #2C2C2C; font-family: monospace; font-size: 12px;")
        self.log_err.setText("Any skipped or non-legal cards will appear here")
        
        layout_console.addWidget(self.log_exec, stretch=2)
        layout_console.addWidget(self.log_err, stretch=1)
        main_layout.addWidget(gb_console, stretch=1)
        
        # --- Bottom Footer ---
        footer = QHBoxLayout()
        self.btn_tui = QPushButton("Launch TUI")
        self.btn_tui.setStyleSheet("background-color: #2C2C2C; color: rgba(255,255,255,150); padding: 6px 16px; border-radius: 4px;")
        self.btn_tui.clicked.connect(self.on_launch_tui)
        
        self.btn_cache = QPushButton("Clear Cache")
        self.btn_cache.setStyleSheet("background-color: #2C2C2C; color: rgba(255,255,255,150); padding: 6px 16px; border-radius: 4px;")
        self.btn_cache.clicked.connect(self.on_clear_cache)
        
        footer.addWidget(self.btn_tui)
        footer.addWidget(self.btn_cache)
        footer.addStretch()
        footer.addWidget(QLabel("by yuhidev", styleSheet="color: rgba(255,255,255,100);"))
        
        main_layout.addLayout(footer)

    def open_pdf_settings(self):
        dlg = PdfSettingsDialog(self, current_settings=self.pdf_settings_cache)
        if dlg.exec_():
            self.pdf_settings_cache = dlg.get_settings()
            
    def browse_file(self):
        filename, _ = QFileDialog.getOpenFileName(self, "Select Decklist text file", "", "Text Files (*.txt);;All Files (*)")
        if filename:
            self.file_input.setText(filename)
            with open(filename, 'r', encoding='utf-8') as f:
                self.paste_area.setText(f.read())
            
    def update_filter(self, text):
        self.proxy_model.setFilterRegExp(text)
        
    def get_discovery_preview(self, name):
        self.statusBar().showMessage(f"Fetching {name}...", 3000)
        self.fetch_image(name)
        
    def on_completer_activated(self, text):
        self.preview_manager.preview_window.hide()
        self.statusBar().showMessage(f"Selected: {text}", 3000)
        
    def display_image(self, filepath):
        pixmap = QPixmap(filepath)
        self.preview_manager.display_image(pixmap)
        
        self.statusBar().showMessage("Artwork preview loaded.", 2000)
        
    def on_launch_deckroller(self):
        self.discovery_window.show()
        self.discovery_window.activateWindow()

    def on_preview_requested(self, name):
        self.statusBar().showMessage(f"Fetching {name}...", 3000)
        self.fetch_image(name)
        
    def on_build_requested(self, name):
        # Explicitly "Send to Doctor" Route
        self.search_input.setText(name)
        self.radio_edhrec.setChecked(True)
        self.on_launch_deckdoctor()
        self.deck_doctor_window.cmd_input.setText(name)
        self.deck_doctor_window.request_analysis()
        self.statusBar().showMessage(f"Sent {name} to the Deck Doctor!", 3000)
        self.discovery_window.hide()
        
    def on_export_requested(self, name):
        # Explicitly "Send to Exporter" Route
        self.search_input.setText(name)
        self.radio_edhrec.setChecked(True)
        self.statusBar().showMessage(f"Sent {name} to Exporter! Click 'Gather' to begin.", 3000)
        self.discovery_window.hide()
        
    # --- Export / Gather Logic ---
    def toggle_pdf_options(self):
        visible = self.chk_pdf.isChecked() and self.chk_pdf.isEnabled()
        self.combo_pdf_pad.setVisible(visible)
        
    def on_img_toggled(self, state):
        is_checked = (state == Qt.Checked)
        self.chk_pdf.setEnabled(is_checked)
        if not is_checked:
            self.chk_pdf.setChecked(False)
        self.toggle_pdf_options()
        
    def fetch_staples(self, commander_name):
        self.statusBar().showMessage(f"Fetching EDHREC baseline for {commander_name}...", 3000)
        self.staple_thread = StapleFetchThread(commander_name)
        self.current_decklist_data = [] # To accumulate the fetched deck
        self.staple_thread.staple_fetched.connect(self.on_staple_received)
        self.staple_thread.finished_fetching.connect(self.on_staples_finished)
        self.staple_thread.start()
        
    def on_staple_received(self, card_data):
        self.current_decklist_data.append(card_data)
        self.statusBar().showMessage(f"Loaded: {card_data.get('name')}")
        
    def on_staples_finished(self):
        self.statusBar().showMessage(f"Loaded {len(self.current_decklist_data)} cards. Ready to Export.", 5000)
            
    def show_help(self):
        QMessageBox.information(self, "MagicGatherer Help", 
            "Welcome!\n\n"
            "1. Choose an Input: Paste a decklist, load a file, or search a Commander.\n"
            "2. Select a Format: Filter out illegal cards for MTGO or Arena.\n"
            "3. Choose Output: Export to PDF (Proxies), CSV, Images, etc.\n"
            "4. Hit 'Gather your Magic' to run the export!\n\n"
            "Use the Deck Doctor to get EDHREC recommendations, or the Deck Roller to find a random commander."
        )

    def on_launch_tui(self):
        import subprocess
        import platform
        from pathlib import Path

        try:
            frozen = getattr(sys, 'frozen', False)

            if platform.system() == "Windows":
                if frozen:
                    exe_dir = Path(sys.executable).parent
                    tui_exe = exe_dir / "MagicGathererTUI.exe"
                    if tui_exe.exists():
                        subprocess.Popen([str(tui_exe)], creationflags=subprocess.CREATE_NEW_CONSOLE)
                        self.statusBar().showMessage("Launching TUI...", 3000)
                    else:
                        self.statusBar().showMessage(
                            "TUI not found. Place MagicGathererTUI.exe next to MagicGatherer.exe", 6000)
                    return
                script_path = Path(__file__).resolve().parent / "tui" / "app.py"
                src_dir = str(Path(__file__).resolve().parent)
                if not script_path.exists():
                    self.statusBar().showMessage(f"TUI script not found: {script_path}", 5000)
                    return
                subprocess.Popen(f'start cmd /k "set PYTHONPATH={src_dir};%PYTHONPATH% && python \"{script_path}\""',
                                 shell=True)
                self.statusBar().showMessage("Launching TUI...", 3000)

            elif platform.system() == "Darwin":
                script_path = Path(__file__).resolve().parent / "tui" / "app.py"
                src_dir = str(Path(__file__).resolve().parent)
                if not script_path.exists():
                    self.statusBar().showMessage(f"TUI not found at {script_path}", 5000)
                    return
                cmd = f'export PYTHONPATH="{src_dir}:$PYTHONPATH" && python3 "{script_path}"'
                subprocess.Popen(["osascript", "-e",
                                  f'tell application "Terminal" to do script "{cmd}"'])
                self.statusBar().showMessage("Launching TUI in Terminal...", 3000)

            else:
                script_path = Path(__file__).resolve().parent / "tui" / "app.py"
                src_dir = str(Path(__file__).resolve().parent)
                if not script_path.exists():
                    self.statusBar().showMessage(f"TUI not found at {script_path}", 5000)
                    return
                cmd_bash = f'export PYTHONPATH="{src_dir}:$PYTHONPATH" && python3 "{script_path}"'
                subprocess.Popen(["x-terminal-emulator", "-e", f"bash -c '{cmd_bash}'"])
                self.statusBar().showMessage("Launching TUI...", 3000)

        except Exception as e:
            self.statusBar().showMessage(f"TUI Launch Error: {e}", 5000)

    def on_clear_cache(self):
        from image_fetcher import CACHE_DIR
        import shutil
        if CACHE_DIR.exists():
            try:
                shutil.rmtree(CACHE_DIR)
                CACHE_DIR.mkdir(parents=True, exist_ok=True)
                self.statusBar().showMessage("Image cache cleared successfully!", 4000)
            except Exception as e:
                self.statusBar().showMessage(f"Failed to clear cache: {e}", 5000)
        else:
            self.statusBar().showMessage("Cache is already empty.", 3000)

    def export_logs(self):
        log_path = Path("magicgatherer_error.log")
        if not log_path.exists():
            self.statusBar().showMessage("No error logs found. The app is healthy!", 4000)
            return
            
        dest, _ = QFileDialog.getSaveFileName(self, "Export Log File", "magicgatherer_error.log", "Log Files (*.log);;All Files (*)")
        if dest:
            try:
                import shutil
                shutil.copy(log_path, dest)
                self.statusBar().showMessage(f"Logs successfully exported to {dest}", 6000)
            except Exception as e:
                self.statusBar().showMessage(f"Failed to export logs: {e}", 6000)

    def on_launch_deckdoctor(self):
        raw_text = self.paste_area.toPlainText()
        
        format_choice = "paper"
        if self.radio_arena.isChecked():
            format_choice = "arena"
        elif self.radio_mtgo.isChecked():
            format_choice = "mtgo"
        
        # Safely reuse the existing DeckDoctorWindow to avoid destroying active QThreads
        if hasattr(self, 'deck_doctor_window'):
            if not self.deck_doctor_window.isVisible():
                self.deck_doctor_window.paste_area.setText(raw_text)
                self.deck_doctor_window.format_choice = format_choice # Update format filter
            self.deck_doctor_window.show()
            self.deck_doctor_window.activateWindow()
            return
            
        self.deck_doctor_window = DeckDoctorWindow(initial_decklist=raw_text, commanders_model=self.source_model, format_choice=format_choice)
        self.deck_doctor_window.dashboard.gap_filler_requested.connect(self.on_gap_filler_requested)
        self.deck_doctor_window.send_to_exporter.connect(self.on_receive_from_doctor)
        self.deck_doctor_window.show()

    def on_gap_filler_requested(self, query):
        self.search_input.setText(query)
        self.radio_edhrec.setChecked(True)
        self.statusBar().showMessage(f"Loaded Gap Filler Query: {query}", 5000)

    def on_receive_from_doctor(self, text, commander_name=""):
        self.paste_area.setText(text)
        if commander_name:
            self.search_input.setText(commander_name)
            self.radio_edhrec.setChecked(True)
        self.statusBar().showMessage("Received updated decklist from Deck Doctor!", 5000)
        
    def on_gather_clicked(self):
        raw_text = self.paste_area.toPlainText().strip()
        has_current_data = hasattr(self, 'current_decklist_data') and self.current_decklist_data
        edhrec_cmd = self.search_input.text().strip() if hasattr(self, 'radio_edhrec') and self.radio_edhrec.isChecked() else ""

        # Validate: need at least one source of cards
        if not has_current_data and not raw_text and not edhrec_cmd:
            self.statusBar().showMessage("Please enter a commander (EDHREC), paste a decklist, or complete a Discovery search first.", 4000)
            return

        save_dir = QFileDialog.getExistingDirectory(self, "Select Output Directory")
        if not save_dir:
            return

        fmt = "paper"
        if self.radio_arena.isChecked(): fmt = "arena"
        elif self.radio_mtgo.isChecked(): fmt = "mtgo"

        self.export_options = {
            "json": self.chk_json.isChecked(),
            "csv": self.chk_csv.isChecked(),
            "img": self.chk_img.isChecked(),
            "pdf": self.chk_pdf.isChecked(),
            "mtgo": self.chk_mtgo.isChecked(),
            "arena": self.chk_arena.isChecked(),
            "save_dir": save_dir,
            "format_filter": fmt,
            "pdf_settings": self.pdf_settings_cache
        }

        self.export_prefix = "Gathered_Deck"
        if self.search_input.text().strip():
            import re
            self.export_prefix = re.sub(r'[\\/*?:"<>|]', "", self.search_input.text().strip())

        if has_current_data:
            self.start_gather_worker(self.current_decklist_data)
        elif edhrec_cmd:
            # EDHREC source: build deck from commander name via logic.py
            self.statusBar().showMessage(f"Fetching EDHREC deck for {edhrec_cmd}...", 3000)
            def _on_edhrec_cards(cards, _):
                self.start_gather_worker(cards)
            self.analysis_thread = DeckAnalysisThread(edhrec_cmd)
            # Use EDHREC mode by patching the input slightly (prefix with !edhrec:)
            # Actually call gather_cards directly in a thread for EDHREC
            from logic import gather_cards as _gc
            from pathlib import Path as _Path
            import threading

            def _edhrec_worker():
                try:
                    cards = []
                    from logic import _fetch_edhrec_full_deck
                    cards = _fetch_edhrec_full_deck(edhrec_cmd, lambda m: self.log_exec.append(m))
                    if cards:
                        # Switch back to main thread
                        self.start_gather_worker(cards)
                    else:
                        self.statusBar().showMessage(f"No cards found for '{edhrec_cmd}' on EDHREC.", 4000)
                except Exception as e:
                    self.statusBar().showMessage(f"EDHREC fetch error: {e}", 5000)

            threading.Thread(target=_edhrec_worker, daemon=True).start()
        else:
            self.statusBar().showMessage("Parsing pasted decklist before gathering...", 3000)
            self.analysis_thread = DeckAnalysisThread(raw_text)
            self.analysis_thread.cards_fetched.connect(lambda cards, cmdr: self.start_gather_worker(cards))
            self.analysis_thread.error_occurred.connect(lambda err: self.statusBar().showMessage(f"Parse Error: {err}"))
            self.analysis_thread.start()


    def start_gather_worker(self, cards):
        if hasattr(self, 'gather_worker') and self.gather_worker.isRunning():
            return
        
        if not cards:
            self.statusBar().showMessage("No valid cards to export.", 3000)
            return
            
        self.gather_worker = GatherWorker(cards, self.export_options["save_dir"], self.export_prefix, self.export_options)
        
        self.gather_worker.log_added.connect(lambda msg: self.log_exec.append(msg))
        self.gather_worker.progress_made.connect(self.progress_bar.setValue)
        self.gather_worker.error_occurred.connect(lambda e: self.log_err.append(f"ERROR: {e}"))
        self.gather_worker.finished_ok.connect(lambda: self.statusBar().showMessage(f"Gather Complete! Saved to {self.export_options['save_dir']}", 5000))
        
        self.progress_bar.setValue(0)
        self.log_exec.append("--- Starting Gather Process ---")
        self.gather_worker.start()
        self.statusBar().showMessage("Gathering in background...", 3000)
            
    def fetch_image(self, card_name, manager_ref=None):
        if manager_ref:
            self.preview_manager = manager_ref # Update current active manager

        # Cancel any previous rapid fetch threads
        if hasattr(self, 'img_thread') and self.img_thread.isRunning():
            self.img_thread.quit()
            
        self.img_thread = ImageFetchThread(card_name=card_name)
        self.img_thread.image_ready.connect(self.display_image)
        self.img_thread.start()

def exception_hook(exctype, value, tb):
    """Global exception handler to capture UI crashes in the log."""
    logging.error("Uncaught exception", exc_info=(exctype, value, tb))
    sys._excepthook(exctype, value, tb)
    
sys._excepthook = sys.excepthook
sys.excepthook = exception_hook

def main():
    app = QApplication(sys.argv)
    
    # ── Force dark theme on every platform (fixes black-on-grey Windows bug) ──
    from PyQt5.QtGui import QPalette, QColor
    dark_palette = QPalette()
    dark_palette.setColor(QPalette.Window,          QColor(28,  28,  30 ))
    dark_palette.setColor(QPalette.WindowText,      QColor(230, 230, 230))
    dark_palette.setColor(QPalette.Base,            QColor(18,  18,  18 ))
    dark_palette.setColor(QPalette.AlternateBase,   QColor(35,  35,  35 ))
    dark_palette.setColor(QPalette.ToolTipBase,     QColor(28,  28,  30 ))
    dark_palette.setColor(QPalette.ToolTipText,     QColor(230, 230, 230))
    dark_palette.setColor(QPalette.Text,            QColor(230, 230, 230))
    dark_palette.setColor(QPalette.Button,          QColor(44,  44,  46 ))
    dark_palette.setColor(QPalette.ButtonText,      QColor(230, 230, 230))
    dark_palette.setColor(QPalette.BrightText,      QColor(255, 255, 255))
    dark_palette.setColor(QPalette.Link,            QColor(42,  130, 218))
    dark_palette.setColor(QPalette.Highlight,       QColor(42,  130, 218))
    dark_palette.setColor(QPalette.HighlightedText, QColor(255, 255, 255))
    dark_palette.setColor(QPalette.Disabled, QPalette.Text,       QColor(120, 120, 120))
    dark_palette.setColor(QPalette.Disabled, QPalette.ButtonText, QColor(120, 120, 120))
    app.setPalette(dark_palette)
    app.setStyle("Fusion")
    # QCheckBox indicators are invisible with the dark Fusion palette unless
    # explicitly styled — the native indicator background becomes black.
    app.setStyleSheet("""
        QCheckBox::indicator {
            width: 14px; height: 14px;
            border: 2px solid #555;
            border-radius: 3px;
            background-color: #2C2C2C;
        }
        QCheckBox::indicator:checked {
            background-color: #007AFF;
            border-color: #007AFF;
        }
        QCheckBox::indicator:hover {
            border-color: #007AFF;
        }
    """)

    # Configure global logging
    logging.basicConfig(level=logging.ERROR, filename='magicgatherer_error.log', filemode='a',
                        format='%(asctime)s - %(levelname)s - %(message)s')
    
    # Setup Splash Screen — works both frozen (PyInstaller) and in source
    if getattr(sys, 'frozen', False):
        base_dir = Path(sys._MEIPASS)
    else:
        base_dir = Path(__file__).resolve().parent.parent
    logo_path = base_dir / "logo.png"
    splash_pixmap = QPixmap(str(logo_path))
    if splash_pixmap.isNull():
        splash_pixmap = QPixmap(400, 300)
        splash_pixmap.fill(Qt.black)
        
    splash = QSplashScreen(splash_pixmap, Qt.WindowStaysOnTopHint | Qt.FramelessWindowHint)
    splash.show()
    
    def update_splash(msg):
        splash.showMessage(msg, Qt.AlignBottom | Qt.AlignCenter, Qt.white)
        
    # Start Checksum Thread
    thread = SmartChecksumThread()
    thread.progress_update.connect(update_splash)
    
    main_window = None
    def on_fetch_complete(commanders):
        nonlocal main_window
        main_window = MainWindow(commanders)
        main_window.show()
        splash.finish(main_window)
        
    thread.fetch_complete.connect(on_fetch_complete)
    thread.start()
    
    sys.exit(app.exec_())

if __name__ == "__main__":
    main()
