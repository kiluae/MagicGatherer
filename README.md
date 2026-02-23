# MagicGatherer

A high-fidelity MTG deck data fetcher for proxying and deckbuilding. 

MagicGatherer provides unparalleled ease in converting standard Magic: The Gathering decklists from various formats into high-resolution, print-ready datasets natively mapping to Scryfall endpoints.

## Why MagicGatherer?
I built MagicGatherer because I play a *lot* of Historic Brawl on **Magic: The Gathering Arena**. I wanted a seamless way to pull popular commander lists directly from EDHREC and drop them into the digital client, but constantly hit roadblocks. MTG Arena natively rejects imported decks if they contain printings that don't exist digitally. If an EDHREC list had fifty incompatible paper-only cards, Arena would just throw a wall of text and refuse the import. 

Even worse, EDHREC lists don't actively track Basic Lands, and manual spreadsheet scrubbing was exhausting. I needed a tool that could take an EDHREC commander, automatically cross-reference every single card against Scryfall's database to explicitly verify its `game:arena` legality, and silently drop the incompatible cards—while ensuring basic lands bypassed the filters flawlessly. 

Thus, **MagicGatherer** was born. It started as a personal script to bypass Arena's strict import constraints for Historic Brawl and has evolved into a fully-fledged, cross-platform deckbuilding automation suite.

## Features
- **High-Res PNG Downloads:** Scrape the absolute highest quality scans for MPC or home printing.
- **EDHREC Integration:** Automatically pull average composite lists by directly querying commander names.
- **Digital Client Filtering:** Guarantee client-legal output utilizing a persistent API fetching backend perfectly integrated for MTG Arena and MTGO lists, seamlessly routing specific digital card availability.
- **Clean Output Pipelines:** Export localized CSV spreadsheets, JSON dictionaries, or raw _Decklist Textfiles_ tailored for broad ingestion.

## What's New
- **PySide6 Foundation:** Completely rewritten UI architecture utilizing the official Qt for Python bindings (PySide6) to guarantee absolutely flawless executable stability across Windows, macOS, and Linux without missing dynamic libraries.
- **Modal Double-Faced Cards (MDFC) Support:** High-resolution image scraping now automatically identifies dual-sided cards, intelligently downloading the back face dynamically alongside the front face (e.g., `CardName.png` & `CardName (Back).png`).
- **Smart OS Caching:** Blazing fast repeat queries via automated JSON caching securely nested in your home directory (`~/.magicgatherer/cache`)—immune to macOS Application Bundle read-only crashes.
- **Clear Cache Interface:** Manage local disk footprint natively from the GUI with a dedicated click-to-wipe "Clear Cache" function.
- **Fully Automated CI/CD:** Guaranteed 1:1 consistent compiled builds published across Windows, macOS, Ubuntu, and Fedora.

## How to Use
You do not need to install Python! Simply navigate to the [Releases](../../releases) tab and download the pre-compiled executable tailored for your operating system (Windows, macOS, or Linux). 

1. Launch the executable (`MagicGatherer`).
2. Select your Input format (Paste your deck, Browse for a `.txt`, or query an EDHREC Commander).
3. Select your Format (Paper/Arena/MTGO) and Output options.
4. Click **Gather your Magic** and choose a folder!

## Use Cases
* **High-Fidelity Proxying:** Generate high-resolution PNG sets specifically for **MPCFill**, third-party proxy sites, or high-quality home printing.
* **Digital Client Optimization:** Cross-reference MTGA/MTGO filtered metadata before building a deck to ensure your limited Rare/Mythic Wildcards or Event Tix are mathematically prioritized on the most impactful, high-synergy staples over niche inclusions.
* **Brawl Deckbuilding Strategy:** Supplement EDHREC's paper-centric data with Digital Legality Filtering to build optimized client-only lists.
* **AI-Assisted Deck Auditing:** Export your current deck alongside an Arena-filtered EDHREC list to JSON or CSV. Upload them to any LLM (like ChatGPT or Claude) to identify missing engines, optimize mana curves, and receive personalized swap suggestions outside the game.
* **Comparative Data Analysis:** Open exported datasets in Excel or Google Sheets to manually compare synergy, mana curves, and card types between your paper and online collections.
* **Scryfall Search Abstraction:** Skip complex query syntax; type in your Commander's name to immediately fetch all relevant card data and images.

## Future Roadmap
The ultimate vision for **MagicGatherer** is to evolve from a static data fetcher into a fully integrated **Local LLM Contextual Deck Builder**.
By piping this massive aggregated Scryfall and EDHREC JSON data natively into a localized Large Language Model, the application will eventually be capable of analyzing user collections, mathematically optimizing mana curves, and contextually suggesting synergistic card swaps entirely offline.

## Disclaimer
**All rights reserved.** MagicGatherer is an open-source tool for **play-testing purposes only**. I do not own any of the intellectual property, artwork, or card data associated with Magic: The Gathering. All card imagery and data are provided by Scryfall. Please support Wizards of the Coast and the original artists by purchasing official products.

---
*Created by **yuhidev***  
*Open Source - Feel free to clone and contribute.*
