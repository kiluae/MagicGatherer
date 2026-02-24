# MagicGatherer 3.0 (Qt Edition)

MagicGatherer is a high-performance desktop application designed for Magic: The Gathering players. It streamlines the deckbuilding and proxy generation process by natively integrating Scryfall and EDHREC APIs securely over Python background threads.

## Final Release Version: v3.0

This complete rewrite introduces a robust, multi-threaded PyQt5 infrastructure designed to completely replace the legacy Flutter applications, eliminating crash footprints and significantly improving UI/UX flow.

---

### Features

#### 🛡️ The Stable Foundation
- **API Etiquette:** Strict `time.sleep` throttling and custom `MagicGatherer/3.0.0` User-Agents to prevent Scryfall bans.
- **Persistent State:** Safely stores configurations, padding preferences, and toggle states across application reboots via `config.json`.
- **Global Error Handling:** Application-wide `sys.excepthook` interceptors to catch silent threads and pipe UI crashes directly to `magicgatherer_error.log`.

#### 🧠 Data & Caching Engine
- **Smart Checksum (TTL):** Background paginators download all ~4,200 Scryfall commanders locally (`commanders.json`). The engine relies on a strict 7-day TTL check against the file modification time (`st_mtime`) to skip redundant web requests entirely.
- **Thread-safe Skeleton Loaders:** Asynchronous UI pulsing frames lock layout boundaries while `ImageFetchThread` performs heavy network loading.
- **Local Asset Cache:** Downloads `.jpeg` files directly to `~/.magicgatherer/cache` to permanently secure assets and allow for instantaneous zero-latency image swapping.
- **Heuristic Text Parsing:** Native Oracle-text categorization tags (`Ramp`, `Draw`, `Interaction`, etc.) for uploaded lists.

#### 🎲 The Discovery Deck Roller
*Not sure what to build next? Roll the dice.*
- **Coin-toss Parameters:** Generate dynamic Scryfall queries instantly using visually striking WUBRG toggle blocks, CMC limits, and popularity constraints.
- **Crossfade Hardware:** Lightning-fast `QVariantAnimation` transitions and alpha-channels for gorgeous, fluid 150ms image swapping as you inspect new commanders.

#### 🩺 The Deck Doctor Analytics
*Is your deck heavily reliant on artifacts but missing synergy? Find out instantly.*
- **Standalone Diagnostic Dashboard:** Launch a localized `QMainWindow` to visualize your Mana Curve, Color Pips, and Deck Types (Ramp/Interaction) cleanly via empty space bar graphs.
- **Advanced Cut Engine:** Deep inspection queries across **all** EDHREC sub-categories (Synergy, Top, New) to intelligently filter and recommend non-synergistic bloat in your uploaded deck.
- **Reconnaissence Tooltips:** Full visual integration: Hovering your mouse over any 'Suggested Addition' or 'Cut' uses background threads to render `HQ` frameless QPixmap card overlays near the cursor instantly.

#### 🖨️ Advanced Pre-Press Exporters
*Take your list to the table.*
- **PDF Proxy Engine:** Built-in `PIL` (Pillow) engine for rendering print-ready `.pdf` grids with high-fidelity `900 DPI` physical upscaling.
- **Crop Modules:** Native support for 15px bounding layouts and custom Bleed settings for clean scissor lines.
- **Multi-Format Compilers:** Translate raw deck lists to MTGO XML (`.dek`), MTG Arena Clipboard standard, or CSV.

---

### Requirements

* Python 3.10+
* `PyQt5` (Core GUI Architecture)
* `requests` (API integration)
* `Pillow` (PDF Rendering & Image Manipulation Engine)

### Installation & Run

```bash
git clone https://github.com/yourusername/magicgatherer_qt.git
cd magicgatherer_qt
pip install -r requirements.txt
python src/main.py
```
