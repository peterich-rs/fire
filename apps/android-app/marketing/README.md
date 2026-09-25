# Android Marketing Assets

This directory holds Play Store screenshots and graphic assets.

Required before Play Store submission:

- `screenshots/phone/` - phone screenshots
- `screenshots/tablet7/` - 7" tablet screenshots
- `screenshots/tablet10/` - 10" tablet screenshots
- `feature-graphic.png` - 1024x500 Play Store feature graphic

Use real release-candidate screenshots and an approved feature graphic only. Do not commit mock screenshots as final store assets.

After final capture, run the repository validator from the repo root:

```bash
scripts/verify-marketing-assets.sh
```

The validator fails while screenshot folders contain only `.gitkeep`
placeholders or `feature-graphic.png` is missing. The feature graphic must use
PNG content with exact `1024x500` dimensions and non-flat pixel content before
Play Store media evidence can be marked complete. PNG screenshots must also
contain more than a single flat color. Screenshot folders must contain regular
image files only; do not add nested screenshot directories or alternate
screenshot asset paths.
