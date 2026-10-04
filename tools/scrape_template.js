// Forever Loot Wowhead scrape. tools/refresh.py fills in CONFIG and writes tools/scrape_console.js.
//
// Wowhead blocks scripted clients, so this runs in a normal browser tab: open any
// https://www.wowhead.com/forever/ page, open the developer console, paste the whole
// script and press Enter. It fetches one page every few seconds (about 20 minutes in all),
// shows progress in the console, then downloads forever-loot-wowhead.json.
(async () => {
  const CONFIG = /*CONFIG*/ {};
  const DELAY_MS = CONFIG.delayMs || 5000;
  const SOD_NPCS = [200000, 250000]; // Season of Discovery NPC ids; Forever's own start around 250000

  function balanced(s, start, open, close) {
    let depth = 0, quote = null, esc = false;
    for (let i = start; i < s.length; i++) {
      const ch = s[i];
      if (quote) {
        if (esc) esc = false; else if (ch === "\\") esc = true; else if (ch === quote) quote = null;
        continue;
      }
      if (ch === '"' || ch === "'") { quote = ch; continue; }
      if (ch === open) depth++;
      else if (ch === close && --depth === 0) return s.slice(start, i + 1);
    }
    return null;
  }

  function literal(text) {
    try { return JSON.parse(text); } catch (e) { return (new Function("return " + text))(); }
  }

  // Every `new Listview({...})` on the page, by id. Pages write them either with bare
  // keys (id: 'drops', data: [...]) or as JSON ("id":"npcs","data":[...]).
  function listviews(html) {
    const out = {};
    let idx = 0;
    while ((idx = html.indexOf("new Listview(", idx)) !== -1) {
      const os = html.indexOf("{", idx);
      idx = os + 1;
      const obj = balanced(html, os, "{", "}");
      if (!obj) continue;
      try {
        const parsed = JSON.parse(obj);
        if (parsed && parsed.id && Array.isArray(parsed.data)) { out[parsed.id] = parsed.data; continue; }
      } catch (e) { /* bare keys */ }
      const id = obj.match(/["']?\bid["']?\s*:\s*["']([^"']+)["']/);
      const d = obj.search(/["']?\bdata["']?\s*:\s*\[/);
      if (!id || d < 0) continue;
      try { out[id[1]] = literal(balanced(obj, obj.indexOf("[", d), "[", "]")); } catch (e) { /* skip */ }
    }
    // List pages (all zones, say) put theirs in one JSON script instead
    const listPage = html.match(/<script type="application\/json" id="data\.page\.listPage\.listviews">([\s\S]*?)<\/script>/);
    if (listPage) {
      try {
        for (const v of JSON.parse(listPage[1])) if (v && v.id && Array.isArray(v.data) && !out[v.id]) out[v.id] = v.data;
      } catch (e) { /* skip */ }
    }
    const items = html.search(/var listviewitems\s*=\s*\[/);
    if (items >= 0 && !out.items) {
      try { out.items = literal(balanced(html, html.indexOf("[", items), "[", "]")); } catch (e) { /* skip */ }
    }
    return out;
  }

  const norm = (s) => String(s || "").toLowerCase().replace(/^the\s+/, "").replace(/[^a-z0-9]/g, "");
  const isSod = (id) => id >= SOD_NPCS[0] && id < SOD_NPCS[1];
  const sm = (x) => (x.sourcemore || []).map((m) => ({ t: m.t, ti: m.ti, n: m.n, z: m.z }));
  const slimItem = (x, counts) => {
    const o = { id: x.id, name: x.name, q: x.quality, lvl: x.level, req: x.reqlevel, slot: x.slot, sm: sm(x) };
    if (counts) { o.count = x.count; o.outof = x.outof; o.modes = x.modes || null; }
    return o;
  };
  const slimQuest = (x) => {
    const o = {
      id: x.id, name: x.name, level: x.level, req: x.reqlevel, side: x.side, cat: x.category,
      choices: x.itemchoices || [], rewards: x.itemrewards || [], xp: x.xp || 0, money: x.money || 0,
    };
    if (x.envChange && x.envChange.status && x.envChange.status !== "unchanged") {
      o.env = { status: x.envChange.status, labels: x.envChange.labels || [], lines: x.envChange.lines || [] };
    }
    return o;
  };

  function readZone(lv, html) {
    const level = html.match(/Level: (\d+)\s*-\s*(\d+)/);
    const quests = new Map();
    // (A zone page's "starts-quest" list holds items that start quests, not quests.)
    for (const q of lv.quests || []) if (!quests.has(q.id)) quests.set(q.id, slimQuest(q));
    return {
      level: level ? [+level[1], +level[2]] : null,
      drops: (lv.drops || []).map((x) => slimItem(x, false)),
      npcs: (lv.npcs || []).map((x) => ({ id: x.id, name: x.name, c: x.classification, boss: x.boss || 0 })),
      objects: (lv.objects || []).map((x) => ({ id: x.id, name: x.name })),
      quests: [...quests.values()],
    };
  }
  const readPage = (lv) => {
    const lists = {};
    for (const key of ["drops", "contains"]) if (lv[key]) lists[key] = lv[key].map((x) => slimItem(x, true));
    return { lists };
  };
  const readQuests = (lv) => ({ quests: (lv.quests || []).map(slimQuest) });
  const readItems = (lv) => ({
    items: (lv.items || []).map((x) => ({
      id: x.id, name: x.name, q: x.quality, lvl: x.level, req: x.reqlevel, slot: x.slot, src: x.source || [], sm: sm(x),
    })),
  });
  const readZoneNames = (lv) => ({ zones: (lv.zones || []).map((x) => ({ id: x.id, name: x.name })) });

  const result = { version: 2, scraped: new Date().toISOString(), pages: {}, errors: [] };
  window.__foreverLootScrape = result;
  const started = Date.now();
  let done = 0;

  const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

  // One page; when Wowhead pushes back (403/429), wait and try again
  async function get(url) {
    for (let attempt = 0; ; attempt++) {
      const r = await fetch(url, { credentials: "include" });
      if ((r.status === 403 || r.status === 429) && attempt < 3) {
        console.log(`Forever Loot scrape: Wowhead said ${r.status}, waiting ${30 * (attempt + 1)} s`);
        await sleep(30000 * (attempt + 1));
        continue;
      }
      return [r.status, await r.text()];
    }
  }

  // A job's fourth field keeps a 404 as { missing: true } (an id Wowhead has no page for)
  async function run(jobs, phase) {
    for (const [key, url, read, keepMissing] of jobs) {
      if (done > 0) await sleep(DELAY_MS);
      done++;
      try {
        const [status, html] = await get(url);
        if (status === 404 && keepMissing) result.pages[key] = { missing: true };
        else if (status !== 200) result.errors.push([key, status]);
        else result.pages[key] = read(listviews(html), html);
      } catch (e) {
        result.errors.push([key, String(e)]);
      }
      result.progress = `${phase}: ${key} (${done} pages, ${result.errors.length} errors)`;
      console.log(`Forever Loot scrape, ${result.progress}`);
    }
  }

  // 1) Instance zone pages: drops by NPC, the NPC and object lists, quests, level range
  await run([
    ...CONFIG.foreverZones.map((z) => [`forever_zone_${z}`, `/forever/zone=${z}`, readZone]),
    ...CONFIG.classicZones.map((z) => [`classic_zone_${z}`, `/classic/zone=${z}`, readZone]),
  ], "zones");

  // 2) Raid boss and loot chest pages (drop chances), found by name in the zone NPC lists
  const bossJobs = new Map();
  for (const b of CONFIG.bosses) {
    const npcs = new Set(b.npc || []), objects = new Set();
    const names = new Set(b.names.map(norm)), objectNames = new Set((b.objects || []).map(norm));
    for (const z of b.zones) {
      for (const env of ["forever", "classic"]) {
        const page = result.pages[`${env}_zone_${z}`];
        if (!page) continue;
        for (const n of page.npcs) if (names.has(norm(n.name))) npcs.add(n.id);
        for (const x of page.drops) for (const m of x.sm) if (m.t === 1 && names.has(norm(m.n))) npcs.add(m.ti);
        for (const o of page.objects) if (objectNames.has(norm(o.name))) objects.add(o.id);
      }
    }
    for (const id of npcs) {
      // Season of Discovery's versions of the bosses, and Forever-only NPCs on Classic's site, are skipped
      if (isSod(id) || (b.env === "classic" && id >= SOD_NPCS[1])) continue;
      bossJobs.set(`${b.env}_npc_${id}`, `/${b.env}/npc=${id}`);
    }
    for (const id of objects) bossJobs.set(`classic_object_${id}`, `/classic/object=${id}`);
  }
  await run([...bossJobs].map(([key, url]) => [key, url, readPage]), "boss pages");

  // 3) Dungeon quests other sites list that aren't filed under the dungeon on Wowhead
  const known = new Set();
  for (const [key, page] of Object.entries(result.pages)) {
    if (key.startsWith("forever_zone_")) for (const q of page.quests) known.add(norm(q.name));
  }
  const missing = [...new Set(CONFIG.questNames.filter((n) => !known.has(norm(n))))];
  await run(missing.map((n) => [`quest_search_${norm(n)}`, `/forever/quests/name:${encodeURIComponent(n)}`, readQuests]), "quests");

  // 4) Rare and epic items added in Forever (to spot new loot that isn't placed yet)
  await run(CONFIG.newItemRanges.map(([lo, hi, q]) =>
    [`new_items_${q}_${lo}`, `/forever/items/quality:${q}?filter=151:151;2:5;${lo}:${hi}`, readItems]), "new items");

  // 5) Recipes added in Forever, with who sells them or which quest gives them, and every zone's
  //    name (Wowhead lists a vendor's zone by id)
  await run([
    ...(CONFIG.recipeRanges || []).map(([lo, hi]) =>
      [`new_recipes_${lo}`, `/forever/items/recipes?filter=151:151;2:5;${lo}:${hi}`, readItems]),
    ["forever_zones", "/forever/zones", readZoneNames],
  ], "recipes");

  // 6) Quest pages for the instance quests the vanilla database (cMaNGOS) doesn't have, Forever's
  //    own mostly: where each starts and ends, and its series, whose other steps are fetched too
  const decode = (s) => { const t = document.createElement("textarea"); t.innerHTML = s; return t.value; };
  const ref = (s) => {
    const m = s && s.match(/\[url=\/forever\/(npc|object|item)=(\d+)[^\]]*\]([^\[]*)\[\/url\]/);
    return m ? [m[1], +m[2], decode(m[3])] : null;
  };
  const readQuestPage = (id) => (lv, html) => {
    const title = html.match(/<title>([^<]*?) - Quest - Forever/);
    const facts = html.match(/WH\.markup\.printHtml\("(\[ul\]\[li\][\s\S]*?\[\\\/ul\])"/);
    const qf = facts ? facts[1].replace(/\\\//g, "/") : "";
    const fact = (re) => { const m = qf.match(re); return m ? m[1] : null; };
    const page = {
      title: title ? decode(title[1]) : null,
      level: +fact(/\[li\]Level: (\d+)/) || null,
      req: +fact(/\[li\]Requires level (\d+)/) || null,
      side: fact(/Side: (?:\[span class=icon-(\w+)\])?/),
      type: fact(/\[li\]Type: ([^\[]+)/),
      start: ref((qf.match(/Start: (\[url=[^\]]+\][^\[]*\[\/url\])/) || [])[1]),
      end: ref((qf.match(/End: (\[url=[^\]]+\][^\[]*\[\/url\])/) || [])[1]),
    };
    const at = html.indexOf('class="series"');
    if (at >= 0) {
      const table = html.slice(at, html.indexOf("</table>", at));
      const rows = [...table.matchAll(/<tr><th>(\d+)\.<\/th><td><div>(?:<a href="\/forever\/quest=(\d+)[^"]*">([^<]*)<\/a>|<b>([^<]*)<\/b>)/g)];
      page.series = rows.map((m) => (m[2] ? [+m[2], decode(m[3])] : [id, decode(m[4])]));
    }
    return page;
  };
  const vanilla = new Set();
  for (const [first, last] of CONFIG.vanillaQuests || []) for (let i = first; i <= last; i++) vanilla.add(i);
  const questQueue = [], queued = new Set();
  const want = (id) => { if (!vanilla.has(id) && !queued.has(id)) { queued.add(id); questQueue.push(id); } };
  for (const [key, page] of Object.entries(result.pages)) {
    if (!key.startsWith("forever_zone_") && !key.startsWith("quest_search_")) continue;
    for (const q of page.quests) {
      const status = q.env && q.env.status;
      // entries without a quest category are items that start quests
      if (q.cat == null || status === "removed" || status === "unconfirmed") continue;
      want(q.id);
    }
  }
  while (questQueue.length && queued.size < 400) {
    const batch = questQueue.splice(0);
    await run(batch.map((id) => [`quest_${id}`, `/forever/quest=${id}`, readQuestPage(id), true]), "quest pages");
    for (const id of batch) for (const [sid] of (result.pages[`quest_${id}`] || {}).series || []) want(sid);
  }

  // 7) Items Forever added that start a quest (Wowhead's quest pages don't always name them), each
  //    with the quests it starts. Craftsman's Writs (profession orders) are left out.
  await run([["forever_quest_items", "/forever/items?filter=6:151;1:2;0:260000", readItems]], "quest items");
  const questItems = ((result.pages.forever_quest_items || {}).items || []).filter((x) => !/^Craftsman's Writ/.test(x.name));
  await run(questItems.map((x) => [`item_starts_${x.id}`, `/forever/item=${x.id}`,
    (lv) => ({ name: x.name, quests: (lv.starts || []).map((q) => q.id) })]), "quest items");

  result.seconds = Math.round((Date.now() - started) / 1000);
  result.progress = "done";
  console.log(`Forever Loot scrape done: ${Object.keys(result.pages).length} pages, ${result.errors.length} errors, ${result.seconds} s`);

  // Hand the result over: a download, unless something set window.__foreverLootDeliver
  const deliver = window.__foreverLootDeliver || ((data) => {
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([JSON.stringify(data)], { type: "application/json" }));
    a.download = "forever-loot-wowhead.json";
    document.body.appendChild(a);
    a.click();
  });
  await deliver(result);
})();
