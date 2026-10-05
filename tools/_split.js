// One-off: splits XerionUI_Options/Panel.lua into Panel / PageHead / Sidebar / Preview.
const fs = require('fs');
const dir = '../XerionUI_Options/';
const src = fs.readFileSync(dir + 'Panel.lua', 'utf8').replace(/\r\n/g, '\n');
const lines = src.split('\n');

const SEP = '--------------------------------------------------------------------------------';
// index of the separator line that starts the section whose title line is `title`
function sectionStart(title) {
  const i = lines.findIndex(l => l === title);
  if (i < 0) throw new Error('no section ' + title);
  if (lines[i - 1] !== SEP) throw new Error('no separator before ' + title);
  return i - 1;
}
const iHead = sectionStart('-- Page header');
const iSide = sectionStart('-- Sidebar');
const iWin = sectionStart('-- Window');
const iPrev = sectionStart('-- Preview that follows the page, and a window that steps aside for it');
const iOpen = lines.findIndex(l => l === 'function O:Open(key)');

const A = lines.slice(0, iHead);
const B = lines.slice(iHead, iSide);
const C = lines.slice(iSide, iWin);
const D = lines.slice(iWin, iPrev);
const E = lines.slice(iPrev, iOpen);
const F = lines.slice(iOpen);

const SHARED = ['frame', 'sidebar', 'content', 'pageHead', 'entries', 'pages', 'currentKey', 'searchText',
  'expandedClass', 'autoStarted', 'docked', 'UpdateDockSoon'];
const CROSS = { ClassKey: 'O.ClassKey', ModuleContext: 'O.ModuleContext', CreatePageHead: 'O.CreatePageHead', SyncAutoPreview: 'O.SyncAutoPreview' };

function transform(chunk, opts) {
  return chunk.map(line => {
    if (/^\s*--/.test(line)) return line;
    // split off strings and a trailing comment so only code is rewritten
    const parts = line.split(/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/);
    for (let i = 0; i < parts.length; i += 2) {
      let p = parts[i];
      const c = p.indexOf('--');
      let tail = '';
      if (c >= 0) { tail = p.slice(c); p = p.slice(0, c); }
      for (const n of SHARED) {
        p = p.replace(new RegExp('(^|[^A-Za-z0-9_.:])' + n + '(?![A-Za-z0-9_])', 'g'), '$1S.' + n);
      }
      for (const [n, to] of Object.entries(CROSS)) {
        // calls and references, not the definition `local function Name`
        p = p.replace(new RegExp('(^|[^A-Za-z0-9_.:])' + n + '(?![A-Za-z0-9_])', 'g'), '$1' + to);
      }
      parts[i] = p + tail;
    }
    return parts.join('');
  });
}

// top declarations of A: drop the shared locals, add the state table
let a = A.join('\n');
a = a.replace(/local frame, sidebar, content, pageHead\nlocal entries = \{\}[^\n]*\nlocal pages = \{\}[^\n]*\nlocal currentKey\nlocal autoStarted, docked, UpdateDockSoon = \{\}, false, nil\nlocal expandedClass = \{\}\nlocal searchText = ""\n/,
  `-- State the window, the sidebar, the page head and the preview helpers share.
local S = {
	entries = {},        -- sidebar entries in display order
	pages = {},          -- [key] = Page
	autoStarted = {},    -- modules whose preview the open page started
	expandedClass = {},  -- [class token] = unfolded in the sidebar
	docked = false,
	searchText = "",
}
O.S = S
`);
if (!a.includes('O.S = S')) throw new Error('top declarations not replaced');
a = a.replace('local ITEM_H = 28\n', 'local ITEM_H = 28\nO.LAYOUT = { SIDEBAR_W = SIDEBAR_W, HEADER_H = HEADER_H, PAGEHEAD_H = PAGEHEAD_H, ITEM_H = ITEM_H }\n');
let aLines = transform(a.split('\n'));
let aText = aLines.join('\n');
// in A these are definitions the other files call through O
aText = aText.replace(/local function O\.ModuleContext\(m\)/, 'function O.ModuleContext(m)');
aText = aText.replace(/local function O\.ClassKey\(key\)/, 'function O.ClassKey(key)');
aText = aText.replace('S.entries = {}', 'S.entries = {}'); // no-op guard

function header(title, uses) {
  return `--------------------------------------------------------------------------------
-- XerionUI_Options - ${title}
-- (split out of Panel.lua; the window state lives in O.S)
--------------------------------------------------------------------------------
local XUI = _G.XerionUI
local O = XUI and XUI.Options
if not O then return end

local S = O.S
${uses || ''}
`;
}

let b = transform(B).join('\n');
b = b.replace('local function CreatePageHead(parent)', 'function O.CreatePageHead(parent)').replace('local function O.CreatePageHead(parent)', 'function O.CreatePageHead(parent)');
let c = transform(C).join('\n');
let e = transform(E).join('\n');
e = e.replace('local function SyncAutoPreview(key)', 'function O.SyncAutoPreview(key)').replace('local function O.SyncAutoPreview(key)', 'function O.SyncAutoPreview(key)');
let d = transform(D).join('\n');
let f = transform(F).join('\n');

fs.writeFileSync(dir + 'PageHead.lua', header('PageHead.lua', 'local PAGEHEAD_H = O.LAYOUT.PAGEHEAD_H\n') + b.replace(/^-+\n-- Page header\n-+\n/, '--------------------------------------------------------------------------------\n-- Page header\n--------------------------------------------------------------------------------\n'));
fs.writeFileSync(dir + 'Sidebar.lua', header('Sidebar.lua', 'local ITEM_H = O.LAYOUT.ITEM_H\n') + c);
fs.writeFileSync(dir + 'Preview.lua', header('Preview.lua') + e);
fs.writeFileSync(dir + 'Panel.lua', aText + '\n' + d + '\n' + f);
console.log('A', A.length, 'B', B.length, 'C', C.length, 'D', D.length, 'E', E.length, 'F', F.length);
