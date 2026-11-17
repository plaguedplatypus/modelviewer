# Model Viewer

Model Viewer is a RuneScape development plugin for inspecting NPCs, Locs, Objs, and raw model assets while trying Seq animations. It opens from the plugin ribbon into a movable window, so the preview and controls stay together.

## Open the viewer

1. Enable **Model Viewer** in the development client. It requires the **PrettyUI** plugin.
2. Open the **Plugins** ribbon, choose **Model Viewer**, then press **Open Viewer**.
3. Close the window when finished. The ribbon button opens it again.

## View fonts

Press **Font Viewer** below **Open Viewer** in the Model Viewer ribbon. This opens a separate window that reads font names and IDs from the active client; it does not use a saved catalog.

Search by exact ID or part of a name, then select a font in the scrollable list. Type your own preview text and press **Update sample** to see it in that font. The preview wraps words to fit its panel and breaks long unspaced strings such as the alphabet sample. Use the **Background** and **Font colour** swatches to change the preview colours; **Reset colours** restores both defaults. Some game fonts contain icons or special glyphs, so ordinary letters may appear blank. Close the window when finished; the ribbon button opens it again.

## Find a model or animation

On the **NPC** tab, use **NPCs** to search for an NPC ID or part of its config name, then select a result to display it. Use **Seq animations** on the same tab to find and apply a Seq to that NPC. Each view remembers its search when you switch between them. Press **Clear animation** to stop the Seq and return to the NPC's still pose. NPC and Seq IDs are checked against the active game cache before use.

On the **Models** tab, use **Model assets** to search for an asset ID or part of its name, then select a result to view that raw model. Use **Seq animations** on the same tab to find and apply a Seq to it. **Clear animation** returns the model to its still pose. A raw model can be a chat head, body part, effect, or other single asset rather than a complete NPC. The API does not expose a model config lookup, so a listed asset may still appear blank if it is missing from the active cache.

On the **Locs** tab, search for scenery by Loc ID or config name. Results omit Locs with no direct model in any supported shape, such as invisible Locs and MultiLoc selectors without their own models. The list fills as the client checks Locs; a broad search may take a moment to finish. Select a Loc to preview its first shape with a model. Use the shape **Prev** and **Next** buttons below the list to see its other forms. The shape name and number appear above those buttons. The **Seq animations** view can apply a Seq to the Loc's models, though an incompatible animation may do nothing.

On the **Objs** tab, search for an item by Obj ID or config name. Select it to see the item's 3D model and display name. An Obj is an item definition, separate from a raw model asset; this preview shows its item model rather than its inventory icon. Use camera distance if an unusually small or large item needs a closer view. You can try a Seq, but most items have no compatible animation.

Each search starts with the full catalog. The viewer builds names from the active client's ID tables when it opens each catalog. Reload the plugin after a game update to refresh those names. Scroll within the result list and use **Prev** and **Next** to move through every match in pages of 500. The asset or Seq shown in the preview is highlighted in gold when its row is visible in the results. Enter an exact ID or part of a name to narrow a large catalog. A search with one result selects it automatically. Some NPC and Obj configs have no visible model. A Seq built for a different skeleton or model rig may leave it still or animate it strangely. Every asset tab remembers its own selected Seq.

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
- **Window size:** Drag an edge or corner of the viewer window to make the model preview larger or smaller. The search and numeric controls stay on the left; framing buttons stay along the preview's lower edge.

The game API does not provide rendered model bounds. NPC and Loc fits use their tile size and any custom picking bounds, so unusual shapes and animations may still need manual zoom or **Adjust Center**.