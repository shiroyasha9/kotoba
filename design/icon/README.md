# kotoba icon ("Two-Peak Caret")

`generator/mark.ts` holds the geometry and colours; `bun generator/export.ts` (needs `rsvg-convert`) writes `source/*.svg`, `AppIcon.icon/`, `AppIcon.appiconset/` and `MenuBar/*.imageset` next to this file. Copy `AppIcon.icon/` to `App/AppIcon.icon` and the three imagesets into `App/Assets.xcassets`; the app uses those copies.
