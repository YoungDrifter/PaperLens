import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const sharp = createRequire(import.meta.url)('sharp');
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [version, scene, ...extra] = process.argv.slice(2);
if (!/^\d+\.\d+\.\d+$/.test(version ?? '') || extra.length) {
  throw new Error('Usage: node '+path.basename(fileURLToPath(import.meta.url))+' VERSION [SCENE]');
}
const assets = path.join(root, 'docs/versions', version);
const brand = "PaperLens";
const platform = "macOS 15+";
const scenes = [["welcome", "打开一页，留住专注。", "从一份 PDF 开始，留一处安静的阅读空间。", "开始阅读"], ["reading", "多份文档，一处阅读。", "把相关文档放在一起，保留每一次阅读的位置。", "多标签阅读"], ["outline", "沿着章节，读得更从容。", "从章节结构出发，快速抵达要读的段落。", "大纲导航"], ["comments", "一条批注，连回一处思考。", "把想法放在页边，用一条曲线连回原文。", "页面批注"]];
if (scene && !scenes.some(([name]) => name === scene)) throw new Error(`Unknown scene: ${scene}`);
const icon = (await readFile(path.join(root, "PaperLens/Icon/icon_1024.png"))).toString('base64');
const escape = value => value.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
for (const [index, [name, title, subtitle, label]] of scenes.entries()) {
  if (scene && scene !== name) continue;
  const capture = await sharp(await readFile(path.join(assets, `images/source/${name}.png`))).png().toBuffer();
  const {width, height} = await sharp(capture).metadata();
  if (!width || !height) throw new Error(`Invalid source: ${name}`);
  const scale = Math.min(1600 / width, 1060 / height);
  const w = width * scale, h = height * scale;
  const x = (1800 - w) / 2, y = 292 + (1060 - h) / 2;
  const windowRect = `x="${x}" y="${y}" width="${w}" height="${h}" rx="20"`;
  // Restore the active macOS control colours in the promotional composition.
  // Keep their original position, size and outline from the native capture.
  const colours = [['#ff5f57','#e0443e'], ['#febc2e','#dea123'], ['#28c840','#1eac30']];
  const controls = `<g transform="translate(${x} ${y}) scale(${scale})">${[40,80,120].map((cx,i) => `<circle cx="${cx}" cy="54" r="13" fill="${colours[i][0]}" stroke="${colours[i][1]}" stroke-width="1"/>`).join('')}</g>`;
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1800" height="1500" viewBox="0 0 1800 1500">
    <defs>
      <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="16" stdDeviation="20" flood-color="#000" flood-opacity=".09"/></filter>
      <clipPath id="capture"><rect ${windowRect}/></clipPath>
    </defs>
    <rect width="1800" height="1500" fill="#fff"/>
    <g font-family="PingFang SC, Helvetica Neue, sans-serif">
      <image href="data:image/png;base64,${icon}" x="100" y="42" width="54" height="54"/>
      <text x="172" y="80" font-size="30" font-weight="600" fill="#111">${escape(brand)}</text>
      <text x="1700" y="80" text-anchor="end" font-size="23" fill="#222">${escape(label)}</text>
      <line x1="100" y1="117" x2="1700" y2="117" stroke="#eee"/>
      <text x="100" y="194" font-size="60" font-weight="600" letter-spacing="-1" fill="#000">${escape(title)}</text>
      <text x="100" y="249" font-size="27" fill="#666">${escape(subtitle)}</text>
      <rect ${windowRect} fill="#fff" filter="url(#shadow)"/>
      <g clip-path="url(#capture)"><image href="data:image/png;base64,${capture.toString('base64')}" x="${x}" y="${y}" width="${w}" height="${h}"/>${controls}</g>
      <rect ${windowRect} fill="none" stroke="#ddd" stroke-width="1"/>
      <text x="100" y="1450" font-size="20" fill="#777">${escape(brand)} · ${escape(version)} · ${escape(platform)}</text>
      <text x="1700" y="1450" text-anchor="end" font-size="20" fill="#777">${String(index+1).padStart(2,'0')} / 04</text>
    </g>
  </svg>`;
  await writeFile(path.join(assets, `images/source/${name}.svg`), svg);
  await sharp(Buffer.from(svg)).png().toFile(path.join(assets, `images/${name}.png`));
  console.log(`${brand} / ${name}: ${width} × ${height} → 1800 × 1500`);
}
