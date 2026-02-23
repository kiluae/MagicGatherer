import requests
from typing import Dict, Any
from src.utils.parsers import format_commander_name

def fetch_edhrec_deck(commander_name: str, deck_dict: Dict[str, Dict[str, Any]]) -> str:
    # appends to deck_dict and returns output_prefix
    formatted_name = format_commander_name(commander_name)
    json_url = f"https://json.edhrec.com/pages/commanders/{formatted_name}.json"
    resp = requests.get(json_url)
    if resp.status_code != 200: 
        suggestion = ""
        try:
            fuzzy = requests.get(f"https://api.scryfall.com/cards/named?fuzzy={commander_name}")
            if fuzzy.status_code == 200:
                scry = fuzzy.json()
                if "name" in scry:
                    suggestion = f"\n\nDid you mean '{scry['name']}'?"
        except Exception:
            pass
        raise ValueError(f"EDHREC request failed. Check spelling.{suggestion}")
        
    data = resp.json()
    try:
        container = data.get('container', {})
        json_dict = container.get('json_dict', {}) if isinstance(container, dict) else {}
        for clist in json_dict.get('cardlists', []):
            for card in clist.get('cardviews', []):
                cname = card.get('name')
                if cname:
                    deck_dict[cname] = {"quantity": 1, "set": None, "collector_number": None}
    except Exception: 
        pass
    deck_dict.pop(commander_name, None)
    return format_commander_name(commander_name)
