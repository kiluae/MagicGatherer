from PyQt5.QtCore import QThread, pyqtSignal
from pathlib import Path
from api import safe_get

CACHE_DIR = Path.home() / ".magicgatherer" / "cache"

class ImageFetchThread(QThread):
    image_ready = pyqtSignal(str)
    
    def __init__(self, card_name=None, image_uri=None):
        super().__init__()
        self.card_name = card_name
        self.image_uri = image_uri

    def run(self):
        CACHE_DIR.mkdir(parents=True, exist_ok=True)
        try:
            if not self.image_uri and self.card_name:
                url = "https://api.scryfall.com/cards/named"
                resp = safe_get(url, params={"exact": self.card_name})
                resp.raise_for_status()
                data = resp.json()
                if "image_uris" in data:
                    self.image_uri = data["image_uris"].get("png", data["image_uris"].get("large", data["image_uris"].get("normal")))
                elif "card_faces" in data:
                     for face in data["card_faces"]:
                         if "image_uris" in face:
                             self.image_uri = face["image_uris"].get("png", face["image_uris"].get("large", face["image_uris"].get("normal")))
                             break
                    
            if not self.image_uri:
                return
                
            filename = self.image_uri.split("/")[-1].split("?")[0]
            if not filename.endswith(".jpg") and not filename.endswith(".png"):
                filename += ".jpg"
                
            filepath = CACHE_DIR / filename
            if not filepath.exists():
                resp = safe_get(self.image_uri)
                resp.raise_for_status()
                with open(filepath, 'wb') as f:
                    f.write(resp.content)
            
            self.image_ready.emit(str(filepath))
        except Exception as e:
            print(f"Image fetch error: {e}")
