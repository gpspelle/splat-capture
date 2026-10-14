# Capture package format (version 1)

What Splat Capture writes and Splat Studio reads. One recording is one zip:

```
capture_2026-10-14_153012.zip
└── capture_2026-10-14_153012/
    ├── video.mov       the camera image, exactly as ARKit saw it
    ├── frames.jsonl    one line per video frame: where the camera was
    ├── points.json     3D points ARKit tracked, with their colours
    └── meta.json       what recorded it and how
```

A reader should find the folder that holds `frames.jsonl` (the zip may or may not have the
folder level) and ignore files it doesn't know.

## video.mov

HEVC, about 30 frames per second, usually 1920 × 1440. It is the **sensor's landscape image**,
whatever way the phone was held, and has no rotation tag: a capture filmed upright looks
sideways in a video player. That keeps the pixels and the camera numbers in `frames.jsonl` in the
same frame of reference. To show it upright, turn the image (and the camera) using the world's
up direction; Splat Studio does this.

Every frame in the video has exactly one line in `frames.jsonl`, in the same order: line N is
video frame N (counting from 0). A camera frame that couldn't be encoded in time is left out of
both.

## frames.jsonl

One JSON object per line:

| Key | Meaning |
|---|---|
| `i` | frame number in the video, from 0 |
| `t` | seconds since the first frame (the frame's time in the video) |
| `pose` | camera-to-world matrix, 16 numbers, **row-major** |
| `K` | `[fx, fy, cx, cy]` in pixels of the recorded image |
| `tracking` | `normal`, `notAvailable`, or `limited-<reason>`: `limited-initializing`, `limited-excessiveMotion`, `limited-insufficientFeatures`, `limited-relocalizing` |

```json
{"i":0,"t":0,"pose":[0.99,0.01,-0.02,0.03, ...],"K":[1446.2,1446.2,958.1,721.4],"tracking":"limited-initializing"}
```

Axes are ARKit's:

- **World**: metres, y points up (against gravity), x and z level. The origin is where the phone
  was when the session started.
- **Camera**: x to the right of the recorded image, y up in the image, z out of the screen
  towards the person (the camera looks along −z).

To get a COLMAP / OpenCV camera (x right, y down, z forward), flip the camera's y and z axes:
`R_colmap = R_arkit · diag(1, −1, −1)`, keeping the position.

Frames whose `tracking` isn't `normal` have less reliable poses; Splat Studio leaves them out
when it can.

## points.json

```json
{"points": [{"x": 0.12, "y": -0.30, "z": -0.85, "r": 140, "g": 120, "b": 98, "seen": 6}, ...]}
```

Points ARKit tracked (its `rawFeaturePoints`), in world coordinates, sampled every 5th frame.
`seen` is the number of sampled frames the point was in; only points seen at least twice are
kept. Colours come from the video at the point's position. Splat Studio uses them as the
starting point cloud for training.

## meta.json

```json
{
  "format": "splat-capture", "version": 1,
  "app": "0.1.0", "device": "iPhone15,2", "system": "17.5",
  "started": "2026-10-14T13:30:12Z",
  "width": 1920, "height": 1440, "fps": 30,
  "frames": 1834, "duration": 61.1, "points": 5210, "lidar": true
}
```

`format` and `version` identify the package; a reader should refuse a `version` it doesn't
know. A later version may add files (depth maps, for example) and keys.
