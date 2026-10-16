// Writes every production asset for the kotoba mark from mark.ts.
// Needs bun and rsvg-convert (Homebrew librsvg). Optional: Xcode's ictool, to render the .icon document for preview.
// Run from anywhere: bun generator/export.ts
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { $ } from "bun";
import {
  DARK,
  DEV_BAND,
  DEV_DARK,
  DEV_LIGHT,
  LIGHT,
  type Palette,
  appIconSVG,
  caretLayerSVG,
  devAppIconSVG,
  devBandLayerSVG,
  devLettersLayerSVG,
  glyphAttentionSVG,
  glyphCaretOffSVG,
  glyphIdleSVG,
  waveLayerSVG,
} from "./mark";

const root = join(import.meta.dir, "..");
const dir = (...p: string[]) => {
  const d = join(root, ...p);
  mkdirSync(d, { recursive: true });
  return d;
};
const json = (v: unknown) => `${JSON.stringify(v, null, 2)}\n`;

// ---------- sources ----------
const src = dir("source");
const sources: Record<string, string> = {
  "app-icon-light.svg": appIconSVG(LIGHT),
  "app-icon-dark.svg": appIconSVG(DARK),
  "app-icon-dev-light.svg": devAppIconSVG(DEV_LIGHT),
  "app-icon-dev-dark.svg": devAppIconSVG(DEV_DARK),
  "layer-wave.svg": waveLayerSVG(),
  "layer-caret.svg": caretLayerSVG(),
  "menubar-idle.svg": glyphIdleSVG(),
  "menubar-caret-off.svg": glyphCaretOffSVG(),
  "menubar-attention.svg": glyphAttentionSVG(),
};
for (const [f, s] of Object.entries(sources)) writeFileSync(join(src, f), s);

// ---------- AppIcon.appiconset: one PNG per macOS size and scale. Light only: macOS asset catalogs take no dark variant; AppIcon.icon carries it. ----------
const set = dir("AppIcon.appiconset");
const images: { size: number; scale: 1 | 2 }[] = [16, 32, 128, 256, 512].flatMap((size) => [
  { size, scale: 1 as const },
  { size, scale: 2 as const },
]);
for (const { size, scale } of images) {
  const px = size * scale;
  const name = `icon_${size}x${size}${scale === 2 ? "@2x" : ""}.png`;
  await $`rsvg-convert -w ${px} -h ${px} ${join(src, "app-icon-light.svg")} -o ${join(set, name)}`;
}
writeFileSync(
  join(set, "Contents.json"),
  json({
    images: images.map(({ size, scale }) => ({
      filename: `icon_${size}x${size}${scale === 2 ? "@2x" : ""}.png`,
      idiom: "mac",
      scale: `${scale}x`,
      size: `${size}x${size}`,
    })),
    info: { author: "xcode", version: 1 },
  }),
);

// ---------- AppIcon.icon (Icon Composer document: light and dark appearances, system masks and adds Liquid Glass) ----------
const srgb = (hex: string) => {
  const n = (i: number) => (Number.parseInt(hex.slice(i, i + 2), 16) / 255).toFixed(5);
  return `srgb:${n(1)},${n(3)},${n(5)},1.00000`;
};
const fillSpec = (light: string, dark: string) => [{ value: { solid: srgb(light) } }, { appearance: "dark", value: { solid: srgb(dark) } }];
const bg = (p: Palette) => ({ "linear-gradient": [srgb(p.bg1), srgb(p.bg2)] });
const mark = (light: Palette, dark: Palette) => ({
  layers: [
    { "fill-specializations": fillSpec(light.caret, dark.caret), "image-name": "caret.svg", name: "caret" },
    { "fill-specializations": fillSpec(light.wave, dark.wave), "image-name": "wave.svg", name: "wave" },
  ],
  name: "Mark",
  shadow: { kind: "neutral", opacity: 0.5 },
  translucency: { enabled: false, value: 0 },
});
// AppIcon.icon for the release; AppIconDev.icon for kotoba Dev, the Debug build (project.yml), with the "DEV" band.
for (const [name, light, dark, isDev] of [
  ["AppIcon.icon", LIGHT, DARK, false],
  ["AppIconDev.icon", DEV_LIGHT, DEV_DARK, true],
] as const) {
  const icon = dir(name);
  const assets = dir(name, "Assets");
  writeFileSync(join(assets, "caret.svg"), caretLayerSVG());
  writeFileSync(join(assets, "wave.svg"), waveLayerSVG());
  const dev = {
    layers: [
      { "fill-specializations": fillSpec(DEV_BAND.letters, DEV_BAND.letters), "image-name": "dev-letters.svg", name: "letters" },
      { "fill-specializations": fillSpec(DEV_BAND.band, DEV_BAND.band), "image-name": "dev-band.svg", name: "band" },
    ],
    name: "Dev",
    translucency: { enabled: false, value: 0 },
  };
  if (isDev) {
    writeFileSync(join(assets, "dev-band.svg"), devBandLayerSVG());
    writeFileSync(join(assets, "dev-letters.svg"), devLettersLayerSVG());
  }
  writeFileSync(
    join(icon, "icon.json"),
    json({
      "fill-specializations": [{ value: bg(light) }, { appearance: "dark", value: bg(dark) }],
      groups: isDev ? [dev, mark(light, dark)] : [mark(light, dark)],
      "supported-platforms": { squares: ["macOS"] },
    }),
  );
}

// ---------- menu-bar template images: vector PDF at 18 x 18 pt ----------
const glyphs: Record<string, string> = { MenuBarIdle: "menubar-idle", MenuBarListening: "menubar-caret-off", MenuBarAttention: "menubar-attention" };
for (const [setName, file] of Object.entries(glyphs)) {
  const d = dir("MenuBar", `${setName}.imageset`);
  // 72 dpi makes 18 SVG px into 18 PDF pt.
  await $`rsvg-convert -f pdf --dpi-x 72 --dpi-y 72 ${join(src, `${file}.svg`)} -o ${join(d, `${file}.pdf`)}`;
  writeFileSync(
    join(d, "Contents.json"),
    json({
      images: [{ filename: `${file}.pdf`, idiom: "universal" }],
      info: { author: "xcode", version: 1 },
      properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
    }),
  );
}

// ---------- previews ----------
const pv = dir("preview");
await $`rsvg-convert -w 1024 -h 1024 ${join(src, "app-icon-dark.svg")} -o ${join(pv, "app-icon-dark-1024.png")}`;
for (const file of Object.values(glyphs))
  for (const px of [16, 18, 32, 36]) await $`rsvg-convert -w ${px} -h ${px} ${join(src, `${file}.svg`)} -o ${join(pv, `${file}-${px}.png`)}`;
const ictool = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool";
if (existsSync(ictool))
  for (const name of ["AppIcon", "AppIconDev"])
    for (const r of ["Default", "Dark", "ClearLight", "TintedDark"])
      await $`${ictool} ${join(root, `${name}.icon`)} --export-image --output-file ${join(pv, `${name}-${r}.png`)} --platform macOS --rendition ${r} --width 512 --height 512 --scale 1`.nothrow();
console.log("exported to", root);
