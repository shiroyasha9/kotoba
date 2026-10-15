// Writes every production asset for the kotoba mark from mark.ts.
// Needs bun and rsvg-convert (Homebrew librsvg). Optional: Xcode's ictool, to render the .icon document for preview.
// Run from anywhere: bun generator/export.ts
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { $ } from "bun";
import {
  DARK,
  LIGHT,
  type Palette,
  appIconSVG,
  caretLayerSVG,
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
const icon = dir("AppIcon.icon");
const assets = dir("AppIcon.icon", "Assets");
writeFileSync(join(assets, "caret.svg"), caretLayerSVG());
writeFileSync(join(assets, "wave.svg"), waveLayerSVG());
writeFileSync(
  join(icon, "icon.json"),
  json({
    "fill-specializations": [{ value: bg(LIGHT) }, { appearance: "dark", value: bg(DARK) }],
    groups: [
      {
        layers: [
          { "fill-specializations": fillSpec(LIGHT.caret, DARK.caret), "image-name": "caret.svg", name: "caret" },
          { "fill-specializations": fillSpec(LIGHT.wave, DARK.wave), "image-name": "wave.svg", name: "wave" },
        ],
        name: "Mark",
        shadow: { kind: "neutral", opacity: 0.5 },
        translucency: { enabled: false, value: 0 },
      },
    ],
    "supported-platforms": { squares: ["macOS"] },
  }),
);

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
  for (const r of ["Default", "Dark", "ClearLight", "TintedDark"])
    await $`${ictool} ${icon} --export-image --output-file ${join(pv, `icon-composer-${r}.png`)} --platform macOS --rendition ${r} --width 512 --height 512 --scale 1`.nothrow();
console.log("exported to", root);
