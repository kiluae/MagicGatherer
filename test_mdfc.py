import requests
import json
r = requests.get('https://api.scryfall.com/cards/named?exact=Agadeem\'s Awakening')
data = r.json()
print("Top-level image_uris:", "image_uris" in data)
print("Card faces:")
for f in data.get("card_faces", []):
    print("  ", f["name"], "image_uris" in f)
