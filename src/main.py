import sys
import threading
import time
from pathlib import Path
from typing import Dict, Any, Callable

from PySide6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QGroupBox, QRadioButton, QTextEdit, QLineEdit, QPushButton,
    QCheckBox, QLabel, QProgressBar, QFileDialog, QMessageBox,
    QSpinBox
)
from PySide6.QtCore import Qt, QThread, Signal

# Adjust path so we can import modules when running main.py directly
sys.path.append(str(Path(__file__).resolve().parent.parent))

from src.utils.parsers import parse_raw_lines, sanitize_filename
from src.api.edhrec import fetch_edhrec_deck
from src.api.scryfall import fetch_scryfall_paper, fetch_scryfall_digital
from src.utils.exporters import export_json, export_csv, export_mpc, export_images, export_pdf

def resource_path(relative_path: str) -> str:
    """ Get absolute path to resource, works for dev and for PyInstaller wrapper """
    import sys
    import os
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath(os.path.dirname(os.path.dirname(__file__))), relative_path)

def gather_cards(save_dir: Path, source: str, raw_paste: str, file_path: str,
                 edhrec_cmd: str, format_pref: str,
                 do_json: bool, do_csv: bool, do_mpc: bool, do_img: bool, do_pdf: bool,
                 log_cb: Callable[[str], None], progress_cb: Callable[[float], None],
                 pdf_padding: int = 75) -> None:
    deck_dict: Dict[str, Dict[str, Any]] = {}
    output_prefix = "deck"

    if source == "paste":
        raw = raw_paste.strip()
        if not raw:
            raise ValueError("Paste area is empty!")
        deck_dict = parse_raw_lines(raw.split('\n'))
        output_prefix = "pasted_deck"
    elif source == "file":
        fp = file_path.strip()
        p = Path(fp)
        if not p.exists():
            raise ValueError("File not found!")
        with open(p, 'r', encoding='utf-8') as f:
            deck_dict = parse_raw_lines(f.readlines())
        output_prefix = p.stem
    elif source == "edhrec":
        cmd = edhrec_cmd.strip()
        if not cmd:
            raise ValueError("Commander name is empty!")
        log_cb(f"Fetching EDHREC data for {cmd}...")
        output_prefix = fetch_edhrec_deck(cmd, deck_dict)

    if not deck_dict:
        raise ValueError("No cards found to process.")
    log_cb(f"Found {len(deck_dict)} unique cards. Fetching from Scryfall...")

    progress_cb(10.0)

    if format_pref == "paper":
        all_data = fetch_scryfall_paper(deck_dict)
    else:
        def _filter_cb(msg): log_cb(msg)
        all_data = fetch_scryfall_digital(deck_dict, _filter_cb, format_pref)

    progress_cb(50.0)
    log_cb(f"Successfully processed {len(all_data)} cards.")

    safe_pref = sanitize_filename(output_prefix)
    save_dir.mkdir(parents=True, exist_ok=True)

    if do_json:
        export_json(all_data, save_dir, safe_pref)
        log_cb(f"Saved JSON: {save_dir / f'{safe_pref}.json'}")

    if do_csv:
        export_csv(all_data, save_dir, safe_pref)
        log_cb(f"Saved CSV: {save_dir / f'{safe_pref}.csv'}")

    if do_mpc:
        export_mpc(all_data, save_dir, safe_pref)
        log_cb(f"Saved Decklist Textfile: {save_dir / f'{safe_pref}_decklist.txt'}")

    if do_img:
        export_images(all_data, save_dir, safe_pref, log_cb, progress_cb, start_prog=50.0, end_prog=90.0)
        if do_pdf:
            export_pdf(all_data, save_dir, safe_pref, log_cb, padding_px=pdf_padding)
            progress_cb(100.0)
        else:
            progress_cb(100.0)
    else:
        progress_cb(100.0)

    log_cb("=== ALL TASKS FINISHED SUCCESSFULLY ===")


class GatherWorker(QThread):
    log_msg = Signal(str)
    progress = Signal(float)
    finished = Signal(bool)
    error = Signal(str)

    def __init__(self, save_dir: Path, source: str, raw_paste: str, file_path: str,
                 edhrec_cmd: str, format_pref: str,
                 do_json: bool, do_csv: bool, do_mpc: bool, do_img: bool, do_pdf: bool,
                 pdf_padding: int = 75):
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

    def run_queue_log(self, msg: str):
        self.log_msg.emit(msg)

    def run_set_progress(self, val: float):
        self.progress.emit(val)

    def run(self):
        try:
            gather_cards(
                self.save_dir, self.source, self.raw_paste, self.file_path,
                self.edhrec_cmd, self.format_pref,
                self.do_json, self.do_csv, self.do_mpc, self.do_img, self.do_pdf,
                self.run_queue_log, self.run_set_progress, self.pdf_padding
            )
            self.finished.emit(True)
        except Exception as e:
            self.error.emit(str(e))


class MagicGathererApp(QMainWindow):
    def __init__(self):
        super().__init__()
        import os
        from PySide6.QtGui import QIcon
        self.setWindowTitle("MagicGatherer")
        
        icon_p = resource_path("icon.png")
        if os.path.exists(icon_p):
            self.setWindowIcon(QIcon(icon_p))
            
        self.resize(650, 750)
        self.setAcceptDrops(True)

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
        
        self.spin_pdf_pad = QSpinBox()
        self.spin_pdf_pad.setRange(0, 300)
        self.spin_pdf_pad.setValue(75)
        self.spin_pdf_pad.setSuffix(" px padding")
        self.spin_pdf_pad.setToolTip("Adds mechanical cutting space around each PDF grid proxy.")
        
        self.layout_output_bot.addWidget(self.chk_img)
        self.layout_output_bot.addWidget(self.chk_pdf)
        self.layout_output_bot.addWidget(self.spin_pdf_pad)
        self.layout_output.addLayout(self.layout_output_bot)
        
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
        self.group_log = QGroupBox("Log Output")
        self.layout_log = QVBoxLayout()
        self.text_log = QTextEdit()
        self.text_log.setReadOnly(True)
        self.text_log.setStyleSheet("background-color: black; color: lime;")
        self.layout_log.addWidget(self.text_log)
        self.group_log.setLayout(self.layout_log)
        self.layout_main.addWidget(self.group_log)

        # Branding & Cache Clear
        self.layout_bottom = QHBoxLayout()
        
        self.btn_clear_cache = QPushButton("Clear Cache")
        self.btn_clear_cache.setStyleSheet("font-size: 10px; color: gray;")
        self.btn_clear_cache.setMaximumWidth(80)
        self.btn_clear_cache.clicked.connect(self.clear_cache)
        
        self.lbl_brand = QLabel("by yuhidev")
        self.lbl_brand.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
        self.lbl_brand.setStyleSheet("font-size: 10px;")
        
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
        self.btn_run.setEnabled(False)
        self.btn_run.setText("GATHERING...")
        self.progress_bar.setValue(0)
        self.text_log.clear()

        # Gather state
        source = "paste"
        if self.radio_file.isChecked(): source = "file"
        elif self.radio_edhrec.isChecked(): source = "edhrec"

        fmt = "paper"
        if self.radio_arena.isChecked(): fmt = "arena"
        elif self.radio_mtgo.isChecked(): fmt = "mtgo"

        self.worker = GatherWorker(
            save_dir, source, self.text_paste.toPlainText(), self.entry_file.text(),
            self.entry_edhrec.text(), fmt,
            self.chk_json.isChecked(), self.chk_csv.isChecked(),
            self.chk_mpc.isChecked(), self.chk_img.isChecked(), self.chk_pdf.isChecked(),
            self.spin_pdf_pad.value()
        )

        self.worker.log_msg.connect(self.append_log)
        self.worker.progress.connect(lambda v: self.progress_bar.setValue(int(v)))
        self.worker.finished.connect(self.on_worker_finished)
        self.worker.error.connect(self.on_worker_error)
        
        self.worker.start()

    def on_worker_finished(self, success: bool):
        self.btn_run.setEnabled(True)
        self.btn_run.setText("Gather your Magic")
        QMessageBox.information(self, "Done", "MagicGatherer has finished compiling your files!")

    def on_worker_error(self, error_str: str):
        self.append_log(f"ERROR: {error_str}")
        self.btn_run.setEnabled(True)
        self.btn_run.setText("Gather your Magic")
        QMessageBox.critical(self, "Error", f"An error occurred:\n{error_str}")

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
    parser.add_argument("--pdf-padding", type=int, default=75, help="PDF proxy border cutting space in pixels (Default: 75 px)")
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
    console.print(Panel.fit("[bold magenta]MagicGatherer[/bold magenta] [cyan]TUI Edition[/cyan]", border_style="green"))

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
                log_cb, prog_cb, args.pdf_padding
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
