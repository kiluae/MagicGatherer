import random
from PyQt5.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QPushButton, 
                             QComboBox, QListWidget, QLabel)
from PyQt5.QtCore import pyqtSignal, QThread
from ui_core import StyledPane, HeaderLabel, CANVAS_BG, PANE_BG, ACCENT_COLOR, HoverPreviewManager
from api import safe_get

class CommanderFetchThread(QThread):
    results_ready = pyqtSignal(list)
    error_occurred = pyqtSignal(str)
    
    def __init__(self, query):
        super().__init__()
        self.query = query
        
    def run(self):
        try:
            url = "https://api.scryfall.com/cards/search"
            resp = safe_get(url, params={"q": self.query})
            resp.raise_for_status()
            data = resp.json()
            
            cards = data.get("data", [])
            
            if "sort=random" not in self.query:
                random.shuffle(cards)
                
            tops = [c["name"] for c in cards[:5]]
            self.results_ready.emit(tops)
        except Exception as e:
            self.error_occurred.emit(str(e))


class CommanderBrowseThread(QThread):
    """Paginates through ALL Scryfall results for a query, emitting each page."""
    page_ready = pyqtSignal(list)  # emits each page as it arrives
    finished_all = pyqtSignal(int) # total count when done
    error_occurred = pyqtSignal(str)

    def __init__(self, query):
        super().__init__()
        self.query = query
        self._abort = False

    def stop(self):
        self._abort = True

    def run(self):
        try:
            url = "https://api.scryfall.com/cards/search"
            # Sort alphabetically for a clean browse experience
            params = {"q": self.query, "order": "name"}
            total = 0
            while url and not self._abort:
                resp = safe_get(url, params=params)
                resp.raise_for_status()
                data = resp.json()
                cards = data.get("data", [])
                names = [c["name"] for c in cards]
                if names:
                    self.page_ready.emit(names)
                    total += len(names)
                url = data.get("next_page")  # None when exhausted
                params = {}  # next_page URL already has query params
            self.finished_all.emit(total)
        except Exception as e:
            self.error_occurred.emit(str(e))



class DiscoveryWidget(StyledPane):
    preview_requested = pyqtSignal(str)
    build_requested = pyqtSignal(str)
    export_requested = pyqtSignal(str)
    
    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)
        
        header_row = QHBoxLayout()
        header_row.addWidget(HeaderLabel("Commander Roller"))
        self.btn_help = QPushButton("❓ Help")
        self.btn_help.setStyleSheet(f"""
            QPushButton {{
                background-color: #2C2C2C;
                color: {ACCENT_COLOR};
                border-radius: 4px;
                padding: 4px 8px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #4C4C4C;
            }}
        """)
        self.btn_help.clicked.connect(self.show_help)
        header_row.addWidget(self.btn_help)
        header_row.addStretch()
        layout.addLayout(header_row)

        
        # WUBRG Toggle Row
        wubrg_layout = QHBoxLayout()
        self.color_buttons = {}
        colors = [('W', '#F8F6D8'), ('U', '#C1D8E9'), ('B', '#BAB1AB'), ('R', '#E49977'), ('G', '#A3C095')]
        
        for code, hexcolor in colors:
            btn = QPushButton(code)
            btn.setCheckable(True)
            btn.setFixedSize(40, 40)
            btn.setStyleSheet(f"""
                QPushButton {{
                    background-color: #2C2C2C;
                    color: {hexcolor};
                    border-radius: 20px;
                    font-weight: bold;
                    font-size: 16px;
                }}
                QPushButton:checked {{
                    background-color: {hexcolor};
                    color: black;
                }}
            """)
            wubrg_layout.addWidget(btn)
            self.color_buttons[code] = btn
            
        layout.addLayout(wubrg_layout)
        
        # Controls Row 1
        ctrl_layout = QHBoxLayout()
        
        self.btn_flip = QPushButton("🎲 Flip Coins")
        self.btn_flip.setStyleSheet(f"""
            QPushButton {{
                background-color: {ACCENT_COLOR};
                color: white;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #0056b3;
            }}
        """)
        self.btn_flip.clicked.connect(lambda: self.trigger_search(randomize=True))
        ctrl_layout.addWidget(self.btn_flip)
        
        self.btn_manual = QPushButton("🔍 Search Library")
        self.btn_manual.setStyleSheet(f"""
            QPushButton {{
                background-color: #4C4C4C;
                color: white;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #2C2C2C;
            }}
        """)
        self.btn_manual.clicked.connect(lambda: self.trigger_search(randomize=False))
        ctrl_layout.addWidget(self.btn_manual)

        self.btn_browse_all = QPushButton("📋 Browse All")
        self.btn_browse_all.setToolTip("List every commander matching the current color and format filters")
        self.btn_browse_all.setStyleSheet(f"""
            QPushButton {{
                background-color: #3A3A3A;
                color: #A0D4A0;
                border-radius: 4px;
                padding: 8px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #2C2C2C;
            }}
        """)
        self.btn_browse_all.clicked.connect(self.trigger_browse_all)
        ctrl_layout.addWidget(self.btn_browse_all)
        
        self.btn_reset = QPushButton("↺")
        self.btn_reset.setToolTip("Reset Colors")
        self.btn_reset.setStyleSheet(f"""
            QPushButton {{
                background-color: #2C2C2C;
                color: white;
                border-radius: 4px;
                padding: 8px;
                font-weight: bold;
                font-size: 16px;
            }}
            QPushButton:pressed {{
                background-color: #4C4C4C;
            }}
        """)
        self.btn_reset.clicked.connect(self.reset_coins)
        ctrl_layout.addWidget(self.btn_reset)
        
        layout.addLayout(ctrl_layout)
        
        # Controls Row 2 (Filters)
        filter_layout = QHBoxLayout()
        
        self.cmc_combo = QComboBox()
        self.cmc_combo.addItems(["Any CMC", "CMC ≤ 3", "CMC 4-5", "CMC ≥ 6"])
        self.cmc_combo.setStyleSheet(self._combo_style())
        filter_layout.addWidget(self.cmc_combo)
        
        self.pop_combo = QComboBox()
        self.pop_combo.addItems(["Random", "Top EDHREC", "Fringe"])
        self.pop_combo.setStyleSheet(self._combo_style())
        filter_layout.addWidget(self.pop_combo)
        
        self.format_combo = QComboBox()
        self.format_combo.addItems(["Paper", "Arena", "MTGO"])
        self.format_combo.setStyleSheet(self._combo_style())
        filter_layout.addWidget(self.format_combo)
        
        layout.addLayout(filter_layout)
        
        # Master-Detail List
        self.list_widget = QListWidget()
        self.list_widget.setStyleSheet(f"""
            QListWidget {{
                background-color: #121212;
                color: white;
                border: 1px solid #2C2C2C;
                border-radius: 4px;
                padding: 4px;
            }}
            QListWidget::item:selected {{
                background-color: {ACCENT_COLOR};
            }}
        """)
        self.list_widget.setFixedHeight(120)
        self.list_widget.itemSelectionChanged.connect(self.on_item_selected)
        layout.addWidget(self.list_widget)
        self._browse_thread = None
        self._browse_count = 0
        

        # Hover Previews
        self.preview_manager = HoverPreviewManager(self.list_widget, self._trigger_hover_fetch)
        
        # Dual-Rout Buttons
        btn_layout = QHBoxLayout()
        
        self.btn_send_doctor = QPushButton("🩺 Send to Doctor")
        self.btn_send_doctor.setEnabled(False)
        self.btn_send_doctor.setStyleSheet(f"""
            QPushButton {{
                background-color: #4C4C4C;
                color: white;
                border-radius: 4px;
                padding: 8px;
                font-weight: bold;
            }}
            QPushButton:disabled {{
                background-color: #2C2C2C;
                color: gray;
            }}
        """)
        self.btn_send_doctor.clicked.connect(self.on_send_doctor_clicked)
        btn_layout.addWidget(self.btn_send_doctor)
        
        self.btn_send_export = QPushButton("🖨️ Send to Exporter")
        self.btn_send_export.setEnabled(False)
        self.btn_send_export.setStyleSheet(f"""
            QPushButton {{
                background-color: #4C4C4C;
                color: white;
                border-radius: 4px;
                padding: 8px;
                font-weight: bold;
            }}
            QPushButton:disabled {{
                background-color: #2C2C2C;
                color: gray;
            }}
        """)
        self.btn_send_export.clicked.connect(self.on_send_export_clicked)
        btn_layout.addWidget(self.btn_send_export)
        
        layout.addLayout(btn_layout)
        
    def _combo_style(self):
        return """
            QComboBox {
                background-color: #2C2C2C;
                color: white;
                border-radius: 4px;
                padding: 4px 8px;
            }
        """
        
    def reset_coins(self):
        self.list_widget.clear()
        for btn in self.color_buttons.values():
            btn.setChecked(False)
        
    def trigger_search(self, randomize=False):
        self.list_widget.clear()
        if randomize:
            self.list_widget.addItem("Flipping true coins & fetching...")
        else:
            self.list_widget.addItem("Fetching manual color search...")
        
        active_colors = []
        for code, btn in self.color_buttons.items():
            if randomize:
                result = random.choice([True, False])
                btn.setChecked(result)
            else:
                result = btn.isChecked()
                
            if result:
                active_colors.append(code)
                
        # Build Scryfall Query
        # "search_identity = 'C'" if empty
        if not active_colors:
            identity = "id=c"
        else:
            identity = "id=" + "".join(active_colors)
            
        pieces = ["is:commander", identity]
        
        cmc_text = self.cmc_combo.currentText()
        if "≤ 3" in cmc_text:
            pieces.append("cmc<=3")
        elif "4-5" in cmc_text:
            pieces.append("cmc>=4 cmc<=5")
        elif "≥ 6" in cmc_text:
            pieces.append("cmc>=6")
            
        pop_text = self.pop_combo.currentText()
        if pop_text == "Top EDHREC":
            pieces.append("sort=edhrec")
        elif pop_text == "Random":
            # Scryfall has no pure sort=random for query matching perfectly but we can fake it by shuffling
            pass 
        
        # Format restriction
        fmt = self.format_combo.currentText()
        if fmt == "Arena":
            pieces.append("game:arena")
        elif fmt == "MTGO":
            pieces.append("game:mtgo")
            
        query = " ".join(pieces)
        
        self.fetcher = CommanderFetchThread(query)
        self.fetcher.results_ready.connect(self.on_fetch_success)
        self.fetcher.error_occurred.connect(self.on_fetch_error)
        self.fetcher.start()

    def _build_query(self):
        """Returns the Scryfall query string from the current filter state (shared by both buttons)."""
        active_colors = [code for code, btn in self.color_buttons.items() if btn.isChecked()]
        identity = "id=" + "".join(active_colors) if active_colors else "id=c"
        pieces = ["is:commander", identity]

        cmc_text = self.cmc_combo.currentText()
        if "≤ 3" in cmc_text:
            pieces.append("cmc<=3")
        elif "4-5" in cmc_text:
            pieces.append("cmc>=4 cmc<=5")
        elif "≥ 6" in cmc_text:
            pieces.append("cmc>=6")

        fmt = self.format_combo.currentText()
        if fmt == "Arena":
            pieces.append("game:arena")
        elif fmt == "MTGO":
            pieces.append("game:mtgo")

        return " ".join(pieces)

    def trigger_browse_all(self):
        """Fetch and list EVERY commander matching current color/CMC/format filters."""
        # Stop any running browse
        if self._browse_thread and self._browse_thread.isRunning():
            self._browse_thread.stop()
            self._browse_thread.wait()

        self.list_widget.clear()
        self._browse_count = 0
        self.list_widget.addItem("📋 Loading all commanders…")

        query = self._build_query()

        self._browse_thread = CommanderBrowseThread(query)
        self._browse_thread.page_ready.connect(self.on_browse_page)
        self._browse_thread.finished_all.connect(self.on_browse_done)
        self._browse_thread.error_occurred.connect(self.on_fetch_error)
        self._browse_thread.start()

    def on_browse_page(self, names):
        """Called for each page of results as they stream in."""
        if self._browse_count == 0:
            self.list_widget.clear()  # Remove the loading placeholder
        for name in names:
            self.list_widget.addItem(name)
        self._browse_count += len(names)

    def on_browse_done(self, total):
        self.list_widget.addItem(f"── {total} commanders total ──")

        
    def on_fetch_success(self, names):
        self.list_widget.clear()
        if not names:
            self.list_widget.addItem("No commanders found for these coins.")
            return
            
        for name in names:
            self.list_widget.addItem(name)
            
    def on_fetch_error(self, err):
        self.list_widget.clear()
        self.list_widget.addItem(f"Error: {err}")
        
    def on_item_selected(self):
        items = self.list_widget.selectedItems()
        if items and "Error:" not in items[0].text() and "No commanders" not in items[0].text() and "Flipping" not in items[0].text():
            name = items[0].text()
            self.preview_requested.emit(name)
            
            # Enable Dual Buttons
            enabled_style = f"""
                QPushButton {{
                    background-color: {ACCENT_COLOR};
                    color: white;
                    border-radius: 4px;
                    padding: 8px;
                    font-weight: bold;
                }}
            """
            self.btn_send_doctor.setEnabled(True)
            self.btn_send_doctor.setStyleSheet(enabled_style)
            
            self.btn_send_export.setEnabled(True)
            self.btn_send_export.setStyleSheet(enabled_style)
        else:
            self.btn_send_doctor.setEnabled(False)
            self.btn_send_export.setEnabled(False)
            
    def _trigger_hover_fetch(self, name, manager):
        # We bounce this back up to main.py `on_preview_requested` but we pass the manager
        # so main.py knows where to send the image back to.
        # Actually discovery widget doesn't know about main directly due to signals, 
        # so let's just make it emit it.
        # WAIT: Main window's `on_preview_requested` doesn't take a manager arg.
        # Let's just create an internal Image Fetcher thread for DiscoveryWidget Tooltips
        from image_fetcher import ImageFetchThread
        
        # Stop any active thread
        if hasattr(self, 'img_thread') and self.img_thread.isRunning():
            self.img_thread.quit()
            
        self.img_thread = ImageFetchThread(card_name=name)
        self.img_thread.image_ready.connect(manager.display_image)
        self.img_thread.start()
            
    def on_send_doctor_clicked(self):
        items = self.list_widget.selectedItems()
        if items:
            name = items[0].text()
            self.build_requested.emit(name) # Main.py handles this (routes to Doctor)
            
    def on_send_export_clicked(self):
        items = self.list_widget.selectedItems()
        if items:
            name = items[0].text()
            # We need a new signal to tell Main Window to just populate the search bar
            # Currently we only have `build_requested`. Let's add `export_requested`.
            if hasattr(self, 'export_requested'):
                self.export_requested.emit(name)
            
    def show_help(self):
        from PyQt5.QtWidgets import QMessageBox
        QMessageBox.information(self, "Discovery Roll Help", 
            "Don't know what to play? Try the Deck Roller!\n\n"
            "1. Toggle your preferred Magic colors (WUBRG).\n"
            "2. Click 'Toss Coin' to search Scryfall for 5 random commanders matching your colors.\n"
            "3. Double-click to preview the card, or click 'Build This' to auto-import them to the Main deck builder!"
        )
