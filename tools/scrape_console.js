// Refresh the Wowhead data used by build_data.py.
//
// Wowhead blocks scripted HTTP clients, so this runs in your own browser:
// open https://www.wowhead.com/forever/ , open the developer console, paste this
// file and press Enter. It fetches one page every 6 seconds (about 4 minutes),
// then downloads scrape.json. Move that file to tools/raw/scrape.json and run
// `python3 tools/build_data.py`.
(async () => {
  const FOREVER = [2437, 718, 1581, 209, 719, 717, 721, 796, 491, 722, 1337, 1176, 2100, 1477, 1417, 1584,
    17803, 1583, 17804, 2557, 2017, 2057, 16919, 16611, 16732, 16544, 16560];
  const CLASSIC = [2437, 718, 1581, 209, 719, 717, 721, 796, 491, 722, 1337, 1176, 2100, 1477, 1584, 1583,
    2557, 2017, 2057];

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

  function parse(html) {
    const out = { lv: {}, comments: [] };
    let idx = 0;
    while ((idx = html.indexOf("new Listview(", idx)) !== -1) {
      const os = html.indexOf("{", idx);
      idx = os + 1;
      const obj = balanced(html, os, "{", "}");
      if (!obj) continue;
      const id = obj.match(/\bid:\s*'([^']+)'/);
      const d = obj.search(/\bdata:\s*\[/);
      if (!id || d < 0) continue;
      try { out.lv[id[1]] = JSON.parse(balanced(obj, obj.indexOf("[", d), "[", "]")); } catch (e) { /* skip */ }
    }
    const c = html.search(/var lv_comments0\s*=\s*\[/);
    if (c >= 0) try { out.comments = JSON.parse(balanced(html, html.indexOf("[", c), "[", "]")); } catch (e) { /* skip */ }
    const lvl = html.match(/Level: (\d+)\s*-\s*(\d+)/);
    out.level = lvl ? [+lvl[1], +lvl[2]] : null;
    const t = html.match(/<title>([^<]*)<\/title>/);
    out.title = t ? t[1] : null;
    return out;
  }

  const slim = (x) => ({
    id: x.id, name: x.name, q: x.quality, lvl: x.level, req: x.reqlevel, cls: x.classs, sub: x.subclass, slot: x.slot,
    sm: (x.sourcemore || []).map((m) => ({ t: m.t, ti: m.ti, n: m.n, z: m.z, bd: m.bd, dd: m.dd })),
  });

  const jobs = [
    ...FOREVER.map((z) => [`forever_zone_${z}`, `/forever/zone=${z}`, true]),
    ...CLASSIC.map((z) => [`classic_zone_${z}`, `/classic/zone=${z}`, false]),
  ];
  const results = {};
  for (const [name, url, isForever] of jobs) {
    const r = await fetch(url, { credentials: "include" });
    if (r.status !== 200) { console.warn(name, r.status); continue; }
    const p = parse(await r.text());
    results[name] = {
      title: p.title, level: p.level,
      drops: (p.lv.drops || []).map(slim),
      npcs: (p.lv.npcs || []).map((x) => ({ id: x.id, name: x.name, c: x.classification, min: x.minlevel, max: x.maxlevel, boss: x.boss || 0 })),
      comments: isForever ? p.comments.map((c) => ({ user: c.user, date: c.date, rating: c.rating, body: c.body })) : [],
    };
    console.log(`${Object.keys(results).length}/${jobs.length} ${name}`);
    await new Promise((res) => setTimeout(res, 6000));
  }
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(results)], { type: "application/json" }));
  a.download = "scrape.json";
  a.click();
})();
