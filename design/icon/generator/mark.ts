// kotoba mark "Two-Peak Caret": a voice wave with two peaks settles into a flat line and stops at a text caret.
// All art is drawn here as plain SVG geometry; no fonts, no raster sources.

export type P = [number, number];
export type Palette = { bg1: string; bg2: string; wave: string; caret: string };

export const LIGHT: Palette = { bg1: "#FAFAF7", bg2: "#E6E8E3", wave: "#1B1E24", caret: "#E8553D" };
export const DARK: Palette = { bg1: "#20232A", bg2: "#0F1115", wave: "#EEF0F4", caret: "#FF6B4A" };
// kotoba Dev (the Debug build): blue, with an amber "DEV" band, so the Dock and ⌘-Tab tell it from the release.
export const DEV_LIGHT: Palette = { bg1: "#3B82F6", bg2: "#1D4ED8", wave: "#FFFFFF", caret: "#FFB020" };
export const DEV_DARK: Palette = { bg1: "#1E3A8A", bg2: "#0B1A45", wave: "#EEF0F4", caret: "#FFB020" };
export const DEV_BAND = { band: "#FFB020", letters: "#1B1E24" };

const r1 = (n: number) => Math.round(n * 100) / 100;

// Smooth wave through extremes, with a horizontal tangent at each one.
export function waveD(ext: P[], k = 0.42): string {
  let d = `M${ext[0][0]} ${ext[0][1]}`;
  for (let i = 1; i < ext.length; i++) {
    const [x1, y1] = ext[i - 1];
    const [x2, y2] = ext[i];
    const dx = x2 - x1;
    d += `C${r1(x1 + k * dx)} ${y1} ${r1(x2 - k * dx)} ${y2} ${x2} ${y2}`;
  }
  return d;
}
export const caretD = (x: number, y0: number, y1: number, half: number) => `M${x} ${y0}V${y1}M${x - half} ${y0}H${x + half}M${x - half} ${y1}H${x + half}`;
const stroke = (col: string, w: number) => `fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"`;

// ---------- app icon, 1024 x 1024 canvas ----------
// The art is shifted 9 px left so the wave-plus-caret group sits on the optical centre.
const ICON_WAVE = `${waveD([
  [235, 512],
  [325, 352],
  [437, 648],
  [519, 512],
])}H681`;
const ICON_CARET = caretD(743, 378, 646, 46);
export const iconWave = (col: string) => `<path d="${ICON_WAVE}" ${stroke(col, 52)}/>`;
export const iconCaret = (col: string) => `<path d="${ICON_CARET}" ${stroke(col, 40)}/>`;

const svg = (size: number, body: string) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}" width="${size}" height="${size}">${body}</svg>\n`;

// Full-bleed square: macOS masks the corners itself.
export const appIconSVG = (p: Palette) =>
  svg(
    1024,
    `<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${p.bg1}"/><stop offset="1" stop-color="${p.bg2}"/></linearGradient></defs>` +
      `<rect width="1024" height="1024" fill="url(#bg)"/>${iconWave(p.wave)}${iconCaret(p.caret)}`,
  );
// The Dev band: a strip across the bottom, and "DEV" drawn as strokes (no fonts), centred under the mark.
const DEV_BAND_Y = 800;
const DEV_LETTERS =
  "M362 862V974H392C432 974 452 948 452 918C452 888 432 862 392 862Z" + "M552 862H482V974H552M482 918H540" + "M582 862L622 974L662 862";
export const devBand = (col: string) => `<rect y="${DEV_BAND_Y}" width="1024" height="${1024 - DEV_BAND_Y}" fill="${col}"/>`;
export const devLetters = (col: string) => `<path d="${DEV_LETTERS}" ${stroke(col, 30)}/>`;
export const devAppIconSVG = (p: Palette) => appIconSVG(p).replace("</svg>", `${devBand(DEV_BAND.band)}${devLetters(DEV_BAND.letters)}</svg>`);

// Icon Composer foreground layers: transparent canvas, black shapes; icon.json sets the colours per appearance.
export const waveLayerSVG = () => svg(1024, iconWave("#000000"));
export const caretLayerSVG = () => svg(1024, iconCaret("#000000"));
export const devBandLayerSVG = () => svg(1024, devBand("#000000"));
export const devLettersLayerSVG = () => svg(1024, devLetters("#000000"));

// ---------- menu-bar template glyph, 18 x 18 pt, black on transparent ----------
const GLYPH_WAVE = `${waveD([
  [1.3, 9],
  [3.5, 3.8],
  [6.4, 14.2],
  [8.4, 9],
])}H11`;
const glyphWave = `<path d="${GLYPH_WAVE}" ${stroke("#000000", 1.7)}/>`;
export const glyphIdleSVG = () => svg(18, glyphWave + `<path d="${caretD(14.4, 3.6, 14.4, 1.6)}" ${stroke("#000000", 1.7)}/>`);
// Listening blink: the same wave with the caret hidden; it alternates with idle at text-cursor speed.
export const glyphCaretOffSVG = () => svg(18, glyphWave);
// Attention (setup not complete, dictation waiting): the full mark plus a badge dot in the empty space above the flat line.
export const glyphAttentionSVG = () =>
  svg(18, glyphWave + `<path d="${caretD(14.4, 3.6, 14.4, 1.6)}" ${stroke("#000000", 1.7)}/><circle cx="9.4" cy="3.3" r="1.9" fill="#000000"/>`);
