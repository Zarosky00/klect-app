#!/usr/bin/env node
/**
 * Klect token compiler.
 *
 *   node build.mjs
 *
 * Reads tokens.json (the only place design values may be authored) and emits:
 *   ../../mobile/lib/design/tokens.g.dart   — Dart consts + ColorScheme-ish holders
 *   ../../web/src/styles/tokens.g.css       — CSS custom properties for :root / [data-theme]
 *   ../../web/src/design/tokens.g.ts        — typed TS mirror for JS-side needs (motion, layout)
 *
 * Generated files are checked in so `flutter analyze` / `tsc` never depend on Node running first.
 */
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const T = JSON.parse(readFileSync(resolve(here, 'tokens.json'), 'utf8'));

const BANNER_LINES = [
  'GENERATED FILE — DO NOT EDIT.',
  'Source: packages/tokens/tokens.json',
  'Regenerate: node packages/tokens/build.mjs',
];

/* ------------------------------------------------------------------ utils */

const write = (rel, body) => {
  const out = resolve(here, rel);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, body, 'utf8');
  console.log('  ✓', rel.replace(/\\/g, '/'));
};

/** #RRGGBB or #RRGGBBAA -> 0xAARRGGBB for Dart */
const toArgb = (hex) => {
  let h = hex.replace('#', '').trim();
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  if (h.length === 6) h = 'ff' + h;
  else if (h.length === 8) h = h.slice(6, 8) + h.slice(0, 6); // RRGGBBAA -> AARRGGBB
  else throw new Error(`Bad colour literal: ${hex}`);
  return '0x' + h.toUpperCase();
};

/** #RRGGBBAA -> rgb(r g b / a) so CSS gets a real alpha channel */
const toCss = (hex) => {
  let h = hex.replace('#', '').trim();
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  if (h.length === 6) return `#${h.toUpperCase()}`;
  const [r, g, b, a] = [0, 2, 4, 6].map((i) => parseInt(h.slice(i, i + 2), 16));
  return `rgb(${r} ${g} ${b} / ${+(a / 255).toFixed(3)})`;
};

const isColor = (v) => typeof v === 'string' && /^#[0-9a-fA-F]{3,8}$/.test(v);
/** Dart double literal: integers keep a `.0` so the type is never ambiguous. */
const dbl = (v) => (Number.isInteger(Number(v)) ? Number(v).toFixed(1) : String(Number(v)));
const camel = (s) => s.replace(/[_\-\s]+(.)/g, (_, c) => c.toUpperCase()).replace(/^(\d)/, 's$1');
const kebab = (s) => s.replace(/_/g, '-');

/** walk a plain object tree, skipping $meta/note keys, yielding [pathArray, value] */
function* leaves(node, path = []) {
  for (const [k, v] of Object.entries(node)) {
    if (k === '$meta' || k === 'note') continue;
    if (v && typeof v === 'object' && !Array.isArray(v)) yield* leaves(v, [...path, k]);
    else yield [[...path, k], v];
  }
}

/* ------------------------------------------------------------------- dart */

function buildDart() {
  const L = [];
  const p = (s = '') => L.push(s);

  BANNER_LINES.forEach((l) => p(`// ${l}`));
  p('// ignore_for_file: constant_identifier_names, unused_field');
  p();
  p("import 'dart:ui' show Color;");
  p("import 'package:flutter/animation.dart' show Cubic, Curve;");
  p();

  /* ---- colours: one class per theme, plus an abstract contract so widgets
         can take a KlectColors and never care which theme is live. ---- */
  const darkLeaves = [...leaves(T.color.dark)].filter(([, v]) => isColor(v));
  const lightLeaves = [...leaves(T.color.light)].filter(([, v]) => isColor(v));

  const nameOf = (path) => camel(path.join('_'));

  const dNames = darkLeaves.map(([pth]) => nameOf(pth));
  const lNames = lightLeaves.map(([pth]) => nameOf(pth));
  const missing = dNames.filter((n) => !lNames.includes(n)).concat(lNames.filter((n) => !dNames.includes(n)));
  if (missing.length) throw new Error(`dark/light colour sets diverge: ${[...new Set(missing)].join(', ')}`);

  p('/// Every colour the product may use. Implemented once per theme.');
  p('/// A raw hex anywhere in the widget tree is a bug — read it from here.');
  p('abstract class KlectColors {');
  p('  const KlectColors();');
  dNames.forEach((n) => p(`  Color get ${n};`));
  p('  bool get isDark;');
  p('}');
  p();

  const emitTheme = (className, entries, isDark) => {
    p(`class ${className} extends KlectColors {`);
    p(`  const ${className}();`);
    p(`  @override`);
    p(`  bool get isDark => ${isDark};`);
    entries.forEach(([pth, hex]) => {
      p(`  @override`);
      p(`  Color get ${nameOf(pth)} => const Color(${toArgb(hex)});`);
    });
    p('}');
    p();
  };
  emitTheme('KlectColorsDark', darkLeaves, true);
  emitTheme('KlectColorsLight', lightLeaves, false);

  /* ---- spacing ---- */
  p('/// 4pt grid. Values outside this ramp are not permitted.');
  p('abstract final class Space {');
  for (const [k, v] of Object.entries(T.space)) {
    if (k === 'note') continue;
    p(`  static const double ${camel('s_' + k)} = ${Number(v).toFixed(1)};`);
  }
  p('}');
  p();

  /* ---- radius ---- */
  p('abstract final class Radii {');
  for (const [k, v] of Object.entries(T.radius)) p(`  static const double ${camel(k)} = ${Number(v).toFixed(1)};`);
  p('}');
  p();

  /* ---- border widths ---- */
  p('abstract final class Strokes {');
  for (const [k, v] of Object.entries(T.border)) p(`  static const double ${camel(k)} = ${Number(v).toFixed(1)};`);
  p('}');
  p();

  /* ---- typography ---- */
  p('/// Immutable description of one step on the type scale.');
  p('class TypeStep {');
  p('  const TypeStep(this.size, this.height, this.weight, this.family, this.tracking, {this.tabular = false});');
  p('  final double size;');
  p('  final double height;      // absolute line-height in logical px');
  p('  final int weight;');
  p('  final String family;');
  p('  final double tracking;');
  p('  final bool tabular;');
  p('  /// Flutter wants a unitless multiplier for TextStyle.height.');
  p('  double get heightFactor => height / size;');
  p('}');
  p();
  p('abstract final class Fonts {');
  for (const [k, v] of Object.entries(T.typography.family)) p(`  static const String ${camel(k)} = '${v}';`);
  p('}');
  p();
  p('abstract final class TypeScale {');
  for (const [k, v] of Object.entries(T.typography.scale)) {
    const fam = `Fonts.${camel(v.family)}`;
    const tab = v.tabular ? ', tabular: true' : '';
    p(`  static const TypeStep ${camel(k)} = TypeStep(${v.size.toFixed(1)}, ${v.lineHeight.toFixed(1)}, ${v.weight}, ${fam}, ${v.tracking.toFixed(2)}${tab});`);
  }
  p('}');
  p();

  /* ---- elevation ---- */
  p('class ShadowSpec {');
  p('  const ShadowSpec(this.y, this.blur, this.spread, this.color);');
  p('  final double y; final double blur; final double spread; final Color color;');
  p('}');
  p();
  p('abstract final class Elevation {');
  for (const [k, v] of Object.entries(T.elevation)) {
    if (k === 'note') continue;
    p(`  static const ShadowSpec ${camel(k)} = ShadowSpec(${v.y.toFixed(1)}, ${v.blur.toFixed(1)}, ${v.spread.toFixed(1)}, Color(${toArgb(v.color)}));`);
  }
  p('}');
  p();

  /* ---- motion ---- */
  p('abstract final class Durations {');
  for (const [k, v] of Object.entries(T.motion.duration)) p(`  static const Duration ${camel(k)} = Duration(milliseconds: ${v});`);
  p('}');
  p();
  p('abstract final class Curves_ {');
  for (const [k, v] of Object.entries(T.motion.curve)) {
    p(`  static const Curve ${camel(k)} = Cubic(${v.map((n) => n.toFixed(3)).join(', ')});`);
  }
  p('}');
  p();
  p('class SpringSpec {');
  p('  const SpringSpec(this.stiffness, this.damping, this.mass);');
  p('  final double stiffness; final double damping; final double mass;');
  p('}');
  p();
  p('abstract final class Springs {');
  for (const [k, v] of Object.entries(T.motion.spring)) {
    p(`  static const SpringSpec ${camel(k)} = SpringSpec(${v.stiffness.toFixed(1)}, ${v.damping.toFixed(1)}, ${v.mass.toFixed(1)});`);
  }
  p('}');
  p();
  p('abstract final class Stagger {');
  for (const [k, v] of Object.entries(T.motion.stagger)) p(`  static const int ${camel(k)} = ${v};`);
  p('}');
  p();
  p('/// How long a transient surface stays before it dismisses itself.');
  p('/// A dwell period is not an animation, so the 480ms animation ceiling');
  p('/// from `docs/DESIGN_SYSTEM.md` does not apply here.');
  p('abstract final class Dwell {');
  for (const [k, v] of Object.entries(T.motion.dwell)) {
    if (k === 'note') continue;
    p(`  static const Duration ${camel(k)} = Duration(milliseconds: ${v});`);
  }
  p('}');
  p();
  p('/// Finger-driven commit thresholds. Distances are logical pixels,');
  p('/// velocities logical pixels per second, fractions are of the dragged extent.');
  p('abstract final class Drags {');
  for (const [k, v] of Object.entries(T.motion.drag)) {
    if (k === 'note') continue;
    p(`  static const double ${camel(k)} = ${dbl(v)};`);
  }
  p('}');
  p();
  p('/// How long an async placeholder may wait before it gives up.');
  p('/// Network budget, not motion.');
  p('abstract final class Timeouts {');
  for (const [k, v] of Object.entries(T.motion.timeout)) {
    if (k === 'note') continue;
    p(`  static const Duration ${camel(k)} = Duration(milliseconds: ${v});`);
  }
  p('}');
  p();

  /* ---- layout ---- */
  p('abstract final class Breakpoints {');
  for (const [k, v] of Object.entries(T.layout.breakpoint)) p(`  static const double ${camel(k)} = ${Number(v).toFixed(1)};`);
  p('}');
  p();
  p('abstract final class Layout {');
  p(`  static const double masonryGutter = ${T.layout.masonryGutter.toFixed(1)};`);
  p(`  static const double contentMaxWidth = ${T.layout.contentMaxWidth.toFixed(1)};`);
  p(`  static const double readableMaxWidth = ${T.layout.readableMaxWidth.toFixed(1)};`);
  p(`  static const double tapTargetMin = ${T.layout.tapTargetMin.toFixed(1)};`);
  p(`  static const double bottomBarHeight = ${T.layout.bottomBarHeight.toFixed(1)};`);
  p(`  static const double topBarHeight = ${T.layout.topBarHeight.toFixed(1)};`);
  p(`  static const double callPillHeight = ${T.layout.callPillHeight.toFixed(1)};`);
  p('  /// Masonry column count for a given viewport width. Mobile and web');
  p('  /// resolve this identically so a shared link looks like the same product.');
  p('  static int masonryColumns(double width) {');
  const bps = Object.entries(T.layout.breakpoint).sort((a, b) => b[1] - a[1]);
  for (const [name, min] of bps) {
    const cols = T.layout.masonryColumns[name];
    if (cols == null) continue;
    p(`    if (width >= ${Number(min).toFixed(1)}) return ${cols};`);
  }
  p(`    return ${T.layout.masonryColumns.xs};`);
  p('  }');
  p('}');
  p();
  p('abstract final class Opacities {');
  for (const [k, v] of Object.entries(T.opacity)) p(`  static const double ${camel(k)} = ${v};`);
  p('}');
  p();
  p('abstract final class Blurs {');
  for (const [k, v] of Object.entries(T.blur)) p(`  static const double ${camel(k)} = ${Number(v).toFixed(1)};`);
  p('}');
  p();
  p('abstract final class Aspect {');
  for (const [k, v] of Object.entries(T.aspect)) {
    if (k === 'note') continue;
    p(`  static const double ${camel(k)} = ${Number(v).toFixed(2)};`);
  }
  p('}');
  p();
  p('abstract final class ZIndex {');
  for (const [k, v] of Object.entries(T.z)) p(`  static const int ${camel(k)} = ${v};`);
  p('}');

  return L.join('\n') + '\n';
}

/* -------------------------------------------------------------------- css */

function buildCss() {
  const L = [];
  // variadic: colour blocks are pushed as spread arrays
  const p = (...s) => L.push(...(s.length ? s : ['']));

  p('/*');
  BANNER_LINES.forEach((l) => p(` * ${l}`));
  p(' */');
  p();

  const colorVars = (theme) =>
    [...leaves(T.color[theme])]
      .filter(([, v]) => isColor(v))
      .map(([pth, v]) => `  --k-${pth.map(kebab).join('-')}: ${toCss(v)};`);

  // Dark is the default identity of the product; light is the override.
  p(':root {');
  p('  color-scheme: dark;');
  p(...colorVars('dark'));
  p('}');
  p();
  p("[data-theme='light'] {");
  p('  color-scheme: light;');
  p(...colorVars('light'));
  p('}');
  p();
  p('@media (prefers-color-scheme: light) {');
  p('  :root:not([data-theme]) {');
  p('    color-scheme: light;');
  p(...colorVars('light').map((l) => '  ' + l));
  p('  }');
  p('}');
  p();

  p(':root {');
  p('  /* type */');
  for (const [k, v] of Object.entries(T.typography.family)) p(`  --k-font-${kebab(k)}: '${v}';`);
  for (const [k, v] of Object.entries(T.typography.scale)) {
    p(`  --k-text-${kebab(k)}-size: ${v.size / 16}rem;`);
    p(`  --k-text-${kebab(k)}-lh: ${(v.lineHeight / v.size).toFixed(4)};`);
    p(`  --k-text-${kebab(k)}-weight: ${v.weight};`);
    p(`  --k-text-${kebab(k)}-tracking: ${v.tracking / 16}rem;`);
  }
  p('  /* space */');
  for (const [k, v] of Object.entries(T.space)) {
    if (k === 'note') continue;
    p(`  --k-space-${kebab(k)}: ${Number(v)}px;`);
  }
  p('  /* radius */');
  for (const [k, v] of Object.entries(T.radius)) p(`  --k-radius-${kebab(k)}: ${Number(v)}px;`);
  p('  /* stroke */');
  for (const [k, v] of Object.entries(T.border)) p(`  --k-stroke-${kebab(k)}: ${Number(v)}px;`);
  p('  /* elevation */');
  for (const [k, v] of Object.entries(T.elevation)) {
    if (k === 'note') continue;
    p(`  --k-shadow-${kebab(k)}: 0 ${v.y}px ${v.blur}px ${v.spread}px ${toCss(v.color)};`);
  }
  p('  /* motion */');
  for (const [k, v] of Object.entries(T.motion.duration)) p(`  --k-dur-${kebab(k)}: ${v}ms;`);
  for (const [k, v] of Object.entries(T.motion.curve)) p(`  --k-ease-${kebab(k)}: cubic-bezier(${v.join(', ')});`);
  p('  /* dwell + timeout: self-dismiss and network budgets, not animation */');
  for (const [k, v] of Object.entries(T.motion.dwell)) {
    if (k === 'note') continue;
    p(`  --k-dwell-${kebab(k)}: ${v}ms;`);
  }
  for (const [k, v] of Object.entries(T.motion.timeout)) {
    if (k === 'note') continue;
    p(`  --k-timeout-${kebab(k)}: ${v}ms;`);
  }
  p('  /* drag thresholds: unitless — px, px/s and fractions, per token name */');
  for (const [k, v] of Object.entries(T.motion.drag)) {
    if (k === 'note') continue;
    p(`  --k-drag-${kebab(k)}: ${v};`);
  }
  p('  /* layout */');
  p(`  --k-masonry-gutter: ${T.layout.masonryGutter}px;`);
  p(`  --k-content-max: ${T.layout.contentMaxWidth}px;`);
  p(`  --k-readable-max: ${T.layout.readableMaxWidth}px;`);
  p(`  --k-tap-min: ${T.layout.tapTargetMin}px;`);
  p(`  --k-bottombar-h: ${T.layout.bottomBarHeight}px;`);
  p(`  --k-topbar-h: ${T.layout.topBarHeight}px;`);
  p(`  --k-callpill-h: ${T.layout.callPillHeight}px;`);
  p('  /* opacity + blur */');
  for (const [k, v] of Object.entries(T.opacity)) p(`  --k-opacity-${kebab(k)}: ${v};`);
  for (const [k, v] of Object.entries(T.blur)) p(`  --k-blur-${kebab(k)}: ${v}px;`);
  p('  /* z */');
  for (const [k, v] of Object.entries(T.z)) p(`  --k-z-${kebab(k)}: ${v};`);
  p('}');
  p();
  p('/* Masonry column count must match Layout.masonryColumns() in Dart. */');
  p(':root { --k-masonry-cols: ' + T.layout.masonryColumns.xs + '; }');
  for (const [name, min] of Object.entries(T.layout.breakpoint)) {
    const cols = T.layout.masonryColumns[name];
    if (cols == null || min === 0) continue;
    p(`@media (min-width: ${min}px) { :root { --k-masonry-cols: ${cols}; } }`);
  }
  p();
  p('/* Respect the OS. Anyone who asks for less motion gets none of ours. */');
  p('@media (prefers-reduced-motion: reduce) {');
  p('  :root {');
  for (const k of Object.keys(T.motion.duration)) p(`    --k-dur-${kebab(k)}: 1ms;`);
  p('  }');
  p('  *, *::before, *::after { animation-duration: 1ms !important; transition-duration: 1ms !important; scroll-behavior: auto !important; }');
  p('}');

  return L.join('\n') + '\n';
}

/* --------------------------------------------------------------------- ts */

function buildTs() {
  const L = [];
  BANNER_LINES.forEach((l) => L.push(`// ${l}`));
  L.push('');
  L.push('/* Values JS actually needs at runtime — motion for Framer-style springs,');
  L.push('   layout for masonry math. Colours stay in CSS custom properties so the');
  L.push('   theme can flip without a React re-render. */');
  L.push('');
  L.push(`export const duration = ${JSON.stringify(T.motion.duration, null, 2)} as const;`);
  L.push('');
  L.push(`export const ease = ${JSON.stringify(T.motion.curve, null, 2)} as const;`);
  L.push('');
  L.push(`export const spring = ${JSON.stringify(T.motion.spring, null, 2)} as const;`);
  L.push('');
  L.push(`export const stagger = ${JSON.stringify(T.motion.stagger, null, 2)} as const;`);
  L.push('');
  L.push('/** Self-dismiss periods in ms. Not animation — the 480ms cap does not apply. */');
  L.push(`export const dwell = ${JSON.stringify(T.motion.dwell, null, 2)} as const;`);
  L.push('');
  L.push('/** Finger-driven commit thresholds: px, px/s and fractions of the dragged extent. */');
  L.push(`export const drag = ${JSON.stringify(T.motion.drag, null, 2)} as const;`);
  L.push('');
  L.push('/** Async placeholder budgets in ms. */');
  L.push(`export const timeout = ${JSON.stringify(T.motion.timeout, null, 2)} as const;`);
  L.push('');
  const layout = { ...T.layout };
  delete layout.note;
  L.push(`export const layout = ${JSON.stringify(layout, null, 2)} as const;`);
  L.push('');
  const aspect = { ...T.aspect };
  delete aspect.note;
  L.push(`export const aspect = ${JSON.stringify(aspect, null, 2)} as const;`);
  L.push('');
  L.push(`export const z = ${JSON.stringify(T.z, null, 2)} as const;`);
  L.push('');
  L.push('/** Mirrors Layout.masonryColumns() in Dart. Keep the two in lockstep. */');
  L.push('export function masonryColumns(width: number): number {');
  const bps = Object.entries(T.layout.breakpoint).sort((a, b) => b[1] - a[1]);
  for (const [name, min] of bps) {
    const cols = T.layout.masonryColumns[name];
    if (cols == null) continue;
    L.push(`  if (width >= ${min}) return ${cols};`);
  }
  L.push(`  return ${T.layout.masonryColumns.xs};`);
  L.push('}');
  L.push('');
  return L.join('\n');
}

/* -------------------------------------------------------------------- run */

console.log('Klect tokens →');
write('../../mobile/lib/design/tokens.g.dart', buildDart());
write('../../web/src/styles/tokens.g.css', buildCss());
write('../../web/src/design/tokens.g.ts', buildTs());
console.log('done.');
