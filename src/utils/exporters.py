import json
import time
from pathlib import Path
import requests
import xml.etree.ElementTree as ET
from xml.dom import minidom
from typing import List, Dict, Any, Callable, Optional
from src.utils.parsers import sanitize_filename

def export_json(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str) -> None:
    fp = save_dir / f"{safe_pref}.json"
    with open(fp, 'w', encoding='utf-8') as f: 
        json.dump(all_data, f, indent=4)

def export_xml(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str) -> None:
    fp = save_dir / f"{safe_pref}.xml"
    root = ET.Element("order")
    fronts = ET.SubElement(root, "fronts")
    for i, c in enumerate(all_data):
        ce = ET.SubElement(fronts, "card")
        ET.SubElement(ce, "slots").text = str(i)
        ET.SubElement(ce, "name").text = str(c.get("name", ""))
        ET.SubElement(ce, "query").text = str(c.get("name", "")).lower()
        ET.SubElement(ce, "quantity").text = str(c.get("quantity", 1))
    xml_str = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
    with open(fp, "w", encoding="utf-8") as f: 
        f.write(xml_str)

def export_mpc(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str) -> None:
    mpc_path = save_dir / f"{safe_pref}_decklist.txt"
    with open(mpc_path, "w", encoding="utf-8") as f:
        for c in all_data: 
            f.write(f"{c.get('quantity', 1)} {c.get('name', '')}\n")

def export_images(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str, 
                  log_callback: Callable[[str], None],
                  progress_callback: Optional[Callable[[float], None]] = None,
                  start_prog: float = 0.0, end_prog: float = 100.0) -> None:
    img_dir = save_dir / f"{safe_pref}_images"
    img_dir.mkdir(parents=True, exist_ok=True)
    log_callback(f"Downloading images to {img_dir}...")
    
    all_faces: List[Dict[str, Any]] = []
    for c in all_data:
        faces: List[Dict[str, Any]] = []
        if 'image_uris' in c and c['image_uris']:
            faces.append({"name": c['name'].split(" // ")[0], "uris": c['image_uris']})
        elif 'card_faces' in c: 
            base_name = c['name'].split(" // ")[0]
            for idx, f in enumerate(c['card_faces']):
                if 'image_uris' in f and f['image_uris']:
                    suffix = "" if idx == 0 else " (Back)"
                    faces.append({"name": f"{base_name}{suffix}", "uris": f['image_uris']})
        all_faces.extend(faces)
        
    total = len(all_faces)
    for idx, face in enumerate(all_faces):
        if progress_callback is not None and total > 0:
            current_prog = start_prog + (end_prog - start_prog) * (idx / total)
            progress_callback(current_prog)
            
        u = face['uris']
        # Prioritize borderless (border_crop), extended art (art_crop) if requested, else highest res
        url = u.get('png') or u.get('border_crop') or u.get('art_crop') or u.get('large') or u.get('normal')
        if not url: 
            continue
        ext = ".png" if 'png' in url else ".jpg"
        fp = img_dir / f"{sanitize_filename(face['name'])}{ext}"
        if not fp.exists():
            success = False
            for attempt, wait_time in enumerate([1, 2, 4]):
                try:
                    resp = requests.get(url, timeout=10)
                    resp.raise_for_status()
                    with open(fp, 'wb') as f: 
                        f.write(resp.content)
                    success = True
                    time.sleep(0.05)
                    break
                except Exception as e:
                    if attempt < 2:
                        time.sleep(wait_time)
                    else:
                        log_callback(f"Failed image after 3 attempts: {face['name']} ({str(e)})")
            
            if not success:
                continue
                
    if progress_callback is not None:
        progress_callback(end_prog)
    log_callback("Image download complete!")
