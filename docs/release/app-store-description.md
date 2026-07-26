# Fire - App Store Listing Draft

## Name

Fire

## Subtitle

LinuxDo native client

## Promotional Text

A native LinuxDo experience with fast topic browsing, offline cache, home screen widgets, Siri Shortcuts, and dark/OLED themes.

## Keywords

LinuxDo,community,forum,topics,discussion,Fire

## Description

Fire is a native client for the LinuxDo community, rebuilt around native iOS surfaces and a shared Rust core.

Core features:

- Fast home feed and topic detail browsing
- Native topic rows, replies, code blocks, polls, images, and link handling
- Notifications, search, profiles, bookmarks, drafts, and read history
- Offline cache for previously loaded lists and topic detail data
- Home screen widgets for unread count and recent topics
- Siri Shortcuts for unread notifications, search, and profile navigation
- Dark mode, OLED mode, haptics, and native context menus

Fire is an unofficial community client. It communicates with LinuxDo using the user's authenticated session and stores app data locally on the device.

## What's New

Version 2.0 is a native rebuild:

- Shared Rust session, API, model, cache, and orchestration layer
- Native iOS interface with WidgetKit widgets and AppIntents shortcuts
- Native Android interface with RemoteViews widgets
- Offline cache support for core reading flows
- Updated release preparation, privacy, testing, and accessibility materials

## Review Notes

- Login uses a platform WebView so users can complete Cloudflare and LinuxDo authentication in the system-native browser surface.
- Fire does not operate a separate backend service.
- Push-token backend registration is not yet available; current push diagnostics store tokens locally only.
- Privacy policy (public GitHub main): https://github.com/peterich-rs/fire/blob/main/docs/release/privacy-policy.md
- Support: https://github.com/peterich-rs/fire/issues
- Full public URL table: `docs/release/public-urls.md`
- For TestFlight external review, include a demo LinuxDo username/password in the Beta App Review notes (see `testflight-setup.md`).
