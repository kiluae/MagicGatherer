import os
import time
import requests
from pathlib import Path
from typing import List, Dict, Any, Callable, Optional

from api import safe_get, safe_post
from exporters import (
    export_json, export_csv, export_mtgo_dek, 
    generate_arena_clipboard, export_images, export_pdf,
    sanitize_filename
)

# Re-export for convenience
__all__ = [
    'gather_cards', 'export_json', 'export_csv', 'export_mtgo_dek',
    'generate_arena_clipboard', 'export_images', 'export_pdf', 'sanitize_filename'
]

def gather_cards(
    save_dir: Path,
    source: str, # "paste", "file", "edhrec"
    raw_paste: str,
    file_path: str,
    edhrec_cmd: str,
    format_pref: str, # "paper", "arena", "mtgo"
    options: Dict[str, bool], # {"json": True, "csv": True, ...}
    log_cb: Callable[[str], None],
    progress_cb: Callable[[float], None],
    pdf_config: Optional[Dict[str, Any]] = None
) -> None:
    """
    Centralized logic to fetch and export cards.
    This is shared between the Qt GUI and the TUI.
    """
    all_cards: List[Dict[str, Any]] = []
    prefix = "gathered_deck"
    
    # 1. Parsing / Initial Fetch
    if source == "paste":
        lines = [line.strip() for line in raw_paste.split('\n') if line.strip()]
        all_cards = _fetch_scryfall_batch(lines, log_cb)
        prefix = "pasted_list"
    elif source == "file":
        p = Path(file_path)
        if not p.exists():
            raise FileNotFoundError(f"File not found: {file_path}")
        with open(p, 'r', encoding='utf-8') as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
        all_cards = _fetch_scryfall_batch(lines, log_cb)
        prefix = p.stem
    elif source == "edhrec":
        log_cb(f"Querying EDHREC for {edhrec_cmd}...")
        all_cards = _fetch_edhrec_full_deck(edhrec_cmd, log_cb)
        prefix = sanitize_filename(edhrec_cmd).replace(" ", "_")

    if not all_cards:
        raise ValueError("No cards found to process.")

    # 2. Format Filtering
    log_cb(f"Applying {format_pref} legality filters...")
    filtered = []
    for card in all_cards:
        games = card.get("games", [])
        if format_pref == "arena" and "arena" not in games:
            log_cb(f"Skipping {card.get('name')} (Not on Arena)")
            continue
        if format_pref == "mtgo" and "mtgo" not in games:
            log_cb(f"Skipping {card.get('name')} (Not on MTGO)")
            continue
        filtered.append(card)
    
    all_cards = filtered
    if not all_cards:
        raise ValueError("All cards filtered out by legality check.")

    # 3. Exporting
    save_dir.mkdir(parents=True, exist_ok=True)
    safe_prefix = sanitize_filename(prefix)
    
    if options.get("json"):
        export_json(all_cards, save_dir, safe_prefix)
        log_cb("JSON Exported.")
    if options.get("csv"):
        export_csv(all_cards, save_dir, safe_prefix)
        log_cb("CSV Exported.")
    if options.get("mtgo"):
        export_mtgo_dek(all_cards, save_dir / f"{safe_prefix}.dek")
        log_cb("MTGO .dek Exported.")
    
    if options.get("img") or options.get("pdf"):
        export_images(all_cards, save_dir, safe_prefix, log_cb, progress_cb, 20, 80)
        if options.get("pdf"):
            export_pdf(all_cards, save_dir, safe_prefix, log_cb, pdf_config)
            log_cb("PDF Proxies Generated.")

    progress_cb(100.0)
    log_cb("Gathering Complete!")

def _fetch_scryfall_batch(lines: List[str], log_cb: Callable[[str], None]) -> List[Dict[str, Any]]:
    """Helper to fetch a list of names/quantities from Scryfall."""
    parsed = []
    import re
    for line in lines:
        match = re.match(r'^(\d+)x?\s+(.*)$', line, re.IGNORECASE)
        if match:
            qty = int(match.group(1))
            name = match.group(2).strip()
        else:
            qty = 1
            name = line.strip()
        parsed.append({"name": name, "quantity": qty})
    
    all_data = []
    chunk_size = 75
    for i in range(0, len(parsed), chunk_size):
        chunk = parsed[i:i+chunk_size]
        payload = {"identifiers": [{"name": p["name"]} for p in chunk]}
        resp = safe_post("https://api.scryfall.com/cards/collection", json=payload)
        resp.raise_for_status()
        data = resp.json()
        
        # Match quantities back
        for scry_card in data.get("data", []):
            # Find the original qty
            for p in chunk:
                if p["name"].lower() == scry_card.get("name", "").lower():
                    scry_card["quantity"] = p["quantity"]
                    break
            all_data.append(scry_card)
    return all_data

def _fetch_edhrec_full_deck(commander: str, log_cb: Callable[[str], None]) -> List[Dict[str, Any]]:
    """Fetches the average deck from EDHREC and looks up details in Scryfall."""
    cmd_slug = commander.lower().replace(" ", "-").replace("'", "").replace(",", "")
    url = f"https://json.edhrec.com/pages/commanders/{cmd_slug}.json"
    r = safe_get(url)
    if r.status_code != 200:
        raise Exception(f"Commander '{commander}' not found on EDHREC.")
    
    data = r.json()
    cardlists = data.get("cardlists", [])
    names = set()
    for lst in cardlists:
        for c in lst.get("cardviews", []):
            if c.get("name"):
                names.add(c["name"])
    
    # Batch fetch from Scryfall
    return _fetch_scryfall_batch(list(names), log_cb)
