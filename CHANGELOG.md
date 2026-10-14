# Changelog

## Unreleased

### Added
- Focus, exposure and white balance are locked while recording.
- A name for each recording, used for its zip and saved in `meta.json`.
- A check right after stopping: how far around the object, height range, unsteady tracking and
  blurry frames, with what to fix; also saved in `meta.json` as `quality`.
- Phase 0 prototype: records the camera image with ARKit's camera position for every frame and
  the points it tracked, and saves each recording as one zip to send to the Mac
  ([format](docs/capture-format.md)).
- Live tracking status, and time, frames, points and unsteady share while recording.
- Captures list with Send (AirDrop and the share sheet) and swipe to delete; captures are also in
  the Files app.
