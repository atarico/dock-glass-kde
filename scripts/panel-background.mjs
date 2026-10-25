// SPDX-License-Identifier: GPL-3.0-or-later
// Writes the panel backgrounds of the Dock Glass Plasma Style:
//
//   node scripts/panel-background.mjs
//
// Each SVG holds two frames. The "dock-" one has 32 px corners, so the 64 px
// dock is a full pill; the dock widget selects it. The plain one has 16 px
// corners for every other panel: Plasma never makes a panel thinner than its
// frame's top and bottom borders, so 32 px corners would keep a top bar at
// 64 px.
import {writeFileSync} from 'node:fs';
import {dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';

const STYLE_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'plasma-style');
// The middle of each frame, between its corners: any size, Plasma stretches it.
const EDGE = 8;
const MASK_OFFSET = 100;

const LOOKS = {
    // Clear glass, used while KWin blurs behind panels: no tint, like the
    // original pill on Blur My Shell's Liquid Glass, only a faint fill, a soft
    // highlight over the top half and a 1 px inner rim that is brighter on
    // top, as if lit from above.
    glass: {
        fill: 'fill="#ffffff" fill-opacity="0.06"',
        highlight: true,
        rim: {top: 0.50, side: 0.30, bottom: 0.18},
    },
    // Dark and nearly opaque: for the panel's opaque mode, and for when
    // nothing blurs behind panels.
    solid: {
        fill: 'fill="#26262a" fill-opacity="0.92"',
        highlight: false,
        rim: {top: 0.28, side: 0.28, bottom: 0.28},
    },
};

// The outlines of the nine cells of a frame with corners of radius r, laid
// out from (x, y).
function cells(r, x, y) {
    const e = EDGE;
    const far = x + 2 * r + e;
    const low = y + 2 * r + e;
    return {
        topleft: `M${x},${y + r} A${r},${r} 0 0 1 ${x + r},${y} V${y + r} Z`,
        top: `M${x + r},${y} h${e} v${r} h-${e} Z`,
        topright: `M${x + r + e},${y} A${r},${r} 0 0 1 ${far},${y + r} H${x + r + e} Z`,
        left: `M${x},${y + r} h${r} v${e} h-${r} Z`,
        center: `M${x + r},${y + r} h${e} v${e} h-${e} Z`,
        right: `M${x + r + e},${y + r} h${r} v${e} h-${r} Z`,
        bottomleft: `M${x + r},${low} A${r},${r} 0 0 1 ${x},${y + r + e} H${x + r} Z`,
        bottom: `M${x + r},${y + r + e} h${e} v${r} h-${e} Z`,
        bottomright: `M${far},${y + r + e} A${r},${r} 0 0 1 ${x + r + e},${low} V${y + r + e} Z`,
    };
}

// The nine elements of one frame and its mask. The rim is a filled ring, not
// a stroke: Qt pads a stroke's bounds by half its width, which shrank the
// corners into their cells and left seams.
function frame(prefix, r, x, y, look) {
    const e = EDGE;
    const far = x + 2 * r + e;
    const low = y + 2 * r + e;
    const shapes = cells(r, x, y);
    const q = r - 1;
    const rims = {
        topleft: [`M${x},${y + r} A${r},${r} 0 0 1 ${x + r},${y} V${y + 1} A${q},${q} 0 0 0 ${x + 1},${y + r} Z`, 'top'],
        top: [`M${x + r},${y} h${e} v1 h-${e} Z`, 'top'],
        topright: [`M${x + r + e},${y} A${r},${r} 0 0 1 ${far},${y + r} H${far - 1} A${q},${q} 0 0 0 ${x + r + e},${y + 1} Z`, 'top'],
        left: [`M${x},${y + r} h1 v${e} h-1 Z`, 'side'],
        right: [`M${far - 1},${y + r} h1 v${e} h-1 Z`, 'side'],
        bottomleft: [`M${x + r},${low} A${r},${r} 0 0 1 ${x},${y + r + e} H${x + 1} A${q},${q} 0 0 0 ${x + r},${low - 1} Z`, 'bottom'],
        bottom: [`M${x + r},${low - 1} h${e} v1 h-${e} Z`, 'bottom'],
        bottomright: [`M${far},${y + r + e} A${r},${r} 0 0 1 ${x + r + e},${low} V${low - 1} A${q},${q} 0 0 0 ${far - 1},${y + r + e} Z`, 'bottom'],
    };
    const lines = [];
    for (const [name, shape] of Object.entries(shapes)) {
        const parts = [`<path d="${shape}" ${look.fill}/>`];
        if (look.highlight && name.startsWith('top'))
            parts.push(`<path d="${shape}" fill="url(#highlight)"/>`);
        if (rims[name]) {
            const [ring, side] = rims[name];
            parts.push(`<path d="${ring}" fill="#ffffff" fill-opacity="${look.rim[side].toFixed(2)}"/>`);
        }
        lines.push(`  <g id="${prefix}${name}">`, ...parts.map(part => `    ${part}`), '  </g>');
    }
    // The blur region: the same shapes, as alpha.
    for (const [name, shape] of Object.entries(cells(r, x + MASK_OFFSET, y)))
        lines.push(`  <path id="mask-${prefix}${name}" d="${shape}"/>`);
    return lines.join('\n');
}

// Content margins. Without them, Plasma would take the corners as margins.
// With these, Plasma 6.8.1 pads the panel's widgets by 8 px at the ends and
// 4 px above and below, the same as with Breeze.
function hints(prefix, x, y) {
    return [
        `  <rect id="${prefix}hint-left-margin" x="${x}" y="${y}" width="14" height="1" fill-opacity="0"/>`,
        `  <rect id="${prefix}hint-right-margin" x="${x}" y="${y + 2}" width="14" height="1" fill-opacity="0"/>`,
        `  <rect id="${prefix}hint-top-margin" x="${x + 16}" y="${y}" width="1" height="4" fill-opacity="0"/>`,
        `  <rect id="${prefix}hint-bottom-margin" x="${x + 18}" y="${y}" width="1" height="4" fill-opacity="0"/>`,
    ].join('\n');
}

function panelBackground(look, description) {
    const dockRadius = 32;
    const barRadius = 16;
    const barY = 2 * dockRadius + EDGE + 8;
    const height = barY + 2 * barRadius + EDGE;
    return `<?xml version="1.0" encoding="UTF-8"?>
<!-- SPDX-License-Identifier: GPL-3.0-or-later -->
<!-- ${description}
     Written by scripts/panel-background.mjs; edit that and run it again.
     The dock- frame has 32 px corners, so the 64 px dock is a full pill; the
     plain frame has 16 px corners, so other panels can be as thin as 32 px.
     The mask- elements repeat each shape ${MASK_OFFSET} px to the right for the
     blur region, and the hint- elements at x >= 200 only give margins. -->
<svg xmlns="http://www.w3.org/2000/svg" width="300" height="${height}" viewBox="0 0 300 ${height}">
  <defs>
    <!-- Down each top element, which is the frame's upper half. -->
    <linearGradient id="highlight" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff" stop-opacity="0.20"/>
      <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
    </linearGradient>
  </defs>
${frame('dock-', dockRadius, 0, 0, look)}
${frame('', barRadius, 0, barY, look)}
${hints('', 200, 0)}
${hints('dock-', 200, 10)}
  <!-- Plasma pads a panel's widgets with the thick- margins. -->
  <rect id="thick-center" x="230" y="0" width="8" height="8" fill-opacity="0"/>
  <rect id="thick-hint-left-margin" x="240" y="0" width="10" height="1" fill-opacity="0"/>
  <rect id="thick-hint-right-margin" x="240" y="2" width="10" height="1" fill-opacity="0"/>
  <rect id="thick-hint-top-margin" x="252" y="0" width="1" height="1" fill-opacity="0"/>
  <rect id="thick-hint-bottom-margin" x="254" y="0" width="1" height="1" fill-opacity="0"/>
</svg>
`;
}

const glass = panelBackground(LOOKS.glass,
    'Clear glass panel, used while KWin blurs behind panels.');
const solid = panelBackground(LOOKS.solid,
    'Dark, nearly opaque panel: for the opaque mode, and for when nothing\n     blurs behind panels.');
writeFileSync(join(STYLE_DIR, 'translucent/widgets/panel-background.svg'), glass);
for (const path of ['widgets/panel-background.svg', 'solid/widgets/panel-background.svg', 'opaque/widgets/panel-background.svg'])
    writeFileSync(join(STYLE_DIR, path), solid);
