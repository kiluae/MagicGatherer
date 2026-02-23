import sys
import os
import time
from pathlib import Path
from typing import Dict, Any, Callable, List

from src.utils.parsers import parse_raw_lines, sanitize_filename
from src.api.edhrec import fetch_edhrec_deck
from src.api.scryfall import fetch_scryfall_paper, fetch_scryfall_digital
from src.utils.exporters import export_json, export_csv, export_mpc, export_images, export_pdf

def resource_path(relative_path: str) -> str:
    """ Get absolute path to resource, works for dev and for PyInstaller wrapper """
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)
    return os.path.join(os.path.abspath(os.path.dirname(os.path.dirname(__file__))), relative_path)

def gather_cards(save_dir: Path, source: str, raw_paste: str, file_path: str,
                 edhrec_cmd: str, format_pref: str,
                 do_json: bool, do_csv: bool, do_mpc: bool, do_img: bool, do_pdf: bool,
                 log_cb: Callable[[str], None], progress_cb: Callable[[float], None],
                 pdf_padding: int = 75, skip_cb: Callable[[str], None] = None,
                 draw_guides: bool = False, paper_size: str = "Letter") -> None:
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
        all_data = fetch_scryfall_digital(deck_dict, log_cb, format_pref, skip_cb=skip_cb)

    progress_cb(50.0)
    log_cb(f"Successfully processed {len(all_data)} cards.")

    safe_pref = sanitize_filename(output_prefix)
    save_dir.mkdir(parents=True, exist_ok=True)

    if do_json:
        export_json(all_data, save_dir, safe_pref)
        log_cb(f"Saved JSON: {save_dir / f'{safe_pref}.json'}")

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
            export_pdf(all_data, save_dir, safe_pref, log_cb, padding_px=pdf_padding, draw_guides=draw_guides, paper_size=paper_size)
            progress_cb(100.0)
        else:
            progress_cb(100.0)
    else:
        progress_cb(100.0)

    log_cb("=== ALL TASKS FINISHED SUCCESSFULLY ===")
