# ModHub upload: Mod Reveal

What to enter in the GIANTS ModHub upload form for this mod. Each text box below has a copy button on GitHub.

<img src="icon_512.png" alt="Mod icon" width="160">

**Mod Icon (512x512):** [`icon_512.png`](icon_512.png)

| Field | Value |
|-------|-------|
| Title English | Mod Reveal |
| Title German | Mod Reveal |
| Title French | Mod Reveal |
| Version | `1` `1` `0` `1` |
| Author | DTM Mods, Fennell |
| Manufacturer | Lizard |
| Category 1 | Gameplay |
| Category 2 | Not Set |
| Category 3 | Not Set |

## Title English
```text
Mod Reveal
```

## Title German
```text
Mod Reveal
```

## Title French
```text
Mod Reveal
```

## Description English
```text
Shows every mod and DLC your game is running, with its version, author and file name, and what each mod actually has in your savegame.

Press Left Alt + I to open the list. Tabs:
- Active mods: everything loaded right now, with tags for maps, script mods, mods that don't support multiplayer, unzipped folders and possible duplicates.
- DLC: the DLCs in use.
- Not used: mods in your mods folder that this savegame or server doesn't use.
- Changes: what was updated, added or removed since the last time you played this savegame or server, with a short message on screen after an update.

In game: how many vehicles, pallets, buildings and hand tools from each mod are in this savegame, and how many are yours. Mods that only add shop items and have nothing in the savegame are tagged NOTHING IN GAME.

Select a mod for its mod name, file hash, shop items, scripts, needed mods and description. Type to search; click SORT to sort by name, in game, author, file or load order. Gamepad: LB / RB for tabs, B closes.

On every load the list is written to modSettings/FS25_ModReveal/ModList.txt and ModList.csv, ready to paste into Discord or open in a spreadsheet. On a dedicated server the same files and a summary in the server log show what the server runs.

Only reads; it changes nothing in the game. Works in single player and multiplayer.

Changelog 1.1.0.1:
- The game's HUD no longer shows through the window: it is hidden while Mod Reveal is open and comes back when it closes.
- The window is drawn after everything else, so other mods' overlays don't cover it.
```

## Description German
```text
Zeigt jeden Mod und DLC, den dein Spiel nutzt, mit Version, Autor und Dateiname, und was jeder Mod tatsächlich in deinem Spielstand hat.

Linke Alt + I öffnet die Liste. Reiter:
- Aktive Mods: alles, was gerade geladen ist, mit Markierungen für Karten, Skript-Mods, Mods ohne Multiplayer, entpackte Ordner und mögliche Duplikate.
- DLC: die genutzten DLCs.
- Nicht genutzt: Mods in deinem Mod-Ordner, die dieser Spielstand oder Server nicht nutzt.
- Änderungen: was seit dem letzten Spielen auf diesem Spielstand oder Server aktualisiert, hinzugefügt oder entfernt wurde, mit einer kurzen Meldung nach einem Update.

Im Spiel: wie viele Fahrzeuge, Paletten, Gebäude und Handwerkzeuge jedes Mods in diesem Spielstand sind, und wie viele davon dir gehören. Mods, die nur Shop-Artikel bringen und nichts im Spielstand haben, sind als NICHTS IM SPIEL markiert.

Wähle einen Mod für Modname, Datei-Hash, Shop-Artikel, Skripte, benötigte Mods und Beschreibung. Tippen sucht; SORTIERT ändert die Sortierung nach Name, im Spiel, Autor, Datei oder Ladereihenfolge. Gamepad: LB / RB für Reiter, B schließt.

Bei jedem Laden wird die Liste nach modSettings/FS25_ModReveal/ModList.txt und ModList.csv geschrieben, bereit für Discord oder eine Tabelle. Auf einem dedizierten Server zeigen dieselben Dateien und eine Zusammenfassung im Server-Log, was der Server nutzt.

Liest nur; ändert nichts im Spiel. Funktioniert im Einzelspieler und Multiplayer.

Changelog 1.1.0.1:
- Das HUD des Spiels scheint nicht mehr durch das Fenster: Es wird ausgeblendet, solange Mod Reveal offen ist, und kommt beim Schließen zurück.
- Das Fenster wird als Letztes gezeichnet, damit Anzeigen anderer Mods es nicht verdecken.
```

## Description French
```text
Affiche chaque mod et DLC que votre jeu utilise, avec sa version, son auteur et son nom de fichier, et ce que chaque mod a réellement dans votre partie.

Appuyez sur Alt gauche + I pour ouvrir la liste. Onglets :
- Mods actifs : tout ce qui est chargé, avec des marqueurs pour les cartes, les mods de script, les mods sans multijoueur, les dossiers non compressés et les doublons possibles.
- DLC : les DLC utilisés.
- Non utilisés : les mods de votre dossier mods que cette partie ou ce serveur n'utilise pas.
- Changements : ce qui a été mis à jour, ajouté ou retiré depuis votre dernière session sur cette partie ou ce serveur, avec un court message après une mise à jour.

En jeu : combien de véhicules, palettes, bâtiments et outils à main de chaque mod se trouvent dans cette partie, et combien sont à vous. Les mods qui n'ajoutent que des articles de boutique et n'ont rien dans la partie sont marqués NOTHING IN GAME.

Sélectionnez un mod pour voir son nom, son hash de fichier, ses articles de boutique, ses scripts, les mods requis et sa description. Tapez pour chercher ; cliquez sur SORT pour trier par nom, en jeu, auteur, fichier ou ordre de chargement. Manette : LB / RB pour les onglets, B ferme.

À chaque chargement, la liste est écrite dans modSettings/FS25_ModReveal/ModList.txt et ModList.csv, prête à coller dans Discord ou à ouvrir dans un tableur. Sur un serveur dédié, les mêmes fichiers et un résumé dans le journal du serveur montrent ce que le serveur utilise.

Lecture seule ; ne change rien dans le jeu. Fonctionne en solo et en multijoueur.

Changelog 1.1.0.1 :
- Le HUD du jeu ne transparaît plus à travers la fenêtre : il est masqué tant que Mod Reveal est ouvert et revient à la fermeture.
- La fenêtre est dessinée en dernier, pour que les affichages d'autres mods ne la couvrent pas.
```

## Before uploading

- The mod has no French: the in-game texts exist in English and German only, and modDesc.xml has only English and
  German descriptions. The French text here does not add translations to the mod.
- It ships console commands (`modReveal`, `modRevealExport`, `modRevealChanges`, `modRevealShow`). Your decision
  whether they stay in a ModHub build.
- It writes files to `modSettings/FS25_ModReveal/` (the mod list, and `Changes.txt` for server scripts). ModHub
  allows modSettings, but say so in the description if GIANTS asks.
- Tested in game as a multiplayer client (list, Changes tab, Left Alt + I). The 1.1.0.1 HUD hiding has not been seen
  in game yet.
- No screenshots yet: ModHub needs at least one. Take them in game and put them in `screenshots/`.
