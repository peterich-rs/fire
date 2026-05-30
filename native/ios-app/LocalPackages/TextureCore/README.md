# TextureCore

This directory stores the checked-in Texture 3.2.0
`AsyncDisplayKit.xcframework` used by the iOS app.

The Fire target links and embeds
`Artifacts/AsyncDisplayKit.xcframework` directly from
`native/ios-app/project.yml`. It is intentionally not referenced through a
local SwiftPM binary package, because Xcode can report a missing
`AsyncDisplayKit` package product when that local package product is not
resolved in the workspace.

Fire intentionally uses `Texture/Core` only. Do not add `Texture/IGListKit`
because that subspec depends on IGListKit 4.x, and do not add
`Texture/PINRemoteImage` because topic-detail image networking is owned by Nuke.

Regenerate the binary with:

```sh
native/ios-app/scripts/build_texture_xcframework.sh
```

The script archives Texture's upstream `AsyncDisplayKit` scheme for iOS device
and simulator, then writes
`native/ios-app/LocalPackages/TextureCore/Artifacts/AsyncDisplayKit.xcframework`.
