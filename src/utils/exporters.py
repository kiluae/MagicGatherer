import json
import time
from pathlib import Path
import requests
import csv
from typing import List, Dict, Any, Callable, Optional
from PIL import Image
from src.utils.parsers import sanitize_filename

def export_json(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str) -> None:
    fp = save_dir / f"{safe_pref}.json"
    with open(fp, 'w', encoding='utf-8') as f: 
        json.dump(all_data, f, indent=4)

def export_csv(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str) -> None:
    fp = save_dir / f"{safe_pref}.csv"
    with open(fp, 'w', encoding='utf-8', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(["Quantity", "Name", "Type", "Mana Cost", "CMC", "Oracle Text"])
        for c in all_data:
            writer.writerow([
                c.get("quantity", 1),
                c.get("name", ""),
                c.get("type_line", ""),
                c.get("mana_cost", ""),
                c.get("cmc", ""),
                c.get("oracle_text", "")
            ])

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


def export_pdf(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str, log_callback: Callable[[str], None], padding_px: int = 75) -> None:
    img_dir = save_dir / f"{safe_pref}_images"
    if not img_dir.exists():
        log_callback("Error: Image directory not found. Cannot generate PDF.")
        return

    # Constants for 600 DPI US Letter
    PAGE_WIDTH = 5100
    PAGE_HEIGHT = 6600
    CARD_WIDTH = 1500  # 2.5 inches * 600 dpi
    CARD_HEIGHT = 2100 # 3.5 inches * 600 dpi
    
    # Calculate perfectly centered margins for a 3x3 grid including padding space
    TOTAL_GRID_WIDTH: int = int((3 * CARD_WIDTH) + (2 * padding_px))
    TOTAL_GRID_HEIGHT: int = int((3 * CARD_HEIGHT) + (2 * padding_px))
    
    # If the user sets massive padding causing bleed over the physical page, clamp it logically to nearest fit
    if TOTAL_GRID_WIDTH > PAGE_WIDTH:
        padding_px = int((PAGE_WIDTH - (3 * CARD_WIDTH)) // 3)
        TOTAL_GRID_WIDTH = int((3 * CARD_WIDTH) + (2 * padding_px))
    if TOTAL_GRID_HEIGHT > PAGE_HEIGHT:
        padding_px = int((PAGE_HEIGHT - (3 * CARD_HEIGHT)) // 3)
        TOTAL_GRID_HEIGHT = int((3 * CARD_HEIGHT) + (2 * padding_px))

    MARGIN_X: int = int((PAGE_WIDTH - TOTAL_GRID_WIDTH) // 2)
    MARGIN_Y: int = int((PAGE_HEIGHT - TOTAL_GRID_HEIGHT) // 2)

    # Flatten out quantities into a massive single list
    card_files_to_print: List[Path] = []
    
    for c in all_data:
        qty = int(c.get('quantity', 1))
        
        # Handle MDFC faces separately if present
        if 'card_faces' in c and not 'image_uris' in c:
            base_name = c['name'].split(" // ")[0]
            for idx, f in enumerate(c['card_faces']):
                if 'image_uris' in f and f['image_uris']:
                    suffix = "" if idx == 0 else " (Back)"
                    face_name = f"{base_name}{suffix}"
                    # Try both extensions
                    fp_jpg = img_dir / f"{sanitize_filename(face_name)}.jpg"
                    fp_png = img_dir / f"{sanitize_filename(face_name)}.png"
                    if fp_jpg.exists(): card_files_to_print.extend([fp_jpg] * qty)
                    elif fp_png.exists(): card_files_to_print.extend([fp_png] * qty)
        else:
            # Standard single face
            card_name = c['name'].split(" // ")[0]
            fp_jpg = img_dir / f"{sanitize_filename(card_name)}.jpg"
            fp_png = img_dir / f"{sanitize_filename(card_name)}.png"
            if fp_jpg.exists(): card_files_to_print.extend([fp_jpg] * qty)
            elif fp_png.exists(): card_files_to_print.extend([fp_png] * qty)

    if not card_files_to_print:
        log_callback("No downloaded images found to compile into PDF.")
        return

    log_callback(f"Compiling {len(card_files_to_print)} cards into 3x3 proxy pages...")

    pages = []
    current_page = Image.new('RGB', (PAGE_WIDTH, PAGE_HEIGHT), (255, 255, 255))
    x_idx: int = 0
    y_idx: int = 0

    for fp in card_files_to_print:
        try:
            with Image.open(fp) as img:
                img = img.convert('RGB')
                img = img.resize((CARD_WIDTH, CARD_HEIGHT), Image.Resampling.LANCZOS)
                
                pos_x: int = int(MARGIN_X + (x_idx * (CARD_WIDTH + padding_px)))
                pos_y: int = int(MARGIN_Y + (y_idx * (CARD_HEIGHT + padding_px)))
                
                current_page.paste(img, (pos_x, pos_y))
                
                x_idx += 1
                if x_idx >= 3:
                    x_idx = 0
                    y_idx += 1
                    
                if y_idx >= 3:
                    pages.append(current_page)
                    current_page = Image.new('RGB', (PAGE_WIDTH, PAGE_HEIGHT), (255, 255, 255))
                    x_idx = 0
                    y_idx = 0
                    
        except Exception as e:
            log_callback(f"Warning: Failed to compile {fp.name} into PDF - {e}")

    # Append the last partial page if it has any cards on it
    if x_idx > 0 or y_idx > 0:
        pages.append(current_page)

    if pages:
        pdf_path = save_dir / f"{safe_pref}_proxies.pdf"
        pages[0].save(
            pdf_path, 
            "PDF", 
            resolution=600.0, 
            save_all=True, 
            append_images=pages[1:]
        )
        log_callback(f"Successfully generated PDF Proxies: {pdf_path}")
