# iOS Marketing Assets

This directory holds App Store screenshots and preview video assets.

Required before App Store submission:

- `screenshots/iPhone6.5/` - iPhone 6.5" screenshots
- `screenshots/iPhone5.5/` - iPhone 5.5" screenshots
- `screenshots/iPad12.9/` - iPad 12.9" screenshots
- `screenshots/iPad11/` - iPad 11" screenshots
- `preview-video/app-preview.mp4` - optional App Preview video

Use real release-candidate screenshots only. Do not commit mock screenshots as final store assets.

After final capture, run the repository validator from the repo root:

```bash
scripts/verify-marketing-assets.sh
```

The validator fails while screenshot folders contain only `.gitkeep`
placeholders, while PNG screenshots are flat single-color placeholders, or while
dimensions cannot be decoded. Screenshot folders must contain regular image
files only; do not add nested screenshot directories or alternate screenshot
asset paths. If an App Preview is shipped, place it at
`preview-video/app-preview.mp4` as a regular MP4 file; otherwise leave the
folder empty except for `.gitkeep` and record the no-ship decision in
`docs/release/release-gate-evidence.md`. Do not add nested preview directories
or alternate preview asset paths.
