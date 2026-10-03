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

function runFile(file) {
  const src = fs.readFileSync(path.join(__dirname, file));
  if (lauxlib.luaL_loadbuffer(L, src, null, to_luastring('@' + file)) !== lua.LUA_OK ||
      lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exit(2);
  }
}

runFile('wowmock.lua');
runFile('loader.lua');
runFile(process.argv[2] || 'scenario.lua');
