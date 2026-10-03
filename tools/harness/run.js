// Runs XerionUI inside a mocked WoW client (fengari Lua VM) and drives the
// options window through a scenario. Exits non-zero when any Lua error was
// raised or reported to the error handler.
//   node tools/harness/run.js            (needs: npm install fengari)
const fs = require('fs');
const path = require('path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

const ROOT = path.resolve(__dirname, '..', '..');
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// readfile(relativePath) -> contents or nil
lua.lua_register(L, to_luastring('readfile'), (L) => {
  const rel = to_jsstring(lauxlib.luaL_checkstring(L, 1));
  const p = path.join(ROOT, rel.replace(/\\/g, '/'));
  if (!fs.existsSync(p)) { lua.lua_pushnil(L); return 1; }
  lua.lua_pushstring(L, to_luastring(fs.readFileSync(p, 'latin1'), true));
  return 1;
});

const emit = require('./snapshot');
lua.lua_register(L, to_luastring('emitsnapshot'), (L) => {
  const name = to_jsstring(lauxlib.luaL_checkstring(L, 1));
  const json = to_jsstring(lauxlib.luaL_checkstring(L, 2));
  const w = lua.lua_tonumber(L, 3), h = lua.lua_tonumber(L, 4);
  const crop = lua.lua_isnumber(L, 5) ? [5, 6, 7, 8].map((i) => lua.lua_tonumber(L, i)) : null;
  console.log('snapshot: ' + emit(name, json, w, h, crop));
  return 0;
});

function runFile(file) {
  const src = fs.readFileSync(path.join(__dirname, file));
  if (lauxlib.luaL_loadbuffer(L, src, null, to_luastring('@' + file)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(2);
  }
}

runFile('wowmock.lua');
runFile('render.lua');
runFile('loader.lua');
runFile(process.argv[2] || 'scenario.lua');
