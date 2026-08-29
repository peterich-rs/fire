# Android ↔ iOS UI / interaction parity

Date: 2026-08-29  
Status: Waves 0–4 landed on Android host UI; remaining polish listed below  
Authority: iOS visual + interaction. Android maps the same product, it does not invent a second Material language.

## Landed (2026-08-27 / 2026-08-29)

- Shared Compose chrome: card rows, icon wells, appearance capsule, empty/error, press bounce, secondary scaffold (`native/android-app/.../core/ui/compose/`).
- Secondary destinations hide the bottom tab bar (iOS secondary stack analogue).
- Profile tab rebuilt as iOS card hub: 我的动态 / 书签 / 历史 / 草稿 / 私信 / 勋章 / 反馈 / 邀请 / LDC / CDK / 设置.
- Public profile uses follow/私信 + 关注/粉丝 + 最近动态 instead of top-topic dump.
- Follow lists, activity timeline, badges + detail, invite links.
- Settings: capsule appearance, DoH child page, developer-tools export, logout, version footer.
- Notification copy aligned to iOS Chinese templates.
- Home scope chrome: leading category drawer, status capsules (分类 / 排序 / 标签 / 清除), child shortcut strip, topic rows with avatar + category/tag chips + metric weight.
- Topic detail: pinned title after header scrolls away; WeChat-style quick-reply bar replaces FAB.
- User card: compact detent, 13pt action row, native profile deep link.
- Search full-screen header with back; notifications/chat lose Material cards/FAB and use canvas list chrome.

## Still open

- Topic-row surge micro-animations and home long-press bookmark editor.
- Topic-detail post-row Texture-level spacing/boost capsule polish.
- Composer / bookmark-editor sheet restyle.
- Shake-to-feedback, OLED fourth appearance segment, widget visual parity.

Login remains the earlier Compose unification surface.
