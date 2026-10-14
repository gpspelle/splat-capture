# Notes for coding agents

- The app is generated with XcodeGen from `project.yml`; never commit `SplatCapture.xcodeproj`.
- Code that doesn't need a camera goes in `CaptureKit/` and gets a test in `CaptureKit/Tests`.
- `docs/capture-format.md` is a contract with Splat Studio (`src/splat_studio/capture.py` there).
  Change both in step, and bump `version` in `meta.json` for anything a reader must know about.
- Keep the README current in English and Portuguese, and add a line to `CHANGELOG.md` for
  anything a user sees.
- CI (`.github/workflows/build.yml`) must stay green: CaptureKit tests and an unsigned build.
