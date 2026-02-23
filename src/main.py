import sys
import threading
import time
import subprocess
import platform
import copy
from pathlib import Path
from typing import Dict, Any, Callable

from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGroupBox, QRadioButton, QTextEdit, QLineEdit, QPushButton,
    QCheckBox, QLabel, QProgressBar, QFileDialog, QMessageBox,
    QComboBox
)
from PySide6.QtCore import Qt, QThread, Signal, QUrl
from PySide6.QtGui import QDesktopServices
import json
import os

# Ensure the root project directory is in the Python path so `python3 src/main.py` works
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from src.logic import resource_path, gather_cards

# Logic moved to src/logic.py


class GatherWorker(QThread):
    log_msg = Signal(str)
    skipped_msg = Signal(str)
    progress = Signal(float)
    finished = Signal(bool)
    error = Signal(str)

    def __init__(self, save_dir: Path, source: str, raw_paste: str, file_path: str,
                 edhrec_cmd: str, format_pref: str,
                 do_json: bool, do_csv: bool, do_mpc: bool, do_img: bool, do_pdf: bool,
                 pdf_padding: int = 75, draw_guides: bool = False, paper_size: str = "Letter"):
        super().__init__()
        self.save_dir = save_dir
        self.source = source
        self.raw_paste = raw_paste
        self.file_path = file_path
        self.edhrec_cmd = edhrec_cmd
        self.format_pref = format_pref
        self.do_json = do_json
        self.do_csv = do_csv
        self.do_mpc = do_mpc
        self.do_img = do_img
        self.do_pdf = do_pdf
        self.pdf_padding = pdf_padding
        self.draw_guides = draw_guides
        self.paper_size = paper_size

    def run_queue_log(self, msg: str):
        self.log_msg.emit(msg)

    def run_queue_skipped(self, msg: str):
        self.skipped_msg.emit(msg)

    def run_set_progress(self, val: float):
        self.progress.emit(val)

    def run(self):
        try:
            gather_cards(
                self.save_dir, self.source, self.raw_paste, self.file_path,
                self.edhrec_cmd, self.format_pref,
                self.do_json, self.do_csv, self.do_mpc, self.do_img, self.do_pdf,
                self.run_queue_log, self.run_set_progress, self.pdf_padding,
                skip_cb=self.run_queue_skipped, draw_guides=self.draw_guides,
                paper_size=self.paper_size
            )
            self.finished.emit(True)
        except Exception as e:
            self.error.emit(str(e))


class MagicGathererApp(QMainWindow):
    def __init__(self):
        super().__init__()
        import os
        from PySide6.QtGui import QIcon
        self.setWindowTitle("MagicGatherer v2.0.1")
        
        icon_p = resource_path("icon.png")
        if os.path.exists(icon_p):
            self.setWindowIcon(QIcon(icon_p))
            
        self.resize(800, 800)
        self.setAcceptDrops(True)
        
        self.config_path = Path.home() / ".magicgatherer" / "config.json"
        self.central_widget = QWidget()
        self.setCentralWidget(self.central_widget)
        self.layout_main = QVBoxLayout(self.central_widget)

        # ====== SECTION 1: Input Source ======
        self.group_input = QGroupBox("1. Select Input Source")
        self.layout_input = QVBoxLayout()
        
        self.radio_paste = QRadioButton("Paste List")
        self.radio_paste.setChecked(True)
        self.text_paste = QTextEdit()
        self.text_paste.setMaximumHeight(100)
        self.layout_input.addWidget(self.radio_paste)
        self.layout_input.addWidget(self.text_paste)

        self.layout_file = QHBoxLayout()
        self.radio_file = QRadioButton("Local File:")
        self.entry_file = QLineEdit()
        self.entry_file.setEnabled(False)
        self.btn_browse = QPushButton("Browse")
        self.btn_browse.setEnabled(False)
        self.layout_file.addWidget(self.radio_file)
        self.layout_file.addWidget(self.entry_file)
        self.layout_file.addWidget(self.btn_browse)
        self.layout_input.addLayout(self.layout_file)

        self.layout_edhrec = QHBoxLayout()
        self.radio_edhrec = QRadioButton("EDHREC Commander:")
        self.entry_edhrec = QLineEdit()
        self.entry_edhrec.setEnabled(False)
        self.layout_edhrec.addWidget(self.radio_edhrec)
        self.layout_edhrec.addWidget(self.entry_edhrec)
        self.layout_input.addLayout(self.layout_edhrec)

        self.group_input.setLayout(self.layout_input)
        self.layout_main.addWidget(self.group_input)

        # Signals for Radio Toggling
        self.radio_paste.toggled.connect(self.toggle_inputs)
        self.radio_file.toggled.connect(self.toggle_inputs)
        self.radio_edhrec.toggled.connect(self.toggle_inputs)
        self.btn_browse.clicked.connect(self.browse_file)

        # ====== SECTION 2: Format Filter ======
        self.group_format = QGroupBox("2. Select Format")
        self.layout_format = QVBoxLayout()
        self.radio_paper = QRadioButton("Paper (Every exact card)")
        self.radio_paper.setChecked(True)
        self.radio_arena = QRadioButton("Arena Only (Skip non-Arena cards)")
        self.radio_mtgo = QRadioButton("MTGO Only (Skip non-MTGO cards)")

        self.layout_format.addWidget(self.radio_paper)
        self.layout_format.addWidget(self.radio_arena)
        self.layout_format.addWidget(self.radio_mtgo)

        self.group_format.setLayout(self.layout_format)
        self.layout_main.addWidget(self.group_format)

        # ====== SECTION 3: Output Options ======
        self.group_output = QGroupBox("3. Output Options")
        self.layout_output = QVBoxLayout()
        
        self.layout_output_top = QHBoxLayout()
        self.chk_json = QCheckBox("JSON")
        self.chk_json.setChecked(True)
        self.chk_csv = QCheckBox("CSV")
        self.chk_csv.setChecked(True)
        self.chk_mpc = QCheckBox("Decklist Textfile")
        self.chk_mpc.setChecked(True)
        
        self.layout_output_top.addWidget(self.chk_json)
        self.layout_output_top.addWidget(self.chk_csv)
        self.layout_output_top.addWidget(self.chk_mpc)
        self.layout_output.addLayout(self.layout_output_top)
        
        self.layout_output_bot = QHBoxLayout()
        self.chk_img = QCheckBox("High-Res Images")
        self.chk_img.setChecked(True)
        self.chk_pdf = QCheckBox("PDF Print Proxies")
        self.chk_pdf.setChecked(True)
        
        self.chk_guides = QCheckBox("Print Cut Guides")
        self.chk_guides.setChecked(True)
        
        self.group_paper_size = QGroupBox("Paper Size")
        self.layout_paper_size = QHBoxLayout()
        self.combo_paper_size = QComboBox()
        self.combo_paper_size.addItems(["US Letter", "US Legal", "US Tabloid", "A4", "A3", "A2", "A1"])
        self.combo_paper_size.setCurrentText("US Letter")
        self.layout_paper_size.addWidget(self.combo_paper_size)
        self.group_paper_size.setLayout(self.layout_paper_size)
        
        self.chk_open_folder = QCheckBox("Open Output Folder")
        self.chk_open_folder.setChecked(True)
        
        self.combo_pdf_pad = QComboBox()
        self.combo_pdf_pad.addItems(["No Padding (0 px)", "Standard Proxy Padding (75 px)", "Large Padding (150 px)"])
        self.combo_pdf_pad.setCurrentText("Standard Proxy Padding (75 px)")
        self.combo_pdf_pad.setToolTip("Adds mechanical cutting space around each PDF grid proxy.")
        
        self.layout_output_bot.addWidget(self.chk_img)
        self.layout_output_bot.addWidget(self.chk_pdf)
        self.layout_output_bot.addWidget(self.chk_guides)
        self.layout_output_bot.addWidget(self.chk_open_folder)
        self.layout_output_bot.addWidget(self.combo_pdf_pad)
        self.layout_output_bot.addWidget(self.group_paper_size)
        self.layout_output.addLayout(self.layout_output_bot)
        
        self.chk_img.toggled.connect(self.toggle_pdf_options)
        self.chk_pdf.toggled.connect(self.toggle_pdf_options)

        self.group_output.setLayout(self.layout_output)
        self.layout_main.addWidget(self.group_output)

        # ====== SECTION 4: Action Area ======
        self.btn_run = QPushButton("Gather your Magic")
        self.btn_run.setStyleSheet("font-weight: bold; font-size: 14pt; padding: 10px;")
        self.btn_run.clicked.connect(self.start_thread)
        self.layout_main.addWidget(self.btn_run)

        self.progress_bar = QProgressBar()
        self.progress_bar.setValue(0)
        self.progress_bar.setMaximum(100)
        self.layout_main.addWidget(self.progress_bar)

        # ====== SECTION 5: Console Log ======
        self.group_log = QGroupBox("Console Log")
        self.layout_log_main = QHBoxLayout()
        
        self.text_log = QTextEdit()
        self.text_log.setReadOnly(True)
        self.text_log.setPlaceholderText("Execution logs will appear here...")
        self.text_log.setStyleSheet("background-color: black; color: lime;")
        
        self.skipped_area = QTextEdit()
        self.skipped_area.setReadOnly(True)
        self.skipped_area.setPlaceholderText("Any skipped or non-legal cards will appear here...")
        self.skipped_area.setStyleSheet("background-color: #1a0000; color: #ffb3b3;")
        
        self.layout_log_main.addWidget(self.text_log, 2)
        self.layout_log_main.addWidget(self.skipped_area, 1)
        
        self.group_log.setLayout(self.layout_log_main)
        self.layout_main.addWidget(self.group_log)
        
        # Load config if exists
        self.load_config()

        # Branding & Cache Clear
        self.layout_bottom = QHBoxLayout()
        
        self.btn_clear_cache = QPushButton("Clear Cache")
        self.btn_clear_cache.setStyleSheet("font-size: 10px; color: gray;")
        self.btn_clear_cache.setMaximumWidth(80)
        self.btn_clear_cache.clicked.connect(self.clear_cache)
        
        self.btn_launch_tui = QPushButton("Launch TUI")
        self.btn_launch_tui.setStyleSheet("font-size: 10px; color: gray;")
        self.btn_launch_tui.setMaximumWidth(80)
        self.btn_launch_tui.clicked.connect(self.launch_tui)
        
        self.lbl_brand = QLabel("by yuhidev")
        self.lbl_brand.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        self.lbl_brand.setStyleSheet("font-size: 10px;")
        
        self.layout_bottom.addWidget(self.btn_launch_tui)
        self.layout_bottom.addWidget(self.btn_clear_cache)
        self.layout_bottom.addWidget(self.lbl_brand)
        self.layout_main.addLayout(self.layout_bottom)

    def clear_cache(self):
        import shutil
        cache_dir = Path.home() / ".magicgatherer" / "cache"
        if cache_dir.exists():
            try:
                shutil.rmtree(cache_dir)
                QMessageBox.information(self, "Cache Cleared", "Local Scryfall JSON cache has been successfully wiped.")
            except Exception as e:
                QMessageBox.warning(self, "Error", f"Failed to clear cache: {e}")
        else:
            QMessageBox.information(self, "Cache Cleared", "Cache is already empty!")

    def toggle_pdf_options(self):
        show = self.chk_img.isChecked() and self.chk_pdf.isChecked()
        self.group_paper_size.setVisible(show)
        self.combo_pdf_pad.setVisible(show)
        self.chk_guides.setVisible(show)

    def launch_tui(self):
        """ Spawn the TUI in a new terminal and close the GUI """
        env = copy.deepcopy(os.environ)
        env.pop('_MEIPASS2', None)
        
        if getattr(sys, 'frozen', False):
            # Compiled (PyInstaller) mode
            exe = sys.executable
            if platform.system() == "Windows":
                subprocess.Popen(f'start cmd /c "{exe}" --tui', shell=True, env=env)
            elif platform.system() == "Darwin":
                script = f'''
                tell application "Terminal"
                    do script "\\"{exe}\\" --tui"
                    activate
                end tell
                '''
                subprocess.Popen(["osascript", "-e", script], env=env)
            else:
                subprocess.Popen(["x-terminal-emulator", "-e", f'"{exe}" --tui'], env=env)
        else:
            # Development mode
            python = sys.executable
            script_path = __file__
            if platform.system() == "Windows":
                subprocess.Popen(f'start cmd /c "{python}" "{script_path}" --tui', shell=True, env=env)
            elif platform.system() == "Darwin":
                script = f'''
                tell application "Terminal"
                    do script "\\"{python}\\" \\"{script_path}\\" --tui"
                    activate
                end tell
                '''
                subprocess.Popen(["osascript", "-e", script], env=env)
            else:
                subprocess.Popen(["x-terminal-emulator", "-e", f'"{python}" "{script_path}" --tui'], env=env)
            
        self.close()

    def toggle_inputs(self):
        self.text_paste.setEnabled(self.radio_paste.isChecked())
        self.entry_file.setEnabled(self.radio_file.isChecked())
        self.btn_browse.setEnabled(self.radio_file.isChecked())
        self.entry_edhrec.setEnabled(self.radio_edhrec.isChecked())

    def browse_file(self):
        v, _ = QFileDialog.getOpenFileName(self, "Open List", "", "Text Files (*.txt);;All Files (*)")
        if v:
            self.entry_file.setText(str(v))

    def append_log(self, text: str):
        self.text_log.append(text)

    def start_thread(self):
        save_dir_str = QFileDialog.getExistingDirectory(self, "Select Folder to Save Files")
        if not save_dir_str:
            return
            
        save_dir = Path(save_dir_str)
        source = "paste"
        if self.radio_file.isChecked(): source = "file"
        elif self.radio_edhrec.isChecked(): source = "edhrec"
        
        fmt_pref = "paper"
        if self.radio_arena.isChecked(): fmt_pref = "arena"
        elif self.radio_mtgo.isChecked(): fmt_pref = "mtgo"
        
        self.save_config() # Sticky settings
        
        self.btn_run.setEnabled(False)
        self.text_log.clear()
        self.skipped_area.clear()
        
        raw_paper = self.combo_paper_size.currentText()
        if raw_paper == "US Letter": paper_size = "Letter"
        elif raw_paper == "US Legal": paper_size = "Legal"
        elif raw_paper == "US Tabloid": paper_size = "Tabloid"
        else: paper_size = raw_paper  # A4, A3, etc.
        
        # Parse padding string back to int
        pad_text = self.combo_pdf_pad.currentText()
        pad_val = 0
        if "75" in pad_text: pad_val = 75
        elif "150" in pad_text: pad_val = 150
        
        self.worker = GatherWorker(
            save_dir, source, self.text_paste.toPlainText(), self.entry_file.text(),
            self.entry_edhrec.text(), fmt_pref,
            self.chk_json.isChecked(), self.chk_csv.isChecked(), self.chk_mpc.isChecked(),
            self.chk_img.isChecked(), self.chk_pdf.isChecked(),
            pad_val, self.chk_guides.isChecked(), paper_size
        )
        self.worker.log_msg.connect(self.append_log)
        self.worker.skipped_msg.connect(self.skipped_area.append)
        self.worker.progress.connect(self.progress_bar.setValue)
        self.worker.finished.connect(lambda: self.on_finished(save_dir))
        self.worker.error.connect(self.on_error)
        self.worker.start()

    def on_finished(self, save_dir: Path):
        self.btn_run.setEnabled(True)
        if self.chk_open_folder.isChecked():
            QDesktopServices.openUrl(QUrl.fromLocalFile(str(save_dir)))
        QMessageBox.information(self, "Success", "Magic Gathering Complete!")

    def on_error(self, err: str):
        self.btn_run.setEnabled(True)
        QMessageBox.critical(self, "Error", err)

    def load_config(self):
        if not self.config_path.exists():
            return
        try:
            with open(self.config_path, "r") as f:
                c = json.load(f)
                self.chk_json.setChecked(c.get("json", True))
                self.chk_csv.setChecked(c.get("csv", True))
                self.chk_mpc.setChecked(c.get("mpc", True))
                self.chk_img.setChecked(c.get("img", True))
                self.chk_pdf.setChecked(c.get("pdf", True))
                self.chk_guides.setChecked(c.get("guides", True))
                self.chk_open_folder.setChecked(c.get("open_folder", True))
                pad_val = c.get("padding", 75)
                if pad_val == 0: self.combo_pdf_pad.setCurrentText("No Padding (0 px)")
                elif pad_val == 150: self.combo_pdf_pad.setCurrentText("Large Padding (150 px)")
                else: self.combo_pdf_pad.setCurrentText("Standard Proxy Padding (75 px)")
                
                p_size = c.get("paper_size", "Letter")
                if p_size == "Legal": self.combo_paper_size.setCurrentText("US Legal")
                elif p_size == "Tabloid": self.combo_paper_size.setCurrentText("US Tabloid")
                elif p_size in ["A4", "A3", "A2", "A1"]: self.combo_paper_size.setCurrentText(p_size)
                else: self.combo_paper_size.setCurrentText("US Letter")
                
                f_pref = c.get("format", "paper")
                if f_pref == "arena": self.radio_arena.setChecked(True)
                elif f_pref == "mtgo": self.radio_mtgo.setChecked(True)
                else: self.radio_paper.setChecked(True)
                
                self.toggle_pdf_options()
        except Exception:
            pass

    def save_config(self):
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        f_pref = "paper"
        if self.radio_arena.isChecked(): f_pref = "arena"
        elif self.radio_mtgo.isChecked(): f_pref = "mtgo"
        
        pad_text = self.combo_pdf_pad.currentText()
        pad_val = 0
        if "75" in pad_text: pad_val = 75
        elif "150" in pad_text: pad_val = 150

        raw_paper = self.combo_paper_size.currentText()
        if raw_paper == "US Letter": p_size = "Letter"
        elif raw_paper == "US Legal": p_size = "Legal"
        elif raw_paper == "US Tabloid": p_size = "Tabloid"
        else: p_size = raw_paper

        c = {
            "json": self.chk_json.isChecked(),
            "csv": self.chk_csv.isChecked(),
            "mpc": self.chk_mpc.isChecked(),
            "img": self.chk_img.isChecked(),
            "pdf": self.chk_pdf.isChecked(),
            "guides": self.chk_guides.isChecked(),
            "open_folder": self.chk_open_folder.isChecked(),
            "padding": pad_val,
            "format": f_pref,
            "paper_size": p_size
        }
        with open(self.config_path, "w") as f:
            json.dump(c, f)

    # Drag and Drop Configs
    def dragEnterEvent(self, event):
        if event.mimeData().hasUrls() or event.mimeData().hasText():
            event.acceptProposedAction()
    
    def dropEvent(self, event):
        if event.mimeData().hasUrls():
            urls = event.mimeData().urls()
            if urls:
                path = urls[0].toLocalFile()
                if path.endswith(".txt"):
                    self.radio_file.setChecked(True)
                    self.entry_file.setText(path)
        event.acceptProposedAction()

def run_tui():
    import argparse
    parser = argparse.ArgumentParser(description="MagicGatherer Terminal UI")
    parser.add_argument("--tui", action="store_true", help="Launch in TUI Mode")
    parser.add_argument("--source", choices=["paste", "file", "edhrec"], default="edhrec", help="Input source")
    parser.add_argument("--file", type=str, default="", help="Path to deck file")
    parser.add_argument("--edhrec", type=str, default="Krenko, Mob Boss", help="EDHREC Commander Name")
    parser.add_argument("--paste", type=str, default="", help="Raw paste literal")
    parser.add_argument("--format", choices=["paper", "arena", "mtgo"], default="paper", help="Format filter")
    parser.add_argument("--no-json", action="store_true", help="Disable JSON export")
    parser.add_argument("--no-csv", action="store_true", help="Disable CSV export")
    parser.add_argument("--no-mpc", action="store_true", help="Disable Decklist textfile export")
    parser.add_argument("--no-img", action="store_true", help="Disable high-res image download")
    parser.add_argument("--no-pdf", action="store_true", help="Disable 9-card proxy PDF generation")
    parser.add_argument("--no-guides", action="store_true", help="Disable PDF cutting guide marks")
    parser.add_argument("--pdf-padding", type=int, default=75, help="PDF proxy border cutting space in pixels (Default: 75 px)")
    parser.add_argument("--paper-size", choices=["Letter", "Legal", "Tabloid", "A4", "A3", "A2", "A1"], default="Letter", help="Paper size for proxy PDF")
    parser.add_argument("--outdir", type=str, default=".", help="Output directory path")
    args = parser.parse_args()

    # Validate
    if args.source == "edhrec" and not args.edhrec:
        print("Error: --edhrec requires a commander name.")
        sys.exit(1)
    if args.source == "file" and not args.file:
        print("Error: --file requires a file path.")
        sys.exit(1)
    if args.source == "paste" and not args.paste:
        print("Error: --paste requires a pasted string.")
        sys.exit(1)

    save_dir = Path(args.outdir).resolve()
    
    from rich.console import Console
    from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn
    from rich.panel import Panel

    console = Console()
    console.print(Panel.fit("[bold magenta]MagicGatherer v2.0.1[/bold magenta] [cyan]TUI Edition[/cyan]", border_style="green"))

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        BarColumn(),
        TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
        console=console
    ) as progress:
        task1 = progress.add_task("[cyan]Gathering Magic...", total=100)

        def log_cb(msg):
            progress.console.print(f"[dim]{msg}[/dim]")
        def prog_cb(val):
            progress.update(task1, completed=val)

        try:
            gather_cards(
                save_dir, args.source, args.paste, args.file,
                args.edhrec, args.format,
                not args.no_json, not args.no_csv, not args.no_mpc, not args.no_img, not args.no_pdf,
                log_cb, prog_cb, args.pdf_padding,
                skip_cb=lambda m: log_cb(f"Skipped: {m}"),
                draw_guides=not args.no_guides,
                paper_size=args.paper_size
            )
            progress.update(task1, completed=100, description="[bold green]Finished![/bold green]")
        except Exception as e:
            progress.console.print(f"[bold red]Error:[/bold red] {e}")
            sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) == 2 and "--tui" in sys.argv:
        try:
            from src.tui.app import MagicGathererTUI
            app_tui = MagicGathererTUI()
            app_tui.run()
        except ImportError:
            run_tui()
    elif "--tui" in sys.argv or "-h" in sys.argv or "--help" in sys.argv:
        run_tui()
    else:
        app = QApplication(sys.argv)
        window = MagicGathererApp()
        window.show()
        sys.exit(app.exec())
