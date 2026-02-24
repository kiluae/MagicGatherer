import os
import sys
from pathlib import Path
from typing import Optional

from textual.app import App, ComposeResult
from textual.containers import Grid, Horizontal, Vertical
from textual.widgets import Header, Footer, Input, RadioSet, RadioButton, Checkbox, Button, Log, Static, Select
from textual import work

# Ensure the parent directory is in sys.path so we can import 'logic' and others
current_dir = os.path.dirname(os.path.abspath(__file__))
parent_dir = os.path.dirname(current_dir)
if parent_dir not in sys.path:
    sys.path.insert(0, parent_dir)

from logic import gather_cards

class MagicGathererTUI(App):
    """A Textual Dashboard for MagicGatherer v3.0"""

    CSS = """
    Screen {
        background: #121212;
    }
    
    .panel {
        border: solid #333333;
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

    Button {
        width: 100%;
        margin-top: 1;
    }
    
    Log {
        border: solid #444444;
        height: 100%;
        min-height: 10;
        margin-top: 1;
        background: black;
        color: #4CAF50;
    }
    
    #exit_label {
        height: 3;
        content-align: center middle;
        text-style: bold;
        background: #2C2C2C;
        color: white;
    }
    """

    BINDINGS = [
        ("q", "quit", "Quit")
    ]

    def compose(self) -> ComposeResult:
        yield Header(show_clock=True)
        yield Static("Press [b]Q[/b] to exit and return to the Desktop app.", id="exit_label")
        
        with Grid(id="main_grid"):
            # LEFT PANE
            with Vertical(id="left_pane", classes="panel"):
                yield Static("[bold cyan]1. Input Selection[/bold cyan]")
                yield RadioSet(
                    RadioButton("EDHREC Commander", id="src_edhrec", value=True),
                    RadioButton("Local Decklist File", id="src_file"),
                    RadioButton("Raw Text Paste", id="src_paste"),
                    id="source_radios"
                )
                yield Input(placeholder="Krenko, Mob Boss", id="input_data")
                
                yield Static("\n[bold cyan]2. Format Filter[/bold cyan]")
                yield RadioSet(
                    RadioButton("Paper (Tabletop)", id="fmt_paper", value=True),
                    RadioButton("MTG Arena", id="fmt_arena"),
                    RadioButton("MTG Online", id="fmt_mtgo"),
                    id="format_radios"
                )
            
            # RIGHT PANE
            with Vertical(id="right_pane", classes="panel"):
                yield Static("[bold cyan]3. Output Options[/bold cyan]")
                with Horizontal():
                    with Vertical():
                        yield Checkbox("JSON", id="chk_json", value=True)
                        yield Checkbox("CSV", id="chk_csv", value=True)
                        yield Checkbox("MTGO .dek", id="chk_mtgo", value=True)
                    with Vertical():
                        yield Checkbox("Images", id="chk_img", value=True)
                        yield Checkbox("PDF Proxy", id="chk_pdf", value=True)
                
                yield Select(
                    [("US Letter", "US Letter"), ("A4", "A4"), ("Legal", "Legal"), ("Tabloid", "Tabloid")],
                    prompt="Paper Size", id="sel_paper", value="US Letter"
                )
                yield Select(
                    [("0 px", "0"), ("75 px", "75"), ("150 px", "150")],
                    prompt="Padding", id="sel_padding", value="75"
                )
                
                yield Input(placeholder="./", id="outdir_input", value=".")
                yield Button("Gather your Magic", id="btn_gather", variant="success")
                yield Log(id="gather_log")

        yield Footer()

    async def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "btn_gather":
            self.run_gather_process()

    @work(thread=True)
    def run_gather_process(self) -> None:
        btn = self.query_one("#btn_gather", Button)
        self.call_from_thread(btn.update, "Gathering...")
        self.call_from_thread(lambda: setattr(btn, "disabled", True))

        source_id = self.query_one("#source_radios", RadioSet).pressed_button.id
        fmt_id = self.query_one("#format_radios", RadioSet).pressed_button.id
        input_data = self.query_one("#input_data", Input).value
        outdir = self.query_one("#outdir_input", Input).value
        
        do_json = self.query_one("#chk_json", Checkbox).value
        do_csv = self.query_one("#chk_csv", Checkbox).value
        do_mtgo = self.query_one("#chk_mtgo", Checkbox).value
        do_img = self.query_one("#chk_img", Checkbox).value
        do_pdf = self.query_one("#chk_pdf", Checkbox).value
        
        paper_size = self.query_one("#sel_paper", Select).value
        pad_val = int(self.query_one("#sel_padding", Select).value)

        source_map = {"src_edhrec": "edhrec", "src_file": "file", "src_paste": "paste"}
        source_val = source_map.get(source_id, "edhrec")

        fmt_map = {"fmt_paper": "paper", "fmt_arena": "arena", "fmt_mtgo": "mtgo"}
        fmt_val = fmt_map.get(fmt_id, "paper")

        logger = self.query_one("#gather_log", Log)
        def log_cb(msg: str):
            self.call_from_thread(logger.write_line, msg)
        def prog_cb(val: float):
            pass

        try:
            gather_cards(
                save_dir=Path(outdir).resolve(),
                source=source_val,
                raw_paste=input_data if source_val == "paste" else "",
                file_path=input_data if source_val == "file" else "",
                edhrec_cmd=input_data if source_val == "edhrec" else "",
                format_pref=fmt_val,
                options={
                    "json": do_json, "csv": do_csv, "mtgo": do_mtgo,
                    "img": do_img, "pdf": do_pdf
                },
                log_cb=log_cb,
                progress_cb=prog_cb,
                pdf_config={"paper_size": paper_size, "dpi": 600, "padding": pad_val}
            )
        except Exception as e:
            log_cb(f"[red]Error: {e}[/red]")
        finally:
            self.call_from_thread(btn.update, "Gather your Magic")
            self.call_from_thread(lambda: setattr(btn, "disabled", False))

if __name__ == "__main__":
    app = MagicGathererTUI()
    app.run()
