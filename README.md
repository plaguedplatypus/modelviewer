# Model Viewer

Model Viewer is a RuneScape development plugin for inspecting NPCs, trying Seq animations, and viewing raw model assets. It opens from the plugin ribbon into a movable window, so the preview and controls stay together.

## Open the viewer

1. Enable **Model Viewer** in the development client. It requires the **PrettyUI** plugin.
2. Open the **Plugins** ribbon, choose **Model Viewer**, then press **Open Viewer**.
3. Close the window when finished. The ribbon button opens it again.

## Find a model or animation

On the **NPC** tab, use **NPCs** to search for an NPC ID or part of its config name, then select a result to display it. Use **Seq animations** on the same tab to find and apply a Seq to that NPC. Each view remembers its search when you switch between them. Press **Clear animation** to stop the Seq and return to the NPC's still pose. NPC and Seq IDs are checked against the active game cache before use.

On the **Models** tab, use **Model assets** to search for an asset ID or part of its name, then select a result to view that raw model. Use **Seq animations** on the same tab to find and apply a Seq to it. **Clear animation** returns the model to its still pose. A raw model can be a chat head, body part, effect, or other single asset rather than a complete NPC. The API does not expose a model config lookup, so a listed asset may still appear blank if it is missing from the active cache.

Each search starts with the full catalog. Scroll within the result list and use **Prev** and **Next** to move through every match in pages of 500. Enter an exact ID or part of a name to narrow a large catalog. A search with one result selects it automatically. Some NPC configs have no visible model. A Seq built for a different skeleton or raw model rig may leave it still or animate it strangely. The NPC and Models tabs remember their own selected Seq.

## Adjust the view

- **Zoom:** Scroll over the model preview. Scroll up to move closer; scroll down to move back.
- **Camera distance:** Enter a positive number and press **Apply** for an exact view. Larger values move the camera back. Use **Fit model** to return to an estimated starting distance.
- **Rotation:** Drag the model to turn it. **Lock pitch** starts checked, so dragging or applying a yaw angle keeps the current tilt. Uncheck it to tilt by dragging or enter a pitch in degrees. Enter a yaw in degrees and press **Apply** for an exact turn.
- **Position:** Hold **Shift** while dragging the preview to move the NPC or model. Press **Center model** to reset its position. Each tab keeps its own position until another NPC or model is selected.
- **Background:** Click the colour swatch below **Clear animation**, choose a colour, and confirm it in the picker. Press **Reset** to restore the original background. The preview remembers the chosen colour while the viewer is open.
- **Window size:** Drag an edge or corner of the viewer window to make the model preview larger or smaller. The search and camera controls stay on the left.

The game API does not provide rendered model bounds, so **Fit model** estimates framing from the NPC's overlay height or a neutral height for raw assets. Use camera distance when the estimate does not fit the model.

