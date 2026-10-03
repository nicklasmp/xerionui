// Lua 5.1 syntax check + global-write detector for WoW addon sources.
// usage: node lint.js <dir> [--globals] [--skip=Libs]
const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const args = process.argv.slice(2);
const root = args[0];
const showGlobals = args.includes('--globals');
const skip = (args.find(a => a.startsWith('--skip=')) || '--skip=').slice(7).split(',').filter(Boolean);
const allowGlobalWrites = new Set((args.find(a => a.startsWith('--allow=')) || '--allow=').slice(8).split(',').filter(Boolean));

function walk(dir, out) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) { if (!skip.includes(e.name)) walk(p, out); }
    else if (e.name.endsWith('.lua')) out.push(p);
  }
  return out;
}

let errors = 0, files = 0;
for (const file of walk(root, [])) {
  files++;
  const src = fs.readFileSync(file, 'utf8');
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: '5.1', scope: true, locations: true, comments: false });
  } catch (e) {
    errors++;
    console.log(`SYNTAX ${path.relative(root, file)}: ${e.message}`);
    continue;
  }
  if (!showGlobals) continue;
  const writes = new Map();
  (function visit(node) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { node.forEach(visit); return; }
    if (node.type === 'AssignmentStatement') {
      for (const v of node.variables) {
        if (v.type === 'Identifier' && !v.isLocal && !allowGlobalWrites.has(v.name)) {
          if (!writes.has(v.name)) writes.set(v.name, v.loc.start.line);
        }
      }
    }
    if (node.type === 'FunctionDeclaration' && node.identifier && node.identifier.type === 'Identifier' && !node.isLocal && !node.identifier.isLocal) {
      if (!allowGlobalWrites.has(node.identifier.name) && !writes.has(node.identifier.name)) writes.set(node.identifier.name, node.loc.start.line);
    }
    for (const k in node) if (k !== 'loc' && k !== 'range') visit(node[k]);
  })(ast);
  for (const [name, line] of writes) console.log(`GLOBAL ${path.relative(root, file)}:${line} ${name}`);
}
console.log(`${files} files, ${errors} syntax errors`);
process.exit(errors ? 1 : 0);
