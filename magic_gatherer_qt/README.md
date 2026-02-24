# MagicGatherer v3.1.1 (Qt Edition)

MagicGatherer is a high-performance desktop application for Magic: The Gathering players. It streamlines deckbuilding and proxy generation by natively integrating the Scryfall and EDHREC APIs over Python background threads — with a full desktop GUI **and** a standalone terminal (TUI) interface.

---

## What's New in v3.1.1

| Feature | Details |
|---|---|
| 🧠 **Expanded EDHREC Engine** | Up to **500 suggestions** pulled from every EDHREC category (Top, Synergy, New, Lands, Creatures…) |
| 🏷️ **Functional Symbols** | Recommendations now show `[D]` Draw, `[R]` Removal, `[M]` Ramp, `[L]` Land, `[P]` Protection tags |
| 🖼️ **Hover Tooltips** | Mouse-over card previews in the **Deck Doctor** and **Discovery** windows (500ms debounce) |
| 💻 **TUI Restored** | Terminal interface lives at `src/tui/app.py` and is launchable via the footer button |
| 🚀 **macOS Terminal Spawn** | "Launch TUI" now correctly opens a new Terminal.app window via `osascript` |
| 🔧 **Shared Logic Core** | `src/logic.py` decouples gathering/exporting so both the GUI and TUI use the same engine |
| 🛡️ **ARM64 Crash Safety** | Null `QPixmap` guards prevent `SIGABRT` crashes during rapid hover on Apple Silicon |

---

## Features

### 🛡️ Stable Foundation
- **API Etiquette** — Strict 100ms throttling + `MagicGatherer/3.0.0` User-Agent to prevent Scryfall bans.
- **Persistent Config** — Toggles, padding, paper size, and format preferences saved via `~/.magicgatherer/config.json`.
- **Global Error Handler** — `sys.excepthook` pipes all silent thread crashes to `magicgatherer_error.log`.
- **Export Logs Button** — Export the error log to disk from inside the app.

### 🧠 Data & Caching Engine
- **Smart Commander TTL** — Downloads all ~4,200 Scryfall commanders to a local `commanders.json` with a 7-day auto-refresh.
- **Thread-safe Skeletons** — Async pulsing frames lock layout while `ImageFetchThread` loads images in the background.
- **Local Asset Cache** — Card images cached to `~/.magicgatherer/cache` for zero-latency swapping. Clear via footer button.

### 🎲 Discovery Deck Roller
- **WUBRG Toggles** — Filter random commanders by color identity with visual WUBRG blocks.
- **Crossfade Hardware** — `QVariantAnimation` / alpha-channel transitions for fluid 150ms image swapping.
- **Dual Send Actions** — "Send to Deck Doctor 🩺" or "Send to Exporter 🖨️" from any discovered commander.

### 🩺 Deck Doctor Analytics
- **Standalone Dashboard** — Dedicated `QMainWindow` with Mana Curve, Color Pips, and Type Distribution graphs.
- **EDHREC Comparison Engine** — Compares your decklist against all EDHREC sub-categories for the detected commander.
- **Functional Symbols** — Recommendations display category context: `[D]` Draw · `[R]` Removal · `[M]` Ramp · `[L]` Land · `[P]` Protection · `[♟]` Creature · `[✦]` Utility
- **Hover Previews** — Mousing over any suggested card pops a full HQ card image in a frameless overlay window.
- **Double-click to Add** — Double-click any recommendation to instantly append it to the decklist editor.

### 💻 Terminal UI (TUI)
- **Textual Dashboard** — Full deckbuilding workflow in a beautiful terminal interface (`textual` library).
- **Shared Logic** — Powered by `src/logic.py`, the same engine used by the desktop GUI.
- **Launch from GUI** — Click **"Launch TUI"** in the bottom-left footer; spawns a new Terminal window on macOS.
- **Or run directly:**
  ```bash
  cd magic_gatherer_qt
  PYTHONPATH=src python3 src/tui/app.py
  ```

### 🖨️ Advanced Proxy Exporter
- **PDF Engine** — Pillow-based renderer for print-ready `.pdf` grids at configurable DPI (300–900+).
- **Paper Sizes** — US Letter, Legal, Tabloid, A4, A3, A2, A1.
- **Cut Guides** — Corner marks, full outlines, or edge lines; configureable via the ⚙️ Advanced Layout Settings dialog.
- **Bleed Edge** — Adjustable mm bleed for professional print shops.
- **Multi-format** — MTGO `.dek` XML, MTG Arena clipboard string, CSV, JSON.

---

## Requirements

```
Python 3.10+
PyQt5
requests
Pillow
textual >= 0.52.0
```

---

## Installation & Run

```bash
git clone https://github.com/kiluae/MagicGatherer.git
cd MagicGatherer/magic_gatherer_qt
pip install -r requirements.txt
python src/main.py
```

### Headless Terminal Edition (TUI)

```bash
PYTHONPATH=src python3 src/tui/app.py
```

Or click **"Launch TUI"** in the bottom-left footer of the desktop app.

---

## Project Structure

```
magic_gatherer_qt/
├── src/
│   ├── main.py          # Qt GUI entry point & MainWindow
│   ├── logic.py         # Shared gathering & exporting engine (GUI + TUI)
│   ├── deck_doctor.py   # Deck Doctor analytics window
│   ├── discovery.py     # Discovery Deck Roller widget
│   ├── ui_core.py       # Reusable UI components & HoverPreviewManager
│   ├── exporters.py     # PDF, CSV, JSON, MTGO, Arena exporters
│   ├── image_fetcher.py # Background image downloader & cache
│   ├── api.py           # Rate-limited HTTP wrapper
│   └── tui/
│       └── app.py       # Textual terminal interface
├── requirements.txt
└── README.md
```

---

*Built by yuhidev*
