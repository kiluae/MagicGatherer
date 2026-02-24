import re
from PyQt5.QtWidgets import (QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, QLabel, 
                             QProgressBar, QTextEdit, QPushButton, QListView, QSpinBox, QLineEdit, QCompleter)
from PyQt5.QtCore import pyqtSignal, Qt, QThread
from PyQt5.QtGui import QStandardItemModel, QStandardItem
from ui_core import StyledPane, HeaderLabel, PANE_BG, FuzzyProxyModel, ACCENT_COLOR
from api import safe_post

def heuristic_categorize(card):
    type_line = card.get("type_line", "").lower()
    oracle_text = card.get("oracle_text", "").lower()
    cats = []
    
    if "land" in type_line: 
        cats.append("Lands")
    if "creature" in type_line: 
        cats.append("Creatures")
        
    # Ramp Heuristics
    is_mana_rock = "add " in oracle_text and ("mana" in oracle_text or "{" in oracle_text)
    is_land_fetch = "search your library for a basic land" in oracle_text or "search your library for a land" in oracle_text
    if is_mana_rock or is_land_fetch:
        cats.append("Ramp")
        
    # Draw Heuristics
    if "draw " in oracle_text and ("card" in oracle_text or "cards" in oracle_text):
        cats.append("Draw")
        
    # Interaction Heuristics
    if "destroy" in oracle_text or "exile" in oracle_text or "counter target" in oracle_text or "deals damage to any target" in oracle_text:
        cats.append("Interaction")
        
    return cats

class ClickableProgressBar(QProgressBar):
    clicked = pyqtSignal()
    def mousePressEvent(self, event):
        self.clicked.emit()
        super().mousePressEvent(event)

class DeckDoctorDashboard(StyledPane):
    gap_filler_requested = pyqtSignal(str) 
    
    def __init__(self):
        super().__init__()
        layout = QVBoxLayout(self)
        layout.setContentsMargins(16, 16, 16, 16)
        layout.setSpacing(12)
        
        layout.addWidget(HeaderLabel("Diagnostics & Curve"))
        
        self.metrics = {
            "Lands": {"current": 0, "target": 36, "bar": None, "query": "t:land"},
            "Creatures": {"current": 0, "target": 25, "bar": None, "query": "t:creature"},
            "Ramp": {"current": 0, "target": 10, "bar": None, "query": "(oracle:\"add mana\" OR oracle:\"search your library\")"},
            "Draw": {"current": 0, "target": 10, "bar": None, "query": "oracle:\"draw a card\""},
            "Interaction": {"current": 0, "target": 10, "bar": None, "query": "(oracle:destroy OR oracle:exile OR oracle:counter)"}
        }
        
        self.commander_identity = []
        
        for cat, data in self.metrics.items():
            row = QHBoxLayout()
            label = QLabel(f"{cat}:")
            label.setStyleSheet("color: rgba(255, 255, 255, 178); font-size: 13px;")
            label.setFixedWidth(80)
            
            spin_target = QSpinBox()
            spin_target.setRange(0, 99)
            spin_target.setValue(data['target'])
            spin_target.setStyleSheet("background-color: #2C2C2C; color: white; border: 1px solid #444;")
            spin_target.setFixedWidth(50)
            spin_target.valueChanged.connect(lambda val, c=cat: self.on_target_changed(c, val))
            
            bar = ClickableProgressBar()
            bar.setFixedHeight(12)
            bar.setTextVisible(False)
            bar.setRange(0, data['target'])
            bar.setValue(0)
            bar.clicked.connect(lambda c=cat: self.on_bar_clicked(c))
            
            self.metrics[cat]["bar"] = bar
            self.metrics[cat]["spin"] = spin_target
            
            val_label = QLabel("0")
            val_label.setStyleSheet("color: white; font-weight: bold; font-size: 12px;")
            val_label.setFixedWidth(30)
            self.metrics[cat]["val_label"] = val_label
            
            row.addWidget(label)
            row.addWidget(spin_target)
            row.addWidget(bar, stretch=1)
            row.addWidget(val_label)
            layout.addLayout(row)
            
        self.status_label = QLabel("Waiting for a decklist or commander...")
        self.status_label.setStyleSheet("color: gray;")
        self.status_label.setWordWrap(True)
        layout.addWidget(self.status_label)
        self.update_bars()
        
    def on_target_changed(self, category, new_val):
        self.metrics[category]["target"] = new_val
        self.metrics[category]["bar"].setRange(0, max(new_val, 1))
        self.update_bars()
        
    def set_commander(self, card_data):
        self.status_label.setText(f"Analyzing {card_data.get('name')} skeleton...")
        self.commander_identity = card_data.get("color_identity", [])
        self.reset_metrics()
        
    def reset_metrics(self):
        for cat in self.metrics:
            self.metrics[cat]["current"] = 0
        self.update_bars()
        
    def add_card(self, card_data):
        cats = heuristic_categorize(card_data)
        for cat in cats:
            if cat in self.metrics:
                self.metrics[cat]["current"] += 1
        self.update_bars()

    def update_bars(self):
        for cat, data in self.metrics.items():
            current = data["current"]
            target = data["target"]
            bar = data["bar"]
            
            bar.setValue(min(current, target))
            data["val_label"].setText(str(current))
            
            if current < target:
                color = "#FF3B30" 
            else:
                color = "#A3C095" 
                
            bar.setStyleSheet(f"""
                QProgressBar {{
                    background-color: #2C2C2C;
                    border-radius: 4px;
                    border: none;
                }}
                QProgressBar::chunk {{
                    background-color: {color};
                    border-radius: 4px;
                }}
            """)
            
    def on_bar_clicked(self, category):
        data = self.metrics[category]
        if data["current"] < data["target"]:
            query = data["query"]
            if self.commander_identity:
                colors = "".join(self.commander_identity)
                query += f" id<={colors}"
            self.status_label.setText(f"Filling gap: {query}")
            self.gap_filler_requested.emit(query)

class DeckAnalysisThread(QThread):
    cards_fetched = pyqtSignal(list, str)
    error_occurred = pyqtSignal(str)
    
    def __init__(self, raw_text):
        super().__init__()
        self.raw_text = raw_text
        
    def run(self):
        try:
            lines = self.raw_text.strip().split('\n')
            parsed_names = []
            
            commander_candidates = []
            in_commander_zone = False
            
            for line in lines:
                line = line.strip()
                if not line: 
                    in_commander_zone = False
                    continue
                    
                line_lower = line.lower()
                if line_lower == "commander" or line_lower.startswith("about") or line_lower.startswith("deck"):
                    if line_lower == "commander" or line_lower.startswith("about"):
                        in_commander_zone = True
                    continue
                    
                match = re.match(r'^(?:[0-9]+x?\s+)?([^\(]+)', line)
                if match:
                    name = match.group(1).strip()
                    # Skip common decklist header false positives
                    if name.lower() not in ["name", "deck", "commander", "about"]:
                        parsed_names.append(name)
                        if in_commander_zone:
                            commander_candidates.append(name)
                        
            # Heuristic 2: explicit text "X is the commander"
            import re as regex
            for line in lines:
                if "is the commander" in line.lower() or "commander is" in line.lower():
                    # Attempt to extract name before "is the commander"
                    m = regex.search(r'([A-Za-z\,\s\']+)\s+is the commander', line, regex.IGNORECASE)
                    if m:
                        candidate = m.group(1).strip()
                        if candidate:
                            commander_candidates.insert(0, candidate)
                            
            # Heuristic 3: Check bottom of list for trailing "1 Commander Name" if no explicit zone
            if not commander_candidates and len(parsed_names) > 0:
                parts = self.raw_text.strip().split('\n\n')
                if len(parts) > 1:
                    last_chunk = parts[-1].strip().split('\n')
                    if len(last_chunk) == 1:
                         match = re.match(r'^(?:[0-9]+x?\s+)?([^\(]+)', last_chunk[0])
                         if match:
                             candidate = match.group(1).strip()
                             # Verify it's not conversational text by checking if it looks like a card 
                             # (usually has a quantity or is concise)
                             if len(candidate.split()) <= 5: 
                                 commander_candidates.append(candidate)
                                 if candidate not in parsed_names:
                                     parsed_names.append(candidate) # Add to parsed if it was standalone
                                     
            # Heuristic 4: If all else fails, the first card in the list is almost always the commander.
            if not commander_candidates and parsed_names:
                commander_candidates.append(parsed_names[0])
                    
            if not parsed_names:
                self.cards_fetched.emit([], "")
                return
                
            all_cards = []
            chunk_size = 75
            for i in range(0, len(parsed_names), chunk_size):
                chunk = parsed_names[i:i+chunk_size]
                payload = {"identifiers": [{"name": name} for name in chunk]}
                resp = safe_post("https://api.scryfall.com/cards/collection", json=payload)
                resp.raise_for_status()
                data = resp.json()
                all_cards.extend(data.get("data", []))
                
            detected_commander = commander_candidates[0] if commander_candidates else ""
            self.cards_fetched.emit(all_cards, detected_commander)
        except Exception as e:
            self.error_occurred.emit(str(e))

from api import safe_get

class EdhrecComparisonThread(QThread):
    ready = pyqtSignal(list, list) # adds, cuts
    error_occurred = pyqtSignal(str)
    
    def __init__(self, commander_name, deck_names):
        super().__init__()
        self.commander = commander_name
        self.deck_names = set([n.lower() for n in deck_names])
        
    def run(self):
        try:
            if not self.commander.strip():
                self.ready.emit([], [])
                return
                
            cmd_slug = self.commander.lower().replace(" ", "-").replace("'", "").replace(",", "")
            r = safe_get(f"https://json.edhrec.com/pages/commanders/{cmd_slug}.json")
            if r.status_code != 200:
                self.error_occurred.emit(f"EDHREC not found for {cmd_slug}")
                return
                
            data = r.json()
            cardlists = data.get("container", {}).get("json_dict", {}).get("cardlists", [])
            
            staples = []
            for lst in cardlists:
                if lst.get("header") in ["High Synergy Cards", "Top Cards", "New Cards", "Game Changers"]:
                    staples.extend([c.get("name") for c in lst.get("cardviews", [])])
            
            staples = list(set([s for s in staples if s]))
            
            adds = []
            for st in staples:
                if st.lower() not in self.deck_names and "Land" not in st:
                    adds.append(st)
                    
            cuts = []
            for d in self.deck_names:
                if d not in [s.lower() for s in staples] and "basic" not in d.lower():
                    cuts.append(d.title())
                    
            self.ready.emit(adds[:50], cuts)
        except Exception as e:
            self.error_occurred.emit(str(e))


class DeckDoctorWindow(QMainWindow):
    send_to_exporter = pyqtSignal(str)

    def __init__(self, initial_decklist="", commanders_model=None):
        super().__init__()
        self.setWindowTitle("MagicGatherer - Deck Doctor 🩺")
        self.resize(1200, 800)
        self.setStyleSheet("background-color: #121212;")
        
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        layout = QHBoxLayout(main_widget)
        layout.setContentsMargins(24, 24, 24, 24)
        layout.setSpacing(16)
        
        # Left Panel (Input)
        left_panel = StyledPane()
        left_layout = QVBoxLayout(left_panel)
        
        header_row = QHBoxLayout()
        header_row.addWidget(HeaderLabel("1. Import Decklist"))
        
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
        self.btn_help.clicked.connect(self.show_help_recommendations)
        header_row.addWidget(self.btn_help)
        header_row.addStretch()
        left_layout.addLayout(header_row)
        
        self.cmd_input = QLineEdit()
        self.cmd_input.setPlaceholderText("Optional: Commander Name for EDHREC comparisons...")
        self.cmd_input.setStyleSheet(f"""
            QLineEdit {{
                background-color: {PANE_BG};
                color: rgba(255, 255, 255, 255);
                border: 1px solid #2C2C2C;
                border-radius: 6px;
                padding: 10px;
                font-weight: bold;
            }}
        """)
        
        if commanders_model:
            self.source_model = commanders_model
        else:
            self.source_model = QStandardItemModel()
        
        
        self.proxy_model = FuzzyProxyModel()
        self.proxy_model.setSourceModel(self.source_model)
        self.completer = QCompleter(self.proxy_model, self)
        self.completer.setCompletionMode(QCompleter.PopupCompletion)
        self.completer.setCaseSensitivity(Qt.CaseInsensitive)
        
        popup = QListView()
        popup.setStyleSheet(f"QListView {{ background-color: {PANE_BG}; color: white; border: 1px solid #2C2C2C; selection-background-color: #4C4C4C; padding: 4px; }}")
        self.completer.setPopup(popup)
        self.cmd_input.setCompleter(self.completer)
        self.cmd_input.textChanged.connect(self.proxy_model.setFilterRegExp)
        
        input_row = QHBoxLayout()
        input_row.addWidget(self.cmd_input, stretch=1)
        
        self.btn_search = QPushButton("Search Staples")
        self.btn_search.setStyleSheet(f"""
            QPushButton {{
                background-color: #5d2785;
                color: white;
                border: 1px solid #2C2C2C;
                border-radius: 6px;
                padding: 10px 16px;
                font-weight: bold;
            }}
            QPushButton:pressed {{
                background-color: #3b1854;
            }}
        """)
        self.btn_search.clicked.connect(self.request_analysis)
        input_row.addWidget(self.btn_search)
        
        left_layout.addLayout(input_row)
        self.paste_area = QTextEdit()
        self.paste_area.setPlaceholderText("Paste your decklist here (Paper, Arena, or MTGO)...")
        self.paste_area.setText(initial_decklist)
        self.paste_area.setStyleSheet("""
            QTextEdit {
                background-color: #121212;
                color: rgba(255, 255, 255, 178);
                border: 1px solid #2C2C2C;
                border-radius: 6px;
                padding: 10px;
                font-family: monospace;
            }
        """)
        left_layout.addWidget(self.paste_area, stretch=1)
        
        self.btn_analyze = QPushButton("Analyze Deck")
        self.btn_analyze.setStyleSheet("""
            QPushButton {
                background-color: #5d2785;
                color: white;
                border-radius: 4px;
                padding: 12px;
                font-weight: bold;
                font-size: 14px;
            }
            QPushButton:pressed {
                background-color: #3b1854;
            }
        """)
        self.btn_analyze.clicked.connect(self.request_analysis)
        left_layout.addWidget(self.btn_analyze)
        
        self.btn_send_main = QPushButton("Send back to Exporter")
        self.btn_send_main.setStyleSheet("""
            QPushButton {
                background-color: #007AFF;
                color: white;
                border-radius: 4px;
                padding: 12px;
                font-weight: bold;
                font-size: 14px;
            }
            QPushButton:pressed {
                background-color: #0056b3;
            }
        """)
        self.btn_send_main.clicked.connect(lambda: self.send_to_exporter.emit(self.paste_area.toPlainText()))
        left_layout.addWidget(self.btn_send_main)
        
        # Center Panel (Metrics)
        self.dashboard = DeckDoctorDashboard()
        
        # Right Panel (Recommendations)
        right_panel = StyledPane()
        right_layout = QVBoxLayout(right_panel)
        
        from PyQt5.QtCore import QStringListModel
        
        right_layout.addWidget(HeaderLabel("Recommended Additions (EDHREC Staples)"))
        self.list_add = QListView()
        self.list_add.setStyleSheet("background-color: #121212; color: #A3C095; border: 1px solid #2C2C2C; padding: 5px;")
        self.model_add = QStringListModel()
        self.list_add.setModel(self.model_add)
        self.list_add.doubleClicked.connect(self.on_recommendation_double_clicked)
        right_layout.addWidget(self.list_add, stretch=1)
        
        right_layout.addWidget(HeaderLabel("Potential Cuts (Non-Synergistic)"))
        self.list_cuts = QListView()
        self.list_cuts.setStyleSheet("background-color: #121212; color: #FF3B30; border: 1px solid #2C2C2C; padding: 5px;")
        self.model_cuts = QStringListModel()
        self.list_cuts.setModel(self.model_cuts)
        self.list_cuts.doubleClicked.connect(self.on_cut_double_clicked)
        right_layout.addWidget(self.list_cuts, stretch=1)
        
        layout.addWidget(left_panel, stretch=1)
        layout.addWidget(self.dashboard, stretch=1)
        layout.addWidget(right_panel, stretch=1)
        
    def request_analysis(self):
        text = self.paste_area.toPlainText()
        cmd_name = self.cmd_input.text().strip()
        if not text.strip() and not cmd_name:
            return
            
        self.dashboard.status_label.setText("Fetching data...")
        self.dashboard.reset_metrics()
        
        if text.strip():
            self.analysis_thread = DeckAnalysisThread(text)
            self.analysis_thread.cards_fetched.connect(self.on_deck_analyzed)
            self.analysis_thread.error_occurred.connect(lambda err: self.dashboard.status_label.setText(f"Error: {err}"))
            self.analysis_thread.start()
        else:
            self.on_deck_analyzed([], None)
        
    def on_deck_analyzed(self, cards, detected_commander):
        for card in cards:
            self.dashboard.add_card(card)
        
        if detected_commander and not self.cmd_input.text().strip():
            self.cmd_input.setText(detected_commander)
            
        self.dashboard.status_label.setText(f"Analysis Complete! Processed {len(cards)} unique cards.")
        
        cmd_name = self.cmd_input.text().strip()
        if cmd_name:
            self.dashboard.status_label.setText(f"Comparing deck to EDHREC for {cmd_name}...")
            deck_names = [c.get("name") for c in cards]
            self.edhrec_thread = EdhrecComparisonThread(cmd_name, deck_names)
            self.edhrec_thread.ready.connect(self.on_recommendations_computed)
            self.edhrec_thread.error_occurred.connect(lambda e: self.dashboard.status_label.setText(f"EDHREC Error: {e}"))
            self.edhrec_thread.start()
            
    def on_recommendations_computed(self, adds, cuts):
        self.dashboard.status_label.setText("EDHREC Comparison Complete! Double-click a recommendation to search it.")
        self.model_add.setStringList(adds)
        self.model_cuts.setStringList(cuts)

    def on_recommendation_double_clicked(self, index):
        card_name = self.model_add.data(index, Qt.DisplayRole)
        if card_name:
            # Append to text area
            current_text = self.paste_area.toPlainText()
            self.paste_area.setText(f"{current_text}\n1 {card_name}".strip())
            
            # Remove from UI list
            self.model_add.removeRow(index.row())
            
            self.dashboard.status_label.setText(f"Appended {card_name} to decklist!")
            self.dashboard.gap_filler_requested.emit(f'"{card_name}"')

    def show_help_recommendations(self):
        from PyQt5.QtWidgets import QMessageBox
        QMessageBox.information(self, "Deck Doctor Help", 
            "1. Paste your decklist (Paper, MTGO, Arena formats supported) into the text box.\n"
            "2. Ensure your Commander is filled in the search bar above.\n"
            "3. Click 'Analyze Deck'.\n\n"
            "The app will calculate your Mana Curve and then ping EDHREC to compare your decklist.\n"
            "It will suggest 'Additions' (Staples you are missing) and flag 'Cuts' (Cards nobody else plays)."
        )

    def on_cut_double_clicked(self, index):
        card_name = self.model_cuts.data(index, Qt.DisplayRole)
        if card_name:
            current_text = self.paste_area.toPlainText()
            import re
            # Regex to find and remove the whole line that contains the card name
            # Accounts for "1x Card Name" or "1 Card Name"
            new_text = re.sub(rf"^(?:[0-9]+x?\s+)?{re.escape(card_name)}$", "", current_text, flags=re.MULTILINE|re.IGNORECASE)
            
            # Clean up empty newlines
            new_text = "\n".join([line for line in new_text.splitlines() if line.strip()])
            
            self.paste_area.setText(new_text)
            self.model_cuts.removeRow(index.row())
            self.dashboard.status_label.setText(f"Trimmed {card_name} from decklist!")
