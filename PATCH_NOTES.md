<p align="center">
  <img src="https://raw.githubusercontent.com/DTM-Mods/.github/main/assets/patch-notes.jpg" alt="Patch notes" width="100%">
</p>

# Patch notes

## 1.1.0.3

- Updated for the current game version: modDesc descVersion 116 (the game build of 2026-10-27; GIANTS TestRunner 0.9.24 accepts only 116).

## 1.1.0.2
- Passes the GIANTS ModHub TestRunner: errors are no longer hidden (they show in the log), and the mod icon is a DXT1 .dds without mipmaps.

## 1.1.0.1
- The game's HUD no longer shows through the window: the F1 help box, the player list and the other HUD parts are hidden while Mod Reveal is open, and come back when it closes (a HUD you had hidden stays hidden).
- The window is drawn after everything else, so other mods' overlays don't cover it either.

## 1.1.0.0
- **In game** column: how many vehicles, pallets, buildings and hand tools from each mod are in your savegame, and how many are yours.
- Mods that only add shop items and have nothing in the savegame are tagged **NOTHING IN GAME**: candidates to remove from the server. **SORT: IN GAME** lists them first; clicking the orange count in the summary does the same.
- The details of a mod say what is in the savegame and which items it puts in the shop.
- German translation.
- Left Alt + I is listed in the F1 help box.
- Gamepad: LB / RB change tabs, the menu extra buttons sort and save the list, B closes. Bind a button to "Mod Reveal: mod list" in the controls to open it.
- `ModList.txt` / `.csv` get the in-game counts (written again 20 seconds after loading, once the savegame's vehicles are there).
- New `Changes.txt` (tab separated) with the changes of the last load, for scripts: the DTM server posts it to Discord.
- Clearer wording ("Store items: 1" instead of "1 store items").

## 1.0.0.1
- Left Alt + I now also works when the game doesn't pass the key on to the mod (the keyboard is watched directly as well).
- New console command `modRevealShow` opens the list without the key.
- The log says whether the key was set up and what opened the list, or which menu stopped it.
- Summary reads "Maps: 1" instead of "1 maps".

## 1.0.0.0
- First version: Left Alt + I shows every active mod and DLC with version, author and file, the mods installed but not used, and what was updated, added or removed since last time. Search, sort, details per mod, and the list written to `modSettings/FS25_ModReveal/ModList.txt` and `ModList.csv` on every load.
