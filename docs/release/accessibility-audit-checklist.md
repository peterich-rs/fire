# Fire Accessibility Audit Checklist

All release candidates must pass this checklist on both iOS and Android before store submission. Record failures with file paths, issue links, and a retest date.

## Screens

- [ ] Login and Cloudflare flow
- [ ] Home feed
- [ ] Category-filtered feed
- [ ] Topic detail
- [ ] Notifications
- [ ] Search
- [ ] Profile
- [ ] Bookmarks
- [ ] Drafts and composer
- [ ] Widgets
- [ ] Developer diagnostics, if exposed in the build

## VoiceOver / TalkBack

- [ ] Focus order follows visual order.
- [ ] Topic rows announce title, category, author/activity, reply count, and unread/cached state where visible.
- [ ] Topic detail posts announce author, timestamp, post number, content, code/image/poll affordances, and available actions.
- [ ] Icon-only buttons have labels.
- [ ] Selected tabs and filters announce selected state.
- [ ] Loading, empty, offline, and error states are announced.
- [ ] Toast/snackbar messages are announced or reachable.
- [ ] Widgets have meaningful labels and deep links.

## Dynamic Type / Font Scale

- [ ] iOS smallest and largest accessibility text sizes do not overlap or hide primary actions.
- [ ] Android largest font scale does not overlap or hide primary actions.
- [ ] Topic rows, metadata, and action bars wrap or truncate intentionally.
- [ ] Composer controls remain reachable.

## Motion And Haptics

- [ ] Reduce Motion disables or simplifies decorative motion.
- [ ] Loading shimmer has a non-animated fallback.
- [ ] Haptics do not fire when system settings indicate reduced feedback should be respected.
- [ ] Navigation and toast transitions remain understandable without animation.

## Contrast And Color

- [ ] Primary text meets 4.5:1 contrast in light, dark, and OLED modes.
- [ ] Secondary text remains legible.
- [ ] Category colors are not the only source of meaning.
- [ ] Warning, success, unread, and disabled states have non-color cues.
- [ ] High contrast modes preserve icons, borders, and selected state.

## Keyboard And Switch Control

- [ ] iPad keyboard focus reaches all main controls.
- [ ] Enter/Space activates focused buttons.
- [ ] Escape/back dismisses modals or returns to the previous screen.
- [ ] Switch Control can navigate the core iOS reading flow.

## Results Log

| Date | Tester | Platform | Device | Screen | Result | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| | | | | | | |

Use exactly the screen and audit category names from this checklist. `Result`
accepts `Pass` for completed release-candidate coverage or `Accepted` for an
explicit waiver with approval/waiver context and a reason, risk, or exception in
`Notes`; use a clear shape such as `Approved by <owner>; reason: <decision>`.
Simulator and emulator rows may be linked as supporting context elsewhere, but
they do not satisfy this log. Tester, device, and notes metadata must not contain
fake/mock/placeholder markers or placeholder URL hosts such as localhost,
`.local`, `.test`, or `.invalid`. Keep exactly one row per platform and screen
or audit category pair; duplicate rows are rejected because they make release
evidence ambiguous.

## Release Rule

Do not mark P4 accessibility complete until the results log covers the release candidate on both platforms and all blocking failures are fixed.

Before marking accessibility evidence complete, run:

```bash
scripts/verify-accessibility-audit.sh
```

The verifier fails until every listed screen and audit category has an iOS and
Android physical-device row with date, tester, device, and `Pass` or `Accepted`
disposition. `Accepted` dispositions must be reasoned waivers, not vague status
notes. `Date` must be a real calendar date in `YYYY-MM-DD` form. Rows with
duplicate platform/screen coverage, missing Markdown table columns, or extra
Markdown table columns are rejected; keep the exact table shape and escape
literal `|` characters in cell text.
