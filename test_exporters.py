import requests
import json
from pathlib import Path

# Mock log cb
def log_cb(x): print("LOG:", x)

import src.api.scryfall as scry

def export_images_test(all_data, log_callback):
    all_faces = []
    for c in all_data:
        faces = []
        if 'image_uris' in c and c['image_uris']:
            faces.append({"name": c['name'].split(" // ")[0], "uris": c['image_uris']})
        elif 'card_faces' in c: 
            base_name = c['name'].split(" // ")[0]
            for idx, f in enumerate(c['card_faces']):
                if 'image_uris' in f and f['image_uris']:
                    suffix = "" if idx == 0 else " (Back)"
                    faces.append({"name": f"{base_name}{suffix}", "uris": f['image_uris']})
        all_faces.extend(faces)
    
    for f in all_faces:
        print(f["name"])

r = requests.get('https://api.scryfall.com/cards/named?exact=Agadeem\'s Awakening')
d = r.json()
c = scry.trim_card_data(d, 1)

export_images_test([c], log_cb)
