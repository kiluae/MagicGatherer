import json
from pathlib import Path
from typing import Dict, Any

CONFIG_FILE = Path.home() / ".magicgatherer" / "config.json"

class Config:
    def __init__(self):
        self.state: Dict[str, Any] = {
            "format": "paper",
            "padding_px": 75,
            "export_json": True,
            "export_csv": False,
            "export_decklist": False,
            "export_images": True,
            "export_pdf": True,
            "draw_crop_marks": True,
            "paper_size": "US Letter",
        }
        self.load()

    def load(self):
        """Loads state from config.json if it exists."""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    disk_state = json.load(f)
                    self.state.update(disk_state)
            except Exception as e:
                print(f"Warning: Failed to load config - {e}")

    def save(self):
        """Saves current state to config.json."""
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.state, f, indent=4)
        except Exception as e:
            print(f"Warning: Failed to save config - {e}")

    # Helper getters/setters for clean UI binding
    def get(self, key: str, default: Any = None) -> Any:
        return self.state.get(key, default)
        
    def set(self, key: str, value: Any):
        self.state[key] = value
