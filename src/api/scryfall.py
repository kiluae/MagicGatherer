import os
import json
import time
from pathlib import Path
import requests
from typing import Dict, List, Any
from src.utils.parsers import sanitize_filename

CACHE_DIR = Path.home() / ".magicgatherer" / "cache"

def get_cached_card(name: str) -> Dict[str, Any]:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"{sanitize_filename(name)}.json"
    if cache_file.exists():
        with open(cache_file, 'r', encoding='utf-8') as f:
            return json.load(f)
    return {}

def save_cached_card(name: str, card_data: Dict[str, Any]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    cache_file = CACHE_DIR / f"{sanitize_filename(name)}.json"
    with open(cache_file, 'w', encoding='utf-8') as f:
        json.dump(card_data, f)

def trim_card_data(card: Dict[str, Any], quantity: int) -> Dict[str, Any]:
    trimmed: Dict[str, Any] = {
        "name": card.get("name"), 
        "quantity": quantity, 
        "mana_cost": card.get("mana_cost", ""),
        "cmc": card.get("cmc"), 
        "type_line": card.get("type_line"), 
        "oracle_text": card.get("oracle_text", ""),
        "keywords": card.get("keywords", []), 
        "legalities": card.get("legalities", {}),
        "image_uris": card.get("image_uris", {}),
        "promo_types": card.get("promo_types", []),
        "frame_effects": card.get("frame_effects", []),
        "border_color": card.get("border_color", ""),
        # Retain 'games' key to correctly evaluate the local Arena filter!
        "games": card.get("games", [])
    }
    if "card_faces" in card:
        trimmed["card_faces"] = []
        for face in card["card_faces"]:
            trimmed["card_faces"].append({
                "name": face.get("name"), 
                "mana_cost": face.get("mana_cost", ""),
                "type_line": face.get("type_line"), 
                "oracle_text": face.get("oracle_text", ""),
                "image_uris": face.get("image_uris", {})
            })
    return trimmed

def fetch_scryfall_paper(deck_dict: Dict[str, Dict[str, Any]]) -> List[Dict[str, Any]]:
    all_data: List[Dict[str, Any]] = []
    url = "https://api.scryfall.com/cards/collection"
    
    uncached_identifiers = []
    
    for n, info in deck_dict.items():
        qty = info.get("quantity", 1)
        cached = get_cached_card(n)
        if cached:
            cached["quantity"] = qty
            all_data.append(cached)
        else:
            uncached_identifiers.append(
                {"set": info["set"], "collector_number": info["collector_number"]} if info.get("set") else {"name": n}
            )

    for i in range(0, len(uncached_identifiers), 75):
        chunk = uncached_identifiers[i:i+75]
        resp = requests.post(url, json={"identifiers": chunk})
        if resp.status_code == 200:
            for card in resp.json().get('data', []):
                cname = card.get("name", "")
                qty = deck_dict.get(cname, {}).get("quantity", 1)
                if cname not in deck_dict and " // " in cname: 
                    qty = deck_dict.get(cname.split(" // ")[0], {}).get("quantity", 1)
                trimmed = trim_card_data(card, qty)
                save_cached_card(cname, trimmed)
                all_data.append(trimmed)
        time.sleep(0.1)
    return all_data

def fetch_scryfall_digital(deck_dict: Dict[str, Dict[str, Any]], log_cb: Any, game_client: str, skip_cb: Any = None) -> List[Dict[str, Any]]:
    all_data: List[Dict[str, Any]] = []
    base_url = "https://api.scryfall.com/cards/search"
    basic_lands = {"Plains", "Island", "Swamp", "Mountain", "Forest", "Snow-Covered Plains", "Snow-Covered Island", "Snow-Covered Swamp", "Snow-Covered Mountain", "Snow-Covered Forest", "Wastes"}
    
    for idx, (name, info) in enumerate(deck_dict.items()):
        qty = info.get("quantity", 1)
        is_basic = name in basic_lands
        
        cached = get_cached_card(name)
        if cached and (is_basic or game_client in cached.get("games", [])):
            cached["quantity"] = qty
            all_data.append(cached)
            continue
            
        log_cb(f"Searching {game_client.title()} for {name}...")
        q = f'!"{name}" game:{game_client}'
        resp = requests.get(base_url, params={'q': q})
        
        # Fuzzy Fallback
        if resp.status_code == 404:
            q_fuzzy = f'{name} game:{game_client}'
            resp = requests.get(base_url, params={'q': q_fuzzy})
            
        if resp.status_code == 200:
            data = resp.json().get('data', [])
            if data:
                trimmed = trim_card_data(data[0], qty)
                save_cached_card(name, trimmed)
                all_data.append(trimmed)
        else:
            msg = f"Skipping {name} (Not found on Scryfall {game_client.title()} endpoints)"
            log_cb(msg)
            if skip_cb:
                skip_cb(name)
            
        time.sleep(0.1)
    return all_data
