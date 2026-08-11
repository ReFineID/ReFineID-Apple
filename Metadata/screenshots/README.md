# App Store screenshots

Screenshots are the one part of a submission that cannot live in
`appstore.json`: they are captures of the running app, so they are PNG
files on disk. `asc-release.swift screenshots <ios|macos> <version>`
uploads everything under here.

## Layout

```
Metadata/screenshots/<locale>/<DISPLAY_TYPE>/<name>.png
```

Files upload in filename order, so name them `01.png`, `02.png`, ….
The folder name is the App Store display type, verbatim. A locale with
no folder is skipped; a display type with no PNGs is skipped.

## Display types and pixel sizes

| Platform | `DISPLAY_TYPE`          | Device            | Portrait px |
|----------|-------------------------|-------------------|-------------|
| macOS    | `APP_DESKTOP`           | Mac               | 2880×1800   |
| iOS      | `APP_IPHONE_67`         | iPhone 6.9″/6.7″  | 1290×2796   |
| iPadOS   | `APP_IPAD_PRO_3GEN_129` | iPad Pro 13″/12.9″| 2048×2732   |

macOS accepts 1280×800, 1440×900, 2560×1600 or 2880×1800. iPhone and
iPad want the sizes above (landscape captures use the transposed size).

## Locales

`en-US` is the primary and is required. `fi` and `sv` may reuse the same
PNGs — copy the folders, or leave them out and the store shows the
primary locale's screenshots.

## Capturing

Run the app on the real device or simulator with a card present, take
the shots, and drop them in the matching folder. Nothing here is
generated: the store shows exactly these files.
