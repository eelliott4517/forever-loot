// Runs smoke.lua in fengari (a Lua VM in JS). Usage: node run.js <addon dir>
const path = require("path");
const fengari = require(process.env.FENGARI || "fengari");
const { lua, lauxlib, lualib, to_luastring } = fengari;

const fs = require("fs");
const addonDir = path.resolve(process.argv[2]);
const testDir = __dirname;
// Files in TOC order, the order the client loads them
const tocFiles = fs.readFileSync(path.join(addonDir, "ForeverLoot.toc"), "utf8")
  .split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
for (const [k, v] of [["arg_addon_dir", addonDir], ["arg_test_dir", testDir], ["arg_files", tocFiles.join(",")]]) {
  lua.lua_pushstring(L, to_luastring(v));
  lua.lua_setglobal(L, to_luastring(k));
}
// Lua error with traceback
lauxlib.luaL_loadstring(L, to_luastring("return debug.traceback"));
lua.lua_call(L, 0, 1);
const tb = lua.lua_gettop(L);
if (lauxlib.luaL_loadfile(L, to_luastring(path.join(testDir, "smoke.lua"))) !== lua.LUA_OK) {
  console.error(lua.lua_tojsstring(L, -1));
  process.exit(1);
}
if (lua.lua_pcall(L, 0, 0, tb) !== lua.LUA_OK) {
  console.error(lua.lua_tojsstring(L, -1));
  process.exit(1);
}
