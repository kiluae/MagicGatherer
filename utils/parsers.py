import re
from typing import Dict, List, Any

def parse_raw_lines(lines: List[str]) -> Dict[str, Dict[str, Any]]:
    deck_data: Dict[str, Dict[str, Any]] = {}
    for line in lines:
        line = line.strip()
        if not line or line.lower() in ['deck', 'commander', 'sideboard', 'companion', 'format:']: 
            continue
        match = re.match(r'^(?:(\d+)x?\s+)?(.*?)(?:\s+\(([A-Z0-9]{2,5})\)\s+(\S+))?$', line, re.IGNORECASE)
        if match:
            qty_str = match.group(1)
            qty = int(qty_str) if qty_str else 1
            name = match.group(2).strip()
            set_code = match.group(3)
            col_num = match.group(4)
            if name in deck_data: 
                deck_data[name]["quantity"] += qty
            else: 
                deck_data[name] = {
                    "quantity": qty, 
                    "set": set_code.lower() if set_code else None, 
                    "collector_number": col_num.lower() if col_num else None
                }
        else:
            if line not in deck_data: 
                deck_data[line] = {"quantity": 1, "set": None, "collector_number": None}
            else: 
                deck_data[line]["quantity"] += 1
    return deck_data

def format_commander_name(commander_name: str) -> str:
    return re.sub(r"[^\w\s]", "", commander_name).lower().replace(" ", "-")

def sanitize_filename(name: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "", name)
