import requests
from typing import Dict, Any
from src.utils.parsers import format_commander_name

def fetch_edhrec_deck(commander_name: str, deck_dict: Dict[str, Dict[str, Any]]) -> str:
    # appends to deck_dict and returns output_prefix
    json_url = f"https://json.edhrec.com/pages/commanders/{format_commander_name(commander_name)}.json"
    resp = requests.get(json_url)
    if resp.status_code != 200: 
        raise ValueError("EDHREC request failed. Check spelling.")
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
    if commander_name in deck_dict: 
        del deck_dict[commander_name]
    return format_commander_name(commander_name)
