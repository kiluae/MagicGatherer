import os
from exporters import export_mtgo_dek, generate_arena_clipboard
from pathlib import Path

test_cards = [
    {"name": "Krenko, Mob Boss", "quantity": 1, "type": "Legendary Creature — Goblin Warrior", "set": "ddn", "collector_number": "253"},
    {"name": "Mountain", "quantity": 10, "type": "Basic Land — Mountain", "set": "unf", "collector_number": "243"},
]

out_dir = "/tmp/GatherTest"
os.makedirs(out_dir, exist_ok=True)

try:
    print("Testing MTGO...")
    mtgo_path = Path(out_dir) / "Test.dek"
    export_mtgo_dek(test_cards, mtgo_path)
    print(f"MTGO file created? {mtgo_path.exists()}")
    
    print("Testing Arena...")
    arena_str = generate_arena_clipboard(test_cards)
    print(f"Arena string output: \n{arena_str}")
    
except Exception as e:
    print(f"Exporter Error: {e}")
