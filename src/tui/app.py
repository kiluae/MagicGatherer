from pathlib import Path
import os
from typing import Optional
from textual.app import App, ComposeResult
from textual.containers import Grid, Horizontal, Vertical
from textual.widgets import Header, Footer, Input, RadioSet, RadioButton, Checkbox, Button, Log, Static, Select
from textual import work
import sys

# Ensure the root project directory is in the Python path so `python3 src/tui/app.py` works
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(os.path.dirname(current_dir))
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

# We need to import gather_cards safely from src.logic
from src.logic import gather_cards

class MagicGathererTUI(App):
    """A Textual Dashboard for MagicGatherer"""

    CSS = """
    Screen {
        background: $surface;
    }
    
    .panel {
        border: solid green;
        padding: 1;
        margin: 1;
        height: auto;
    }
    
    #main_grid {
        layout: grid;
        grid-size: 2;
        grid-columns: 1fr 1fr;
        grid-rows: 1fr;
        height: 1fr;
    }

    #left_pane {
        width: 100%;
        height: 100%;
    }
    
    #right_pane {
        width: 100%;
        height: 100%;
    }
    
    #config_scroll {
        height: auto;
        max-height: 12;
    }

    Button {
        width: 100%;
        margin-top: 1;
    }
    
    Log {
        border: solid magenta;
        height: 100%;
        min-height: 10;
        margin-top: 1;
    }
    
    #exit_label {
        height: 3;
        content-align: center middle;
        text-style: bold;
        background: $primary;
        color: white;
    }
    """

    BINDINGS = [
        ("d", "toggle_dark", "Toggle dark mode"),
        ("q", "quit", "Quit")
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Static("[bold gray]Press (q) or (Ctrl+C) to exit the TUI and relaunch MagicGatherer to return to Desktop Mode.[/bold gray]", classes="panel", id="exit_label")
        
        with Grid(id="main_grid"):
            # LEFT PANE: Inputs and Radios
            with Vertical(id="left_pane", classes="panel"):
                yield Static("[bold cyan]1. Input Selection[/bold cyan]")
                yield RadioSet(
                    RadioButton("EDHREC Commander", id="src_edhrec", value=True),
                    RadioButton("Local Decklist File", id="src_file"),
                    RadioButton("Raw Text Paste", id="src_paste"),
                    id="source_radios"
                )
                yield Input(placeholder="e.g. Krenko, Mob Boss", id="input_data", name="input_data")
                
                yield Static("\n[bold cyan]2. Formatting Legality[/bold cyan]")
                yield RadioSet(
                    RadioButton("Paper / Tabletop (No Restrictions)", id="fmt_paper", value=True),
                    RadioButton("MTG Arena (Strict Filter)", id="fmt_arena"),
                    RadioButton("MTG Online (MTGO Only)", id="fmt_mtgo"),
                    id="format_radios"
                )
            
            # RIGHT PANE: Outputs and Log
            with Vertical(id="right_pane", classes="panel"):
                yield Static("[bold cyan]3. Output Options[/bold cyan]")
                with Vertical(id="config_scroll"):
                    with Horizontal():
                        with Vertical():
                            yield Checkbox("JSON", id="chk_json", value=True)
                            yield Checkbox("CSV", id="chk_csv", value=True)
                            yield Checkbox("Decklist", id="chk_mpc", value=True)
                        with Vertical():
                            yield Checkbox("High-Res", id="chk_img", value=True)
                            yield Checkbox("PDF Proxy", id="chk_pdf", value=True)
                            yield Checkbox("Crop Marks", id="chk_guides", value=True)
                            yield Checkbox("Open Folder", id="chk_open_folder", value=True)
                            yield Select(
                                [
                                    ("US Letter", "Letter"),
                                    ("US Legal", "Legal"),
                                    ("US Tabloid", "Tabloid"),
                                    ("A4", "A4"),
                                    ("A3", "A3"),
                                    ("A2", "A2"),
                                    ("A1", "A1")
                                ],
                                prompt="Paper Size",
                                id="sel_paper",
                                value="Letter"
                            )
                            yield Select(
                                [("No Padding (0 px)", "0"), ("Standard Proxy Padding (75 px)", "75"), ("Large Padding (150 px)", "150")],
                                prompt="PDF Padding",
                                id="sel_padding",
                                value="75"
                            )
                
                yield Input(placeholder="./ (Output Dir)", id="outdir_input", value=".")
                yield Button("Gather your Magic", id="btn_gather", variant="success")
                yield Log(id="gather_log", highlight=True)

        yield Footer()

    def toggle_pdf_options(self) -> None:
        try:
            img_chk = self.query_one("#chk_img", Checkbox)
            pdf_chk = self.query_one("#chk_pdf", Checkbox)
            show = img_chk.value and pdf_chk.value
            
            self.query_one("#sel_paper", Select).display = show
            self.query_one("#sel_padding", Select).display = show
            self.query_one("#chk_guides", Checkbox).display = show
        except Exception:
            pass

    def on_mount(self) -> None:
        self.toggle_pdf_options()

    def on_checkbox_changed(self, event: Checkbox.Changed) -> None:
        if event.checkbox.id in ["chk_img", "chk_pdf"]:
            self.toggle_pdf_options()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn_gather":
            self.run_gather_process()

    @work(thread=True)
    def run_gather_process(self) -> None:
        # Prevent double-clicks
        btn = self.query_one("#btn_gather", Button)
        self.call_from_thread(btn.update, "Gathering...")
        self.call_from_thread(lambda: setattr(btn, "disabled", True))

        # Retrieve all values safely from main thread
        source_id = self.query_one("#source_radios", RadioSet).pressed_button.id
        fmt_id = self.query_one("#format_radios", RadioSet).pressed_button.id
        input_data = self.query_one("#input_data", Input).value
        outdir = self.query_one("#outdir_input", Input).value
        
        do_json = self.query_one("#chk_json", Checkbox).value
        do_csv = self.query_one("#chk_csv", Checkbox).value
        do_mpc = self.query_one("#chk_mpc", Checkbox).value
        do_img = self.query_one("#chk_img", Checkbox).value
        do_pdf = self.query_one("#chk_pdf", Checkbox).value
        do_guides = self.query_one("#chk_guides", Checkbox).value
        do_open = self.query_one("#chk_open_folder", Checkbox).value
        
        paper_size = self.query_one("#sel_paper", Select).value
        pad_val = int(self.query_one("#sel_padding", Select).value)

        # Map source
        source_map = {"src_edhrec": "edhrec", "src_file": "file", "src_paste": "paste"}
        source_val = source_map.get(source_id, "edhrec")

        # Map fmt
        fmt_map = {"fmt_paper": "paper", "fmt_arena": "arena", "fmt_mtgo": "mtgo"}
        fmt_val = fmt_map.get(fmt_id, "paper")

        raw_paste = input_data if source_val == "paste" else ""
        file_path = input_data if source_val == "file" else ""
        edhrec_cmd = input_data if source_val == "edhrec" else ""

        save_dir = Path(outdir).resolve()

        # Callbacks
        logger = self.query_one("#gather_log", Log)
        
        def log_cb(msg: str):
            self.call_from_thread(logger.write_line, msg)
            
        def progress_cb(val: float):
            # Textual progress bar can be added later; using logs for now
            pass
            
        log_cb("[bold magenta]Starting MagicGatherer Process...[/bold magenta]")

        try:
            gather_cards(
                save_dir, source_val, raw_paste, file_path,
                edhrec_cmd, fmt_val,
                do_json, do_csv, do_mpc, do_img, do_pdf,
                log_cb, progress_cb,
                pdf_padding=pad_val,
                skip_cb=lambda m: log_cb(f"[red]Skipped: {m}[/red]"),
                draw_guides=do_guides,
                paper_size=paper_size
            )
            
            if do_open:
                import platform, subprocess
                try:
                    if platform.system() == "Windows":
                        os.startfile(save_dir)
                    elif platform.system() == "Darwin":
                        subprocess.Popen(["open", str(save_dir)])
                    else:
                        subprocess.Popen(["xdg-open", str(save_dir)])
                except:
                    pass
        except Exception as e:
            log_cb(f"[bold red]FATAL ERROR: {e}[/bold red]")
        finally:
            self.call_from_thread(btn.update, "Gather your Magic")
            self.call_from_thread(lambda: setattr(btn, "disabled", False))

if __name__ == "__main__":
    app = MagicGathererTUI()
    app.run()
