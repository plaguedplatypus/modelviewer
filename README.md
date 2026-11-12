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

On the **Locs** tab, search for scenery by Loc ID or config name. Select a Loc to preview the models for its first supported shape. Use the shape **Prev** and **Next** buttons below the list to see its other forms. The shape name and number appear above those buttons. Some Locs are invisible or act as MultiLoc selectors, so they have no direct model to show. The **Seq animations** view can apply a Seq to the Loc's models, though an incompatible animation may do nothing.

On the **Objs** tab, search for an item by Obj ID or config name. Select it to see the item's 3D model and display name. An Obj is an item definition, separate from a raw model asset; this preview shows its item model rather than its inventory icon. Use camera distance if an unusually small or large item needs a closer view. You can try a Seq, but most items have no compatible animation.

Each search starts with the full catalog. The viewer builds names from the active client's ID tables when it opens each catalog. Reload the plugin after a game update to refresh those names. Scroll within the result list and use **Prev** and **Next** to move through every match in pages of 500. Enter an exact ID or part of a name to narrow a large catalog. A search with one result selects it automatically. Some NPC and Obj configs have no visible model. A Seq built for a different skeleton or model rig may leave it still or animate it strangely. Every asset tab remembers its own selected Seq.

To check the loaded list, clear a search box and press **Search**. The status line shows **Client catalog** and the number of names found. You can compare that count or a few IDs with the current `pan` output without waiting for a game update.

## Show an NPC, model, Loc, or Obj over a game tile

On any asset tab, press **Place on tile...**. Right-click a tile in the game view and choose **Place model here**. Repeat this to add more models, including different NPCs, raw models, Locs, and Objs. The button changes to **Cancel placement** while you are choosing a tile. **Remove last** removes the most recently placed model; **Clear all** removes every placed model.

The most recently added placement follows changes to the selected asset, Seq, shape, and rotation on its tab while it remains placed. Earlier placements keep their appearance, so you can select another asset and place it without changing the ones already in the scene. A Loc is placed with all the model parts, scale, and offsets for its chosen shape. Shapes with no direct model cannot be placed; selecting one removes the active placement if it is a Loc.

These are client-side UI models aligned with their selected tiles, not game-world entities. They follow the camera's angle and zoom. When placed models overlap, the one on the nearer tile draws in front. Because each model is a separate UI overlay, intersecting models may still overlap imperfectly, and game objects and characters may not hide them correctly. Each hides when you move more than 40 tiles away and reappears when you return. They use the plugin bottom layer so they stay below plugin windows.

## Adjust the view

- **Zoom:** Scroll over the model preview. Scroll up to move closer; scroll down to move back.
- **Camera distance:** Enter a positive number and press **Apply** for an exact view. Larger values move the camera back. Use **Fit model** to return to an estimated starting distance.
- **Camera height:** Drag the **Height** slider on the right side of the preview. Move it up to raise the camera or down to lower it, from −1500 to +1500 in steps of 25. **+0** uses the usual starting height. Each tab remembers its adjustment while the viewer is open, so a height chosen for Objs stays in place as you browse other Objs.
- **Rotation:** Drag the model to turn it. **Lock pitch** starts checked, so dragging or applying a yaw angle keeps the current tilt. Uncheck it to tilt by dragging or enter a pitch in degrees. Enter a yaw in degrees and press **Apply** for an exact turn.
- **Position:** Hold **Shift** while dragging the preview to move the NPC or model. Press **Center model** to reset its position. Each tab keeps its own position until another NPC or model is selected.
- **Background:** Click the colour swatch below **Clear animation**, choose a colour, and confirm it in the picker. Press **Reset** to restore the original background. The preview remembers the chosen colour while the viewer is open.
- **Window size:** Drag an edge or corner of the viewer window to make the model preview larger or smaller. The search and camera controls stay on the left.

The game API does not provide rendered model bounds, so **Fit model** estimates framing from the NPC's overlay height or a neutral height for raw assets, Locs, and Objs. Use camera distance and height when the estimate does not fit the model.

