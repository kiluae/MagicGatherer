import xml.etree.ElementTree as ET
from xml.dom import minidom
from typing import List, Dict, Any, Callable, Optional
from pathlib import Path
from PIL import Image, ImageDraw
import json
import csv
import time
import requests
import re

def export_mtgo_dek(cards: List[Dict[str, Any]], output_path: Path):
    """Exports to MTGO .dek XML format."""
    root = ET.Element("Deck")
    for card in cards:
        name = card.get("name", "")
        qty = card.get("quantity", 1)
        # Handle split cards (MTGO uses front half or slash)
        if " // " in name:
            name = name.split(" // ")[0]
            
        card_el = ET.SubElement(root, "Cards")
        card_el.set("CatID", "0") # Scryfall doesn't guarantee MTGO ID easily in search
        card_el.set("Quantity", str(qty))
        card_el.set("Sideboard", "false")
        card_el.set("Name", name)
        
    xmlstr = minidom.parseString(ET.tostring(root)).toprettyxml(indent="  ")
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(xmlstr)

def generate_arena_clipboard(cards: List[Dict[str, Any]]) -> str:
    """Generates an MTG Arena compatible import string."""
    lines = []
    for card in cards:
        qty = card.get("quantity", 1)
        name = card.get("name", "")
        if " // " in name:
            name = name.split(" // ")[0]
            
        settings = card.get("set", "")
        collector = card.get("collector_number", "")
        
        # [Quantity] [Card Name] ([Set Code]) [Collector Number]
        if settings and collector:
            lines.append(f"{qty} {name} ({settings.upper()}) {collector}")
        else:
            lines.append(f"{qty} {name}")
            
    return "\n".join(lines)

def draw_crop_marks_on_image(image_path: Path, output_path: Path, mark_length: int = 15):
    """
    Uses PIL to draw crop marks directly on the card image's corners 
    before compiling into a PDF.
    """
    try:
        with Image.open(image_path) as img:
            img = img.convert('RGB')
            draw = ImageDraw.Draw(img)
            width, height = img.size
            color = (200, 200, 200) # Subtle grey
            
            # Top Left
            draw.line([(0, 0), (mark_length, 0)], fill=color, width=2)
            draw.line([(0, 0), (0, mark_length)], fill=color, width=2)
            
            # Top Right
            draw.line([(width, 0), (width - mark_length, 0)], fill=color, width=2)
            draw.line([(width, 0), (width, mark_length)], fill=color, width=2)
            
            # Bottom Left
            draw.line([(0, height), (mark_length, height)], fill=color, width=2)
            draw.line([(0, height), (0, height - mark_length)], fill=color, width=2)
            
            # Bottom Right
            draw.line([(width, height), (width - mark_length, height)], fill=color, width=2)
            draw.line([(width, height), (width, height - mark_length)], fill=color, width=2)
            
            img.save(output_path, "JPEG", quality=95)
            return True
    except Exception as e:
        print(f"Error drawing crop marks on {image_path}: {e}")
        return False


def sanitize_filename(name: str) -> str:
    return re.sub(r'[\\/*?:"<>|]', "", name)

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

def mm_to_px(mm: float, dpi: int) -> int:
    return int((mm / 25.4) * dpi)

def export_pdf(all_data: List[Dict[str, Any]], save_dir: Path, safe_pref: str, 
               log_callback: Callable[[str], None], pdf_config: Dict[str, Any] = None) -> None:
    
    config = pdf_config or {
        "paper_size": "US Letter", "dpi": 300, "cols": 3, "rows": 3,
        "space_x": 0.0, "space_y": 0.0, "off_x": 0.0, "off_y": 0.0,
        "bleed_enabled": False, "bleed_mm": 1.0,
        "guides_enabled": True, "guide_type": "Corners"
    }
    
    dpi = config.get("dpi", 300)
    paper_size = config.get("paper_size", "US Letter")
    
    img_dir = save_dir / f"{safe_pref}_images"
    if not img_dir.exists():
        log_callback("Error: Image directory not found. Cannot generate PDF.")
        return

    # Base paper dims in inches
    paper_inches = {
        "A4": (8.27, 11.69),
        "US Letter": (8.5, 11.0),
        "A3": (11.69, 16.54),
        "Legal": (8.5, 14.0),
        "A5": (5.83, 8.27),
        "Tabloid": (11.0, 17.0)
    }
    
    if paper_size not in paper_inches:
        log_callback(f"Warning: Unknown paper size '{paper_size}', defaulting to US Letter.")
        PAGE_WIDTH_IN, PAGE_HEIGHT_IN = paper_inches["US Letter"]
    else:
        PAGE_WIDTH_IN, PAGE_HEIGHT_IN = paper_inches[paper_size]

    PAGE_WIDTH = int(PAGE_WIDTH_IN * dpi)
    PAGE_HEIGHT = int(PAGE_HEIGHT_IN * dpi)
    
    # Standard MTG Poker size is 63x88mm
    CARD_WIDTH_MM = 63.0
    CARD_HEIGHT_MM = 88.0
    
    if config.get("bleed_enabled"):
        bleed_px = mm_to_px(config.get("bleed_mm", 1.0), dpi)
        CARD_WIDTH = mm_to_px(CARD_WIDTH_MM, dpi) + (bleed_px * 2)
        CARD_HEIGHT = mm_to_px(CARD_HEIGHT_MM, dpi) + (bleed_px * 2)
    else:
        CARD_WIDTH = mm_to_px(CARD_WIDTH_MM, dpi)
        CARD_HEIGHT = mm_to_px(CARD_HEIGHT_MM, dpi)
        
    space_x = mm_to_px(config.get("space_x", 0.0), dpi)
    space_y = mm_to_px(config.get("space_y", 0.0), dpi)
    off_x = mm_to_px(config.get("off_x", 0.0), dpi)
    off_y = mm_to_px(config.get("off_y", 0.0), dpi)
    
    cols = config.get("cols", 3)
    rows = config.get("rows", 3)
    
    TOTAL_GRID_WIDTH: int = int((cols * CARD_WIDTH) + ((cols - 1) * space_x))
    TOTAL_GRID_HEIGHT: int = int((rows * CARD_HEIGHT) + ((rows - 1) * space_y))
    
    if TOTAL_GRID_WIDTH > PAGE_WIDTH:
        log_callback("Warning: Grid width exceeds page dimension. Content may clip.")
    if TOTAL_GRID_HEIGHT > PAGE_HEIGHT:
        log_callback("Warning: Grid height exceeds page dimension. Content may clip.")

    MARGIN_X: int = int((PAGE_WIDTH - TOTAL_GRID_WIDTH) // 2) + off_x
    MARGIN_Y: int = int((PAGE_HEIGHT - TOTAL_GRID_HEIGHT) // 2) + off_y

    card_files_to_print: List[Path] = []
    
    for c in all_data:
        qty = int(c.get('quantity', 1))
        
        if 'card_faces' in c and not 'image_uris' in c:
            base_name = c['name'].split(" // ")[0]
            for idx, f in enumerate(c['card_faces']):
                if 'image_uris' in f and f['image_uris']:
                    suffix = "" if idx == 0 else " (Back)"
                    face_name = f"{base_name}{suffix}"
                    fp_jpg = img_dir / f"{sanitize_filename(face_name)}.jpg"
                    fp_png = img_dir / f"{sanitize_filename(face_name)}.png"
                    if fp_jpg.exists(): card_files_to_print.extend([fp_jpg] * qty)
                    elif fp_png.exists(): card_files_to_print.extend([fp_png] * qty)
        else:
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
                
                pos_x: int = int(MARGIN_X + (x_idx * (CARD_WIDTH + space_x)))
                pos_y: int = int(MARGIN_Y + (y_idx * (CARD_HEIGHT + space_y)))
                
                current_page.paste(img, (pos_x, pos_y))
                
                if config.get("guides_enabled"):
                    draw = ImageDraw.Draw(current_page)
                    color = (200, 200, 200)
                    guide_type = config.get("guide_type", "Corners")
                    
                    if guide_type == "Corners":
                        length = mm_to_px(3.0, dpi) 
                        
                        # Top Left
                        draw.line([(pos_x, pos_y), (pos_x - length, pos_y)], fill=color)
                        draw.line([(pos_x, pos_y), (pos_x, pos_y - length)], fill=color)
                        
                        # Top Right
                        draw.line([(pos_x + CARD_WIDTH, pos_y), (pos_x + CARD_WIDTH + length, pos_y)], fill=color)
                        draw.line([(pos_x + CARD_WIDTH, pos_y), (pos_x + CARD_WIDTH, pos_y - length)], fill=color)
                        
                        # Bottom Left
                        draw.line([(pos_x, pos_y + CARD_HEIGHT), (pos_x - length, pos_y + CARD_HEIGHT)], fill=color)
                        draw.line([(pos_x, pos_y + CARD_HEIGHT), (pos_x, pos_y + CARD_HEIGHT + length)], fill=color)
                        
                        # Bottom Right
                        draw.line([(pos_x + CARD_WIDTH, pos_y + CARD_HEIGHT), (pos_x + CARD_WIDTH + length, pos_y + CARD_HEIGHT)], fill=color)
                        draw.line([(pos_x + CARD_WIDTH, pos_y + CARD_HEIGHT), (pos_x + CARD_WIDTH, pos_y + CARD_HEIGHT + length)], fill=color)
                    
                    elif guide_type == "Full Outline":
                        draw.rectangle([pos_x, pos_y, pos_x + CARD_WIDTH, pos_y + CARD_HEIGHT], outline=color, width=1)
                        
                    elif guide_type == "Edges":
                        ext_l = mm_to_px(3.0, dpi)
                        draw.line([(pos_x - ext_l, pos_y), (pos_x + CARD_WIDTH + ext_l, pos_y)], fill=color)
                        draw.line([(pos_x - ext_l, pos_y + CARD_HEIGHT), (pos_x + CARD_WIDTH + ext_l, pos_y + CARD_HEIGHT)], fill=color)
                        draw.line([(pos_x, pos_y - ext_l), (pos_x, pos_y + CARD_HEIGHT + ext_l)], fill=color)
                        draw.line([(pos_x + CARD_WIDTH, pos_y - ext_l), (pos_x + CARD_WIDTH, pos_y + CARD_HEIGHT + ext_l)], fill=color)
                
                x_idx += 1
                if x_idx >= cols:
                    x_idx = 0
                    y_idx += 1
                    
                if y_idx >= rows:
                    pages.append(current_page)
                    current_page = Image.new('RGB', (PAGE_WIDTH, PAGE_HEIGHT), (255, 255, 255))
                    x_idx = 0
                    y_idx = 0
                    
        except Exception as e:
            log_callback(f"Warning: Failed to compile {fp.name} into PDF - {e}")

    if x_idx > 0 or y_idx > 0:
        pages.append(current_page)

    if pages:
        pdf_path = save_dir / f"{safe_pref}_proxies.pdf"
        pages[0].save(
            pdf_path, 
            "PDF", 
            resolution=float(dpi), 
            save_all=True, 
            append_images=pages[1:]
        )
        log_callback(f"Successfully generated PDF Proxies: {pdf_path}")
