# kotoba icon ("Two-Peak Caret")

`generator/mark.ts` holds the geometry and colours; `bun generator/export.ts` (needs `rsvg-convert`) writes `source/*.svg`, `AppIcon.icon/`, `AppIcon.appiconset/` and `MenuBar/*.imageset` next to this file. Copy `AppIcon.icon/` to `App/AppIcon.icon`, `AppIconDev.icon/` to `App/AppIconDev.icon` and the three imagesets into `App/Assets.xcassets`; the app uses those copies. `AppIconDev.icon` is kotoba Dev's icon (the Debug build, `ASSETCATALOG_COMPILER_APPICON_NAME` in project.yml): blue with an amber "DEV" band, so the Dock and ⌘-Tab tell it from the release.
