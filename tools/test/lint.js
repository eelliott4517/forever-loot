// Syntax-check the addon as Lua 5.1 and list every global it touches, so typos
// and accidental globals stand out. Usage: node lint.js <addon dir>
const fs = require("fs");
const path = require("path");
const luaparse = require(process.env.LUAPARSE || "luaparse");

const dir = process.argv[2];
const toc = fs.readFileSync(path.join(dir, "ForeverLoot.toc"), "utf8");
const files = toc.split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));

// Globals the addon is allowed to read or write
const KNOWN = new Set(`
  _G C_Item C_Timer CreateFrame CreateFont UIParent Minimap GameTooltip DEFAULT_CHAT_FRAME UISpecialFrames
  SlashCmdList SLASH_FOREVERLOOT1 SLASH_FOREVERLOOT2 ForeverLootDB
  GetItemInfo GetItemInfoInstant GetItemIcon GetInstanceInfo UnitLevel GetTime GetCursorPosition
  IsModifierKeyDown HandleModifiedItemClick PlaySound SOUNDKIT GetNumLootItems GetLootSlotLink GetLootSourceInfo
  GameFontNormal GameFontNormalSmall GameFontNormalLarge GameFontNormalHuge GameFontHighlight GameFontHighlightSmall
  ChatFontNormal strsplit strtrim wipe tinsert UnitGUID
  ForeverLootCharDB GetItemCount IsEquippedItem time issecretvalue IsShiftKeyDown GetNumSkillLines
  GetSkillLineInfo GetSpellLink ChatEdit_InsertLink GetLootRollItemLink
  UnitClass UnitFactionGroup TooltipDataProcessor Enum ItemRefTooltip
  ipairs pairs type tostring tonumber select math table string next error pcall
`.split(/\s+/).filter(Boolean));

let failed = false;
const globals = new Map();
for (const f of files) {
  const src = fs.readFileSync(path.join(dir, f), "utf8");
  let ast;
  try {
    ast = luaparse.parse(src, { luaVersion: "5.1", scope: true, locations: true });
  } catch (e) {
    console.log(`SYNTAX ERROR ${f}: ${e.message}`);
    failed = true;
    continue;
  }
  (function walk(node) {
    if (!node || typeof node !== "object") return;
    if (Array.isArray(node)) return node.forEach(walk);
    if (node.type === "Identifier" && node.isLocal === false) {
      const key = node.name;
      if (!globals.has(key)) globals.set(key, []);
      globals.get(key).push(`${f}:${node.loc.start.line}`);
    }
    for (const k of Object.keys(node)) if (k !== "loc" && k !== "range") walk(node[k]);
  })(ast);
  // Lua 5.1 has no goto/labels, integer division or bit operators; luaparse 5.1 mode already rejects them.
  if (src.includes("\u2014")) {
    console.log(`EM DASH found in ${f}`);
    failed = true;
  }
}

const unknown = [...globals.entries()].filter(([k]) => !KNOWN.has(k));
console.log(`files: ${files.join(", ")}`);
console.log(`globals used: ${[...globals.keys()].sort().join(" ")}`);
if (unknown.length) {
  failed = true;
  console.log("UNKNOWN GLOBALS:");
  for (const [k, where] of unknown) console.log(`  ${k}  (${where.slice(0, 4).join(", ")})`);
}
console.log(failed ? "LINT FAILED" : "LINT OK");
process.exit(failed ? 1 : 0);
