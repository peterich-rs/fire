# TextureCore

This local package exposes Texture 3.2.0 `AsyncDisplayKit.framework` as a
checked-in XCFramework binary target for the iOS app.

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
