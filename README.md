# Model Viewer

Model Viewer is a RuneScape development plugin for inspecting NPCs, Locs, Objs, and raw model assets while trying Seq animations. It opens from the plugin ribbon into a movable window, so the preview and controls stay together.

## Open the viewer

1. Enable **Model Viewer** in the development client with **PrettyUI 1.3.0** installed.
2. Open the **Plugins** ribbon, choose **Model Viewer**, then press **Open Viewer**.
3. Close the window when finished. The ribbon button opens it again.

## View fonts

Press **Font Viewer** below **Open Viewer** in the Model Viewer ribbon. This opens a separate window that reads font names and IDs from the active client; it does not use a saved catalog.

Search by exact ID or part of a name, then select a font in the scrollable list. Type your own preview text and press **Update sample** to see it in that font. The preview wraps words to fit its panel and breaks long unspaced strings such as the alphabet sample. Use the **Background** and **Font colour** swatches to change the preview colours; **Reset colours** restores both defaults. Some game fonts contain icons or special glyphs, so ordinary letters may appear blank. Close the window when finished; the ribbon button opens it again.

## Find a model or animation

Search for an asset by ID or name on the left and browse animations beside it. Camera, rotation, and placement controls sit below the animation list. The preview is on the right. Each asset tab remembers its searches.

On the **NPC** tab, select a result to display it. If the NPC has a base animation set, its name and ID appear below the still preview. The client API exposes the set's identity but gives the plugin no way to read or play its individual animations. Use **All animations** to find and apply a Seq manually. Press **Clear animation** to return to the still preview. NPC and Seq IDs are checked against the active game cache before use.

On the **Models** tab, select a raw model from the left list and use **All animations** to find and apply a Seq to it. **Clear animation** returns the model to its still pose. A raw model can be a chat head, body part, effect, or other single asset rather than a complete NPC. The API does not expose a model config lookup, so a listed asset may still appear blank if it is missing from the active cache.

On the **Locs** tab, search for scenery by Loc ID or config name. Results omit Locs with no direct model in any supported shape, such as invisible Locs and MultiLoc selectors without their own models. The list fills as the client checks Locs; a broad search may take a moment to finish. Select a Loc to preview its first shape with a model and play its default animation if it has one. Use the shape **Prev** and **Next** buttons below the list to see its other forms. Choose **Configured** to see the selected Loc's animations, or **All** to try a Seq from the full catalog. **Clear animation** stops playback while that Loc stays selected.

On the **Objs** tab, search for an item by Obj ID or config name. Select it to see the item's 3D model and display name. 

An Obj is an item definition, separate from a raw model asset; this preview shows its item model rather than its inventory icon. Use camera distance if an unusually small or large item needs a closer view.

On **Models** and **Objs**, open **Filters** and uncheck any groups you want to hide from name and exact-ID searches. An unchecked group hides its entries even if they also match a checked group. **Other** controls entries outside the named groups. All filters start checked. Search and placement status appears below the preview.

To define a filter in `src/catalogCategories.lua`, use literal config-name fragments. `prefixes = { "REWARD_" }` matches the start, `suffixes = { "_INV" }` matches the end, and `contains = { "_REWARD_" }` matches a fragment between underscores. `tokens = { "REWARD" }` matches a whole underscore-separated part at any position. A group matches when any of its rules match.

Asset rows show the in-game name when available and use the client name as a fallback. The selected asset's client name appears below the preview. Searches still match IDs or client names. 

To check the loaded list, clear a search box and press **Search**. The status line shows **Client catalog** and the number of names found. You can compare that count or a few IDs with the current `pan` output without waiting for a game update.

## Show an NPC, model, Loc, or Obj over a game tile

On any asset tab, press **Place on tile...**. A cyan outline marks the tile under your cursor. Right-click that tile in the game view and choose **Place model here**. Repeat this to add more models, including different NPCs, raw models, Locs, and Objs. The button changes to **Cancel placement** while you are choosing a tile. **Remove last** removes the most recently placed model; **Clear all** removes every placed model. To remove one from the game view, right-click its original tile and choose **Remove model here**. If several models share a tile, repeat the action to remove them from newest to oldest.

The most recently added placement follows changes to the selected asset, Seq, shape, and model rotation on its tab while it remains placed. Earlier placements keep their appearance, so you can select another asset and place it without changing the ones already in the scene. A Loc is placed with all the model parts, scale, and offsets for its chosen shape. Shapes with no direct model cannot be placed; selecting one removes the active placement if it is a Loc.

## Adjust the view

- **Zoom:** Scroll over the model preview. Scroll up to move closer; scroll down to move back.
- **Camera distance:** Enter a positive number and press **Apply** for an exact view. Larger values move the camera back. **Fit model** estimates a distance and center for NPCs and Locs using their available size information. For raw Models and Objs, it returns to a neutral starting view.
- **Adjust Center:** Drag the slider on the right side of the preview. Move it up to raise the view center or down to lower it, from −1500 to +1500 in steps of 25. **+0** uses the starting center, or the estimated center after pressing **Fit model**. Each tab remembers its adjustment while the viewer is open.
- **Turn the model:** Drag across the preview. Left or right changes yaw; up or down changes pitch in the same screen direction even after a 180° turn. Rotation responds faster to mouse movement. **Lock pitch** starts checked; uncheck it to allow vertical rotation. The preview model and the active placed model from the same tab turn together. Earlier placements keep their angles. Each tab remembers its model angle while the viewer is open.
- **Exact rotation:** Enter model yaw and pitch in degrees and press **Apply**. The boxes update as you drag. **Lock pitch** also prevents typed pitch changes, so uncheck it before entering a new pitch.
- **Reset preview:** Press the refresh icon button at the lower right to restore the current tab's starting model angle, zoom, center adjustment, and pan. If the active placed model came from the same tab, its rotation resets too. The selected asset and animation stay selected.
- **Position:** Hold **Shift** while dragging the preview to move the NPC or model on screen. Pan follows the screen direction as the model turns. Press **Center** to reset its position. Each tab keeps its own position until another NPC or model is selected.
- **Background:** Click the colour swatch below **Clear animation**, choose a colour, and confirm it in the picker. Press **Reset** to restore the original background. The preview remembers the chosen colour while the viewer is open.
- **Move and resize the window** by dragging the title bar or an edge or corner, including in Classic mode. The asset list grows vertically with the window and the preview uses the available space on the right.

The game API does not provide rendered model bounds. NPC and Loc fits use their tile size and any custom picking bounds, so unusual shapes and animations may still need manual zoom or **Adjust Center**.
