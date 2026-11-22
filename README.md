<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-header.jpg" alt="DTM Mods by PropaineX & Fennell" width="100%"></a>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/icons/FS25_ModReveal.png" alt="Mod Reveal icon" width="128">
</p>

<h1 align="center">Mod Reveal</h1>

<p align="center">
  <img src="https://img.shields.io/badge/Farming%20Simulator-25-2E6B4F" alt="Farming Simulator 25">
  <a href="https://github.com/DTM-Mods/FS25_ModReveal/releases/latest"><img src="https://img.shields.io/github/v/release/DTM-Mods/FS25_ModReveal?label=version&color=D9A441" alt="Latest version"></a>
  <a href="https://github.com/DTM-Mods"><img src="https://img.shields.io/badge/DTM-Mods-143326" alt="DTM Mods"></a>
</p>

<p align="center">
  <b>Shows every mod your game runs, with its version.</b><br>
  <sub>by Fennell</sub>
</p>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/features.jpg" alt="Features" width="100%">
</p>

Press **Left Alt + I** in game.

- **Active mods**: every loaded mod with version, author and file name. Tags show maps, script mods, mods that don't support multiplayer (**NO MP**), unzipped folders (**FOLDER**, multiplayer only takes zips) and possible duplicates (two active mods with the same name).
- **DLC**: the DLCs in use.
- **Not used**: mods in your mods folder that this savegame or server doesn't load.
- **Changes**: what was **updated**, **added** or **removed** since you last played this savegame or server, including "same version, new file" (a rebuilt zip). After a change you get a short message on screen when the game starts.
- **In game**: how many vehicles, pallets, buildings and hand tools from each mod are in your savegame (and how many are yours). Mods that only add shop items and have nothing in the savegame are tagged **NOTHING IN GAME**: candidates to remove from the server. **SORT: IN GAME** lists them first.
- **Details** of the selected mod: mod name, file hash (the one the server compares when you join), number of scripts, specializations and store items, the mods it needs, what it puts in the shop, its descVersion and the start of its description.
- **Search** by just typing (name, author, file or version). **SORT** by name, author, file or load order.
- **Mod list files**: on every load the list is written to `modSettings/FS25_ModReveal/ModList.txt` (lined up, ready to paste into Discord) and `ModList.csv` (spreadsheet). **SAVE LIST** writes them again.
- **Dedicated server**: the same files are written on the server, and the server log gets a summary line plus every change since the last start, starting with `[ModReveal]`. `Changes.txt` lists the changes of the last start for scripts; the DTM server posts it to Discord (`announce-mod-changes.ps1` in dtm-server).
- **English and German**, Left Alt + I listed in the F1 help box, gamepad buttons in the window (LB / RB tabs, B closes; bind a button to "Mod Reveal: mod list" to open it).

Keys while the list is open: Left / Right change the tab, Up / Down (hold to run) or the mouse wheel select, Esc clears the search and then closes. Click SORT for name, in game, author, file or load order.

Console: `modReveal` (the list), `modRevealExport` (write the files), `modRevealChanges` (what changed), `modRevealShow` (open the list).

It only reads; it changes nothing in the game.

<!-- dtm-screenshots -->

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/screenshots.jpg" alt="Screenshots" width="100%">
</p>

<p align="center">
  <img src="screenshots/2.jpg" alt="Left Alt + I: every mod at a glance, with author, file and what each mod puts in this savegame; updated mods are tagged" width="100%">
</p>

<p align="center">
  <img src="screenshots/3.jpg" alt="Sort by what is in the game: mods with nothing in this savegame are marked, those could be removed" width="49%">
  <img src="screenshots/5.jpg" alt="What changed since last time: new, updated and removed mods since you last played this savegame" width="49%">
</p>

<p align="center">
  <img src="screenshots/4.jpg" alt="DLC too: every active DLC and how much of it is in your savegame" width="49%">
</p>

<!-- /dtm-screenshots -->

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/installation.jpg" alt="Installation" width="100%">
</p>

Download `FS25_ModReveal.zip` from the [latest release](https://github.com/DTM-Mods/FS25_ModReveal/releases/latest) and put it in `Documents/My Games/FarmingSimulator2025/mods`, without unzipping or renaming it. In multiplayer, install it on the server and on every player's game.

See [PATCH_NOTES.md](PATCH_NOTES.md) for what changed in each version.

<details>
<summary><b>For developers</b></summary>

- `scripts/ModReveal.lua`: reads the mod list (`g_modManager:getActiveMods()`, `getMods()` for the unused ones, each active mod's modDesc.xml for the rest), change tracking (`modSettings/FS25_ModReveal/lastSeen_<savegameN | server_name>.xml`), the files, log and console.
- `scripts/ModRevealDisplay.lua`: the window, drawn with `drawFilledRect` / `renderText` in its own input context (same scheme as Monthly Expense Sheet).
- `translations/l10n_en.xml`, `l10n_de.xml`: all texts.
- In game: `ModReveal.computeUsage()` counts `g_storeManager:getItems()`, `vehicleSystem.vehicles`, `placeableSystem.placeables` and `handToolSystem.handTools` by `.customEnvironment` (the mod they came from), on every open and 20 s after loading.
- Build: `python -I tools\build_zip.py dist\FS25_ModReveal.zip` (forward-slash paths, checks every entry).
- Test: `python tests/test_offline.py` runs both scripts in `lupa` with engine stubs (needs `pip install lupa`).
- Icon: `_brand/tools/make_icons.py <brand> <work> modReveal`, then GIANTS `textureTool.exe icon_ModReveal.png` makes the .dds.

</details>

<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/license.jpg" alt="License" width="100%">
</p>

MIT, see [LICENSE](LICENSE).

---

<p align="center">
  <a href="https://github.com/DTM-Mods"><img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/dtm-intro.gif" alt="DTM Mods by PropaineX & Fennell" width="420"></a><br>
  <sub>Part of <a href="https://github.com/DTM-Mods">DTM Mods</a> (Designed To Manage) by PropaineX & Fennell</sub><br><br>
  <a href="https://ko-fi.com/dtmmods"><img src="https://img.shields.io/badge/Ko--fi-support%20DTM%20Mods-1F4D3A?logo=kofi&logoColor=F4F1E8" alt="Support DTM Mods on Ko-fi"></a>
  <a href="https://www.paypal.com/donate/?business=dtmmods%40gmail.com&amp;no_recurring=0&amp;item_name=DTM+Mods&amp;currency_code=USD"><img src="https://img.shields.io/badge/PayPal-donate-1F4D3A?logo=paypal&logoColor=F4F1E8" alt="Donate to DTM Mods with PayPal"></a><br>
  <a href="https://www.youtube.com/@DTMMods"><img src="https://img.shields.io/badge/YouTube-videos-1F4D3A?logo=youtube&logoColor=F4F1E8" alt="DTM Mods on YouTube"></a>
  <a href="https://dtmmods.itch.io"><img src="https://img.shields.io/badge/itch.io-our%20mods-1F4D3A?logo=itchdotio&logoColor=F4F1E8" alt="DTM Mods on itch.io"></a>
  <a href="https://www.kingmods.net/en/profile/dtmmods"><img src="https://img.shields.io/badge/KingMods-our%20mods-1F4D3A" alt="DTM Mods on KingMods"></a>
</p>
