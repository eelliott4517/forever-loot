"""Draws the Forever Loot window the way WoW: Forever draws it, so the look can be checked without the
game. The addon runs in a strict Lua 5.1 mock (wowmock.lua, with Blizzard's templates rebuilt from
their XML in templates.lua), and every frame, texture and line of text it makes is drawn with the
game's own art and font, fetched from wago.tools by art.py and cached in tools/preview/.art (only the
first run needs the network). Text is measured with that font, so wrapping and "..." truncation come
out as in the game. Adapted from Forever Messenger's tools/preview.

    python3 -m venv /tmp/wowlua && /tmp/wowlua/bin/pip install lupa pillow
    /tmp/wowlua/bin/python tools/preview/preview.py [scenario ...] [--out file.png] [--scale N]

Scenarios (all by default), each for an Alliance Human Rogue at level 20 who has turned in quests 65,
132 and 135 of The Defias Brotherhood and has 141 in the quest log:
  quests-dm        the Quests tab on The Deadmines, The Defias Brotherhood (166) open
  quests-todo      the Quests tab's first page, "Quests you can do"
  dungeons-dm      the Dungeons tab on The Deadmines, its Quests section and The Defias Brotherhood
                   open, scrolled to the Quests header
  quests-tooltip   quests-dm with the mouse over The Defias Brotherhood's header, its tooltip showing
  dungeons-bosses  the Dungeons tab on The Deadmines, every boss closed but the first

Each is written to tools/preview/preview-<scenario>.png: the 880 x 600 window with its side tabs
(and the tooltip), at --scale pixels per UI unit (2 by default; 1 is the game at UI scale 1). Each run
also prints "layout:" lines for what the drawing shows going wrong: text cut short with "...", text
wrapping inside a one-line box, text drawn over other text or under a button that isn't its own.
"""
import argparse
import csv
import os
import re
import sys

import lupa.lua51 as lua51
from PIL import Image, ImageChops, ImageDraw, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import art  # noqa: E402

TOOLS = os.path.dirname(HERE)
SCENARIOS = ["quests-dm", "quests-todo", "dungeons-dm", "quests-tooltip", "dungeons-bosses"]
S = 2  # pixels per UI unit (--scale)

# GlobalColor (1.60.1.70205): NORMAL_FONT_COLOR FFD200, DISABLED_FONT_COLOR 808080, TOOLTIP_DEFAULT_BACKGROUND_COLOR 171730
NORMAL, WHITE, GREY = (1, 210 / 255, 0), (1, 1, 1), (0.5, 0.5, 0.5)
DISABLED = (128 / 255, 128 / 255, 128 / 255)
TOOLTIP_BG = (23 / 255, 23 / 255, 48 / 255)
# Blizzard_Fonts_Shared: name -> (height, color, shadow, justifyH). The SystemFont_Shadow_* families
# carry a black 1, -1 shadow; the tooltip fonts (GameTooltipHeader, Tooltip_Med) have none.
FONTS = {
    "GameFontNormal": (12, NORMAL, True, None), "GameFontNormalLeft": (12, NORMAL, True, "LEFT"),
    "GameFontNormalSmall": (10, NORMAL, True, None), "GameFontNormalLarge": (16, (1, 0.82, 0), True, None),
    "GameFontNormalHuge": (20, (1, 0.82, 0), True, None), "GameFontHighlight": (12, WHITE, True, None),
    "GameFontHighlightSmall": (10, WHITE, True, None), "GameFontDisable": (12, GREY, True, None),
    "GameFontDisableSmall": (10, DISABLED, True, None), "GameFontGreenSmall": (10, (0.1, 1, 0.1), True, None),
    "ChatFontNormal": (14, WHITE, True, None),
    "GameTooltipHeaderText": (14, WHITE, False, "LEFT"), "GameTooltipText": (12, WHITE, False, "LEFT"),
    "GameTooltipTextSmall": (10, WHITE, False, "LEFT"),
}
MAP_OVERRIDES = {1436: "Westfall", 1453: "Stormwind City", 1433: "Redridge Mountains", 1429: "Elwynn Forest"}

_fonts = {}
missing = set()


def font(size):
    key = (size, S)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(art.font(), int(round(size * S)))
    return _fonts[key]


def warn(what):
    if what not in missing:
        missing.add(what)
        print("  warning:", what)


# ------------------------------------------------------------------ text: codes, wrapping, measuring
TOKEN = re.compile(
    r"\|c([0-9a-fA-F]{8})|\|r"
    r"|\|A:([^:|]+)(?::(-?\d+))?(?::(-?\d+))?(?::(-?\d+))?(?::(-?\d+))?[^|]*\|a"
    r"|\|T([^:|]+)(?::(-?\d+))?(?::(-?\d+))?(?::(-?\d+))?(?::(-?\d+))?[^|]*\|t"
    r"|\|H[^|]*\|h|\|h|\|\||\|n|\n|[^|\n]+|\|")


def icon_size(kind, name, h, w, size):
    """An inline |A or |T icon's height and width: 0 means the line's height, and a 0 width keeps
    a |T square and an |A at its atlas's shape."""
    h = h or size
    if not w:
        found = art.atlas(name) if kind == "atlas" else None
        w = h * found[1] / found[2] if found and found[2] else h
    return h, w


def runs(text, base, size):
    """(kind, value, color) pieces: 'text', 'icon' (value = (kind, name, h, w, dy)) or 'newline'."""
    out, color = [], base
    for m in TOKEN.finditer(text):
        tok = m.group(0)
        if m.group(1):
            h = m.group(1)
            color = (int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, int(h[6:8], 16) / 255)
        elif tok == "|r":
            color = base
        elif m.group(2):
            h, w = icon_size("atlas", m.group(2), int(m.group(3) or 0), int(m.group(4) or 0), size)
            out.append(("icon", ("atlas", m.group(2), h, w, int(m.group(6) or 0)), color))
        elif m.group(7):
            h, w = icon_size("file", m.group(7), int(m.group(8) or 0), int(m.group(9) or 0), size)
            out.append(("icon", ("file", m.group(7), h, w, int(m.group(11) or 0)), color))
        elif tok.startswith("|H") or tok == "|h":
            continue   # a link's code; only its [text] shows
        elif tok in ("\n", "|n"):
            out.append(("newline", None, color))
        elif tok == "||":
            out.append(("text", "|", color))
        else:
            out.append(("text", tok, color))
    return out


def piece_width(f, kind, value):
    return value[3] if kind == "icon" else f.getlength(value) / S


def layout_lines(text, size, width, base=WHITE):
    """Greedy word wrap at `width` (0: no wrapping). Returns lines of [(kind, value, color, x)] and
    each line's width, in UI units."""
    f = font(size)
    # each word: its pieces, and the run of spaces before it (the game draws every space, so the
    # addon's "   ·   " separators keep their width; a run where a line wraps is dropped)
    words, cur, gap = [], [], ""
    for kind, value, color in runs(text, base, size):
        if kind == "newline":
            if cur:
                words.append((cur, gap))
            words.append((None, ""))
            cur, gap = [], ""
        elif kind == "icon":
            if cur:
                words.append((cur, gap))
                gap = ""
            words.append(([("icon", value, color)], gap))
            cur, gap = [], ""
        else:
            for p in re.split(r"( +)", value):
                if not p:
                    continue
                if p.startswith(" "):
                    if cur:
                        words.append((cur, gap))
                        cur, gap = [], ""
                    gap += p
                else:
                    cur.append(("text", p, color))
    if cur:
        words.append((cur, gap))
    lines, widths, line, x = [], [], [], 0
    for pieces, before in words:
        if pieces is None:
            lines.append(line); widths.append(x); line, x = [], 0
            continue
        w = sum(piece_width(f, k, v) for k, v, _ in pieces)
        # spaces count between words, and before the first word of the text
        gap = f.getlength(before) / S if before and (line or not lines) else 0
        if width and line and x + gap + w > width + 0.5:
            lines.append(line); widths.append(x); line, x, gap = [], 0, 0
        x += gap
        for kind, value, color in pieces:
            line.append((kind, value, color, x))
            x += piece_width(f, kind, value)
    lines.append(line); widths.append(x)
    return lines, widths


def truncated(line, size, width, more=False):
    """A line cut to fit its width, ending in "...", as the game shortens a font string that doesn't
    wrap. `more`: text was left out after this line, so it ends in "..." even when it fits."""
    f = font(size)
    dots = f.getlength("...") / S
    out, x = [], 0
    if more:
        line = line + [("text", "\0", line[-1][2] if line else WHITE, float("inf"))]
    for kind, value, color, dx in line:
        if kind == "icon":
            if dx + value[3] + dots > width:
                out.append(("text", "...", color, x))
                return out, x + dots
            out.append((kind, value, color, dx)); x = dx + value[3]
            continue
        keep = ""
        for ch in value:
            if dx + (f.getlength(keep + ch) / S) + dots > width:
                break
            keep += ch
        if keep:
            out.append(("text", keep, color, dx)); x = dx + f.getlength(keep) / S
        if keep != value:
            out.append(("text", "...", color, x))
            return out, x + dots
    return out, x


def font_of(name):
    return FONTS.get(name) or (warn(f"no font {name} in FONTS") or FONTS["GameFontHighlight"])


def measure(fontname, text, wrap_width, spacing):
    """MOCK.Measure: a string's width and height in UI units, wrapped at wrap_width (0: not)."""
    size = font_of(fontname)[0]
    if not text:
        return 0, 0
    lines, widths = layout_lines(text, size, wrap_width or 0)
    return max(widths), len(lines) * size + (len(lines) - 1) * spacing


# ------------------------------------------------------------------ the scene, from the addon in the mock
SETUP = r"""
local DIR, SCENARIO, MEASURE, MAPS = ...
assert(loadfile(DIR .. "/preview/wowmock.lua"))(DIR)
MOCK.Measure = function(font, text, width, spacing) return MEASURE(font, text, width, spacing) end
-- An Alliance Human Rogue at level 20: the first three quests of The Defias Brotherhood turned in,
-- the fourth (141) in the quest log
MOCK.side, MOCK.classFile, MOCK.raceID, MOCK.level = "Alliance", "ROGUE", 1, 20
for id, name in pairs(MAPS) do MOCK.mapNames[id] = name end
MOCK.done[65], MOCK.done[132], MOCK.done[135] = true, true, true
MOCK.log[141] = true
local ns = {}
for line in io.lines(DIR .. "/../ForeverLoot/ForeverLoot.toc") do
	local file = line:match("^%s*([^#%s].-%.lua)%s*$")
	if file then assert(loadfile(DIR .. "/../ForeverLoot/" .. file))("ForeverLoot", ns) end
end
MOCK.Fire("ADDON_LOADED", "ForeverLoot")
MOCK.Fire("PLAYER_LOGIN")
SlashCmdList.FOREVERLOOT("")
local UI, DM = ns.UI, ns.DungeonByKey.DM
local hovered
local function Has(id)
	for _, s in ipairs(UI.sectionIds or {}) do if s == id then return true end end
	return false
end
if SCENARIO == "quests-dm" or SCENARIO == "quests-tooltip" then
	UI:OpenQuest(DM, 166)
elseif SCENARIO == "quests-todo" then
	-- click the Quests side tab, then the list's first row
	for _, tab in ipairs(UI.tabs) do if tab.key == "quests" then tab:MockClick() end end
	UI.listRows[1]:Click()
elseif SCENARIO == "dungeons-dm" then
	-- its Quests section open, and in it The Defias Brotherhood (a quest bar is a section: its
	-- "Starts:" line and rewards show once it's open), scrolled to the Quests header
	UI:Select(DM)
	UI.sections["d:DM:quests"] = true
	UI:Refresh()
	assert(Has("d:DM:q:166"), "no section d:DM:q:166 for The Defias Brotherhood on the Dungeons tab")
	UI.sections["d:DM:q:166"] = true
	UI:Refresh()
	for _, e in ipairs(UI.entries) do
		if e.data and e.data.id == "d:DM:quests" then UI.loot:ScrollTo(e.y) end
	end
elseif SCENARIO == "dungeons-bosses" then
	-- every boss closed but the first, so the closed headers show their item counts
	UI:Select(DM)
	local first = DM.bosses[1]
	local id = "d:DM:b:" .. (first.wing and (first.wing .. ":") or "") .. first.name
	assert(Has(id), "no section " .. id .. " for the first boss")
	UI.sections[id] = true
	UI:Refresh()
else
	error("no scenario " .. tostring(SCENARIO))
end
if SCENARIO == "quests-tooltip" then
	for i = 1, UI.used.qhead or 0 do
		local row = UI.pools.qhead[i]
		if row.quest and row.quest.id == 166 then hovered = row end
	end
	assert(hovered, "The Defias Brotherhood's header isn't on screen")
	MOCK.Hover(hovered)
end
-- name the rows for the layout checks
for kind, pool in pairs(UI.pools) do for _, w in ipairs(pool) do w._rowKind = kind end end
for _, row in ipairs(UI.listRows) do row._rowKind = "list row" end
for _, tab in ipairs(UI.tabs) do tab._rowKind = "side tab" end
UI.header._rowKind = "header"
UI.searchBox._rowKind = "search box"
for _, d in pairs(UI.filterButtons) do d._rowKind = "dropdown" end
for _, t in pairs(UI.toggles) do t._rowKind = "checkbox" end
local L = MOCK.layout
L.UpdateScrollBars()
local tip
if GameTooltip:IsShown() and GameTooltip:GetOwner() then
	tip = { rows = GameTooltip._rows, owner = L.Box(GameTooltip:GetOwner()), anchor = GameTooltip._anchor, offset = GameTooltip._offset }
end
local window = L.Box(ForeverLootFrame)
local items, buttons = L.Dump({ ForeverLootFrame }, hovered)
return items, tip, window, buttons
"""

# ------------------------------------------------------------------ drawing
LAYOUTS = {
    # NineSliceLayouts.TooltipDefaultLayout (draw_tooltip draws its Center piece)
    "TooltipDefaultLayout": {
        "TopLeftCorner": ("Tooltip-NineSlice-CornerTopLeft", 0, 0), "TopRightCorner": ("Tooltip-NineSlice-CornerTopRight", 0, 0),
        "BottomLeftCorner": ("Tooltip-NineSlice-CornerBottomLeft", 0, 0), "BottomRightCorner": ("Tooltip-NineSlice-CornerBottomRight", 0, 0),
        "TopEdge": "_Tooltip-NineSlice-EdgeTop", "BottomEdge": "_Tooltip-NineSlice-EdgeBottom",
        "LeftEdge": "!Tooltip-NineSlice-EdgeLeft", "RightEdge": "!Tooltip-NineSlice-EdgeRight",
    },
    # NineSliceLayouts.InsetFrameTemplate
    "InsetFrameTemplate": {
        "TopLeftCorner": ("UI-Frame-InnerTopLeft", 0, 0), "TopRightCorner": ("UI-Frame-InnerTopRight", 0, 0),
        "BottomLeftCorner": ("UI-Frame-InnerBotLeftCorner", 0, -1), "BottomRightCorner": ("UI-Frame-InnerBotRight", 0, -1),
        "TopEdge": "_UI-Frame-InnerTopTile", "BottomEdge": "_UI-Frame-InnerBotTile",
        "LeftEdge": "!UI-Frame-InnerLeftTile", "RightEdge": "!UI-Frame-InnerRightTile",
    },
    # NineSliceLayouts.PortraitFrameTemplate, with Camelot's NineSliceLayoutOverrides applied
    "PortraitFrameTemplate": {
        "TopLeftCorner": ("UI-Frame-PortraitMetal-CornerTopLeft", -13, 16),
        "TopRightCorner": ("UI-Frame-Metal-CornerTopRight", 4 - 2, 16),
        "BottomLeftCorner": ("UI-Frame-Metal-CornerBottomLeft", -13, -8),
        "BottomRightCorner": ("UI-Frame-Metal-CornerBottomRight", 4 - 2, -8),
        "TopEdge": "_UI-Frame-Metal-EdgeTop", "BottomEdge": "_UI-Frame-Metal-EdgeBottom",
        "LeftEdge": "!UI-Frame-Metal-EdgeLeft", "RightEdge": "!UI-Frame-Metal-EdgeRight",
    },
}


class Canvas:
    def __init__(self, bounds):
        self.ox, self.oy = bounds[0], bounds[1]
        self.w, self.h = int(round((bounds[2] - bounds[0]) * S)), int(round((bounds[3] - bounds[1]) * S))
        self.img = Image.new("RGBA", (self.w, self.h), (22, 24, 28, 255))

    def px(self, x, y):
        return int(round((x - self.ox) * S)), int(round((y - self.oy) * S))

    def mask_rect(self, clip):
        x0, y0 = self.px(clip[0], clip[1])
        x1, y1 = self.px(clip[2], clip[3])
        m = Image.new("L", self.img.size, 0)
        if x1 > x0 and y1 > y0:
            ImageDraw.Draw(m).rectangle([x0, y0, x1 - 1, y1 - 1], fill=255)
        return m

    def paste(self, tile, box, clip=None, blend=None, alpha_mask=None):
        """Draws an RGBA image into the UI-unit box, cut to clip (and to alpha_mask, a full-canvas L image)."""
        x0, y0 = self.px(box[0], box[1])
        x1, y1 = self.px(box[2], box[3])
        if x1 <= x0 or y1 <= y0:
            return
        if tile.size != (x1 - x0, y1 - y0):
            tile = tile.resize((x1 - x0, y1 - y0), Image.LANCZOS)
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        layer.paste(tile, (x0, y0))
        a = layer.getchannel("A")
        if clip:
            a = ImageChops.multiply(a, self.mask_rect(clip))
        if alpha_mask is not None:
            a = ImageChops.multiply(a, alpha_mask)
        layer.putalpha(a)
        if blend == "ADD":
            rgb = Image.merge("RGB", [ImageChops.multiply(c, a) for c in layer.split()[:3]])
            out = ImageChops.add(self.img.convert("RGB"), rgb)
            out.putalpha(self.img.getchannel("A"))
            self.img = out
        else:
            self.img.alpha_composite(layer)


def tinted(img, vcolor=None, alpha=1.0, desaturated=False):
    img = img.copy()
    if desaturated:
        a = img.getchannel("A")
        g = ImageOps.grayscale(img.convert("RGB"))
        img = Image.merge("RGBA", (g, g, g, a))
    if vcolor:
        r, g, b = (list(vcolor) + [1, 1, 1])[:3]
        chans = img.split()
        img = Image.merge("RGBA", [chans[0].point(lambda v: v * r), chans[1].point(lambda v: v * g),
                                   chans[2].point(lambda v: v * b), chans[3]])
        if len(vcolor) > 3 and vcolor[3] is not None:
            alpha *= vcolor[3]
    if alpha < 0.999:
        img.putalpha(img.getchannel("A").point(lambda v: v * alpha))
    return img


def cut(img, coords):
    """SetTexCoord on an image: left, right, top, bottom as fractions (flipped when reversed)."""
    if not coords:
        return img
    if len(coords) == 8:  # corner coords: take the upper left and lower right corners
        coords = [coords[0], coords[6], coords[1], coords[7]]
    l, r, t, b = coords
    W, H = img.size
    x0, x1 = sorted((l * W, r * W))
    y0, y1 = sorted((t * H, b * H))
    part = img.crop((int(round(x0)), int(round(y0)), max(int(round(x0)) + 1, int(round(x1))), max(int(round(y0)) + 1, int(round(y1)))))
    if l > r:
        part = ImageOps.mirror(part)
    if t > b:
        part = ImageOps.flip(part)
    return part


def tiled(img, unit_w, unit_h, box, horiz, vert):
    """Repeats the art at its own size (in UI units) along the tiled directions and stretches the others."""
    bw, bh = max(1, int(round((box[2] - box[0]) * S))), max(1, int(round((box[3] - box[1]) * S)))
    tw = max(1, int(round(unit_w * S))) if horiz else bw
    th = max(1, int(round(unit_h * S))) if vert else bh
    piece = img.resize((tw, th), Image.LANCZOS)
    out = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    for y in range(0, bh, th):
        for x in range(0, bw, tw):
            out.paste(piece, (x, y))
    return out


def sliced(img, aw, ah, margins, out_w, out_h):
    """Draws a sliced atlas at a size: the margins keep their size, the middle stretches or tiles."""
    L, T, R, B, tile = margins
    sx, sy = img.width / aw, img.height / ah
    dl, dr, dt, db = L * S, R * S, T * S, B * S
    if dl + dr > out_w:
        k = out_w / (dl + dr); dl, dr = dl * k, dr * k
    if dt + db > out_h:
        k = out_h / (dt + db); dt, db = dt * k, db * k
    xs = [0, round(L * sx), img.width - round(R * sx), img.width]
    ys = [0, round(T * sy), img.height - round(B * sy), img.height]
    dx = [0, round(dl), out_w - round(dr), out_w]
    dy = [0, round(dt), out_h - round(db), out_h]
    out = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    for i in range(3):
        for j in range(3):
            src = (xs[i], ys[j], xs[i + 1], ys[j + 1])
            w, h = dx[i + 1] - dx[i], dy[j + 1] - dy[j]
            if src[2] <= src[0] or src[3] <= src[1] or w <= 0 or h <= 0:
                continue
            piece = img.crop(src)
            if tile and (i == 1 or j == 1):
                nw = max(1, round(piece.width * S / sx)) if i == 1 else w
                nh = max(1, round(piece.height * S / sy)) if j == 1 else h
                piece = piece.resize((nw, nh), Image.LANCZOS)
                cell = Image.new("RGBA", (w, h), (0, 0, 0, 0))
                for y in range(0, h, nh):
                    for x in range(0, w, nw):
                        cell.paste(piece, (x, y))
                piece = cell
            else:
                piece = piece.resize((w, h), Image.LANCZOS)
            out.paste(piece, (dx[i], dy[j]))
    return out


def load_file(path):
    """A texture file by path or file id, as the game loads it."""
    try:
        if isinstance(path, (int, float)):
            return art.by_fdid(int(path))
        img = art.file(path)
    except OSError as e:
        warn(f"couldn't fetch {path} from wago.tools ({e}): drawn as nothing; run again to retry")
        return None
    if img is None:
        warn(f"wago.tools has no file {path} for build {art.BUILD}: drawn as nothing")
    return img


def atlas_crop_fractions(name):
    """Where an atlas sits in its file, as tex coords: the crop a later SetTexture keeps."""
    info = art.atlas_info(name)
    aw, ah = int(info["atlas"]["AtlasWidth"]), int(info["atlas"]["AtlasHeight"])
    l, t, r, b = info["box"]
    return [l / aw, r / aw, t / ah, b / ah]


def texture_image(item, box):
    """The image a texture item shows, sized for its box (None if it shows nothing)."""
    if item.get("color"):
        c = item["color"]
        return Image.new("RGBA", (1, 1), tuple(int(round(v * 255)) for v in c[:3]) + (int(round(c[3] * 255)),))
    if item.get("atlas"):
        name = item["atlas"]
        found = art.atlas(name)
        if not found:
            warn(f"the client has no atlas {name}")
            return None
        img, aw, ah = found
        coords = item.get("coords")
        img = cut(img, coords)
        if coords and len(coords) == 4:
            aw, ah = aw * abs(coords[1] - coords[0]), ah * abs(coords[3] - coords[2])
        horiz = name.startswith("_") or item.get("htile")
        vert = name.startswith("!") or item.get("vtile")
        if horiz or vert:
            return tiled(img, aw, ah, box, horiz, vert)
        margins = art.slices(name)
        if margins and not coords:
            return sliced(img, aw, ah, margins, max(1, round((box[2] - box[0]) * S)), max(1, round((box[3] - box[1]) * S)))
        return img
    if item.get("file") is not None:
        img = load_file(item["file"])
        if img is None:
            return None
        if item.get("staleCrop"):
            img = cut(img, atlas_crop_fractions(item["staleCrop"]))
        img = cut(img, item.get("coords"))
        if item.get("htile") or item.get("vtile"):
            return tiled(img, img.width, img.height, box, item.get("htile"), item.get("vtile"))
        return img
    return None


def mask_image(cv, masks):
    """The alpha the masks leave: each mask's art in its box, nothing outside it."""
    out = None
    for m in masks:
        img = art.atlas(m["atlas"])[0] if m.get("atlas") else load_file(m["file"])
        full = Image.new("L", cv.img.size, 0)
        if img is not None:
            mx0, my0 = cv.px(m["box"][0], m["box"][1])
            mx1, my1 = cv.px(m["box"][2], m["box"][3])
            if mx1 > mx0 and my1 > my0:
                full.paste(img.getchannel("A").resize((mx1 - mx0, my1 - my0), Image.LANCZOS), (mx0, my0))
        out = full if out is None else ImageChops.multiply(out, full)
    return out


def draw_texture(cv, item):
    box = item["box"]
    img = texture_image(item, box)
    if img is None:
        return
    img = tinted(img, item.get("vcolor"), item.get("alpha", 1), item.get("desaturated"))
    alpha_mask = mask_image(cv, item["masks"]) if item.get("masks") else None
    cv.paste(img, box, item.get("clip"), item.get("blend"), alpha_mask)


def draw_nineslice(cv, item):
    lay = LAYOUTS.get(item["layout"])
    if not lay:
        warn(f"no NineSlice layout {item['layout']}")
        return
    L, T, R, B = item["box"]
    boxes = {}
    for key, point in (("TopLeftCorner", "TL"), ("TopRightCorner", "TR"), ("BottomLeftCorner", "BL"), ("BottomRightCorner", "BR")):
        name, x, y = lay[key]
        img, w, h = art.atlas(name)
        ax = L + x if "L" in point else R + x
        ay = T - y if "T" in point else B - y
        x0 = ax if "L" in point else ax - w
        y0 = ay if "T" in point else ay - h
        boxes[key] = (x0, y0, x0 + w, y0 + h)
        cv.paste(tinted(img, alpha=item.get("alpha", 1)), boxes[key], item.get("clip"))
    tl, tr, bl, br = boxes["TopLeftCorner"], boxes["TopRightCorner"], boxes["BottomLeftCorner"], boxes["BottomRightCorner"]
    for key, box in (("TopEdge", (tl[2], tl[1], tr[0], None)), ("BottomEdge", (bl[2], None, br[0], bl[3])),
                     ("LeftEdge", (tl[0], tl[3], None, bl[1])), ("RightEdge", (None, tr[3], tr[2], br[1]))):
        name = lay[key]
        img, w, h = art.atlas(name)
        x0, y0, x1, y1 = box
        if key == "TopEdge":
            y1 = y0 + h
        elif key == "BottomEdge":
            y0 = y1 - h
        elif key == "LeftEdge":
            x1 = x0 + w
        else:
            x0 = x1 - w
        full = (x0, y0, x1, y1)
        if x1 > x0 and y1 > y0:
            cv.paste(tinted(tiled(img, w, h, full, name.startswith("_"), name.startswith("!")), alpha=item.get("alpha", 1)), full, item.get("clip"))


def draw_text(cv, item):
    """Draws a font string; returns where its text landed and whether it was cut short."""
    fontname = item.get("font") or "GameFontHighlight"
    size, base, shadow, font_justify = font_of(fontname)
    if item.get("color"):
        base = tuple(item["color"][:3])
    box = item["box"]
    bw = box[2] - box[0]
    spacing = item.get("spacing") or 0
    lines, widths = layout_lines(item["text"], size, bw if item.get("wrap") else 0, base)
    full = max(widths) if not item.get("wrap") else max(layout_lines(item["text"], size, 0, base)[1])  # on one line
    cut_short = False
    if not item.get("wrap") and bw > 0:
        # a string that doesn't wrap ends in "..." where its width runs out
        cut_lines = [truncated(line, size, bw) if w > bw + 0.5 else (line, w) for line, w in zip(lines, widths)]
        cut_short = any(w > bw + 0.5 for w in widths)
        lines, widths = [c[0] for c in cut_lines], [c[1] for c in cut_lines]
    elif item.get("wrap") and item.get("fixedHeight"):
        # a wrapping string of fixed height shows the lines that fit (at least one), the last cut with "..."
        fit = max(1, int((box[3] - box[1] + spacing + 0.5) // (size + spacing)))
        if len(lines) > fit:
            cut_short = True
            lines, widths = lines[:fit], widths[:fit]
            lines[-1], widths[-1] = truncated(lines[-1], size, bw, more=True)
    total = len(lines) * size + (len(lines) - 1) * spacing
    justify_v = item.get("justifyV") or "MIDDLE"
    top = box[1] if justify_v == "TOP" else (box[3] - total if justify_v == "BOTTOM" else box[1] + ((box[3] - box[1]) - total) / 2)
    f = font(size)
    alpha = item.get("alpha", 1)
    layer = Image.new("RGBA", cv.img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    justify = item.get("justify") or font_justify or "CENTER"
    drawn = None
    for i, (line, lw) in enumerate(zip(lines, widths)):
        y = top + i * (size + spacing)
        x = box[0] if justify == "LEFT" else (box[2] - lw if justify == "RIGHT" else (box[0] + box[2] - lw) / 2)
        if line:
            r = (x, y, x + lw, y + size)
            drawn = r if drawn is None else (min(drawn[0], r[0]), min(drawn[1], r[1]), max(drawn[2], r[2]), max(drawn[3], r[3]))
        base_y = y + size * 0.86
        for kind, value, color, dx in line:
            if kind == "icon":
                ikind, name, ih, iw, dy = value
                img = art.atlas(name)[0] if ikind == "atlas" and art.atlas(name) else (load_file(name) if ikind == "file" else None)
                if img is not None:
                    ax, ay = cv.px(x + dx, y + (size - ih) / 2 - dy)
                    img = tinted(img.resize((max(1, int(round(iw * S))), max(1, int(round(ih * S)))), Image.LANCZOS), alpha=alpha)
                    layer.alpha_composite(img, (max(0, ax), max(0, ay)))
                continue
            px, py = cv.px(x + dx, base_y)
            rgb = tuple(int(round(c * 255)) for c in color[:3])
            if shadow:
                d.text((px + S, py + S), value, font=f, fill=(0, 0, 0, int(255 * alpha)), anchor="ls")
            d.text((px, py), value, font=f, fill=rgb + (int(255 * alpha),), anchor="ls")
    if item.get("clip"):
        layer.putalpha(ImageChops.multiply(layer.getchannel("A"), cv.mask_rect(item["clip"])))
    cv.img.alpha_composite(layer)
    return {"drawn": drawn, "cut": cut_short, "needed": full, "width": bw, "lines": len(lines)}


# GameTooltip: 10 in from each edge, 2 between lines, the first line in GameTooltipHeaderText and the
# rest in GameTooltipText. Lines added with wrap wrap at the width of the widest line that doesn't,
# but at least TIP_WRAP (an estimate of the client's word-wrap minimum, which isn't in the Lua).
TIP_PAD, TIP_GAP, TIP_WRAP, TIP_RIGHT_GAP = 10, 2, 270, 20


def tooltip_layout(tip):
    rows = tip["rows"]
    natural, wrapping = 0, 0
    for i, r in enumerate(rows):
        fontname = "GameTooltipHeaderText" if i == 0 else "GameTooltipText"
        w = measure(fontname, r["left"], 0, 0)[0]
        if r.get("right"):
            w += TIP_RIGHT_GAP + measure(fontname, r["right"], 0, 0)[0]
        if r.get("wrap"):
            wrapping = max(wrapping, w)
        else:
            natural = max(natural, w)
    width = max(natural, min(wrapping, TIP_WRAP))
    laid, h = [], 0
    for i, r in enumerate(rows):
        fontname = "GameTooltipHeaderText" if i == 0 else "GameTooltipText"
        size = FONTS[fontname][0]
        lines, _ = layout_lines(r["left"], size, width if r.get("wrap") else 0)
        laid.append((r, fontname, size, len(lines), h))
        h += len(lines) * size + (len(lines) - 1) * TIP_GAP + TIP_GAP
    return laid, width + 2 * TIP_PAD, h - TIP_GAP + 2 * TIP_PAD


def tooltip_box(tip):
    _, w, h = tooltip_layout(tip)
    o = tip["owner"]
    dx, dy = (tip.get("offset") or [0, 0])[:2]
    anchor = tip.get("anchor")
    if anchor == "ANCHOR_RIGHT":     # its bottom left at the owner's top right
        return (o[2] + dx, o[1] - dy - h, o[2] + dx + w, o[1] - dy)
    if anchor == "ANCHOR_LEFT":      # its bottom right at the owner's top left
        return (o[0] + dx - w, o[1] - dy - h, o[0] + dx, o[1] - dy)
    if anchor == "ANCHOR_TOP":
        cx = (o[0] + o[2]) / 2 + dx
        return (cx - w / 2, o[1] - dy - h, cx + w / 2, o[1] - dy)
    warn(f"tooltip anchor {anchor} drawn as ANCHOR_RIGHT")
    return (o[2] + dx, o[1] - dy - h, o[2] + dx + w, o[1] - dy)


def draw_tooltip(cv, tip):
    laid, w, h = tooltip_layout(tip)
    box = tooltip_box(tip)
    # the NineSlice's Center: its atlas, 4 into each 7-wide corner, in TOOLTIP_DEFAULT_BACKGROUND_COLOR
    center = art.atlas("Tooltip-NineSlice-Center")
    if center:
        cv.paste(tinted(center[0], list(TOOLTIP_BG) + [1]), (box[0] + 3, box[1] + 3, box[2] - 3, box[3] - 3))
    draw_nineslice(cv, {"layout": "TooltipDefaultLayout", "box": box})
    for r, fontname, size, n, y in laid:
        top = box[1] + TIP_PAD + y
        height = n * size + (n - 1) * TIP_GAP
        draw_text(cv, {"box": (box[0] + TIP_PAD, top, box[2] - TIP_PAD, top + height), "text": r["left"], "font": fontname,
                       "justify": "LEFT", "wrap": bool(r.get("wrap")), "spacing": TIP_GAP, "color": r["lc"]})
        if r.get("right"):
            draw_text(cv, {"box": (box[0] + TIP_PAD, top, box[2] - TIP_PAD, top + size), "text": r["right"],
                           "font": fontname, "justify": "RIGHT", "color": r["rc"]})


# ------------------------------------------------------------------ checks and the run
def check_atlases():
    """atlases.txt has to match the client: every name in its table, at the size it gives."""
    for line in open(os.path.join(HERE, "atlases.txt")):
        if not line.strip() or line.startswith("#"):
            continue
        name, w, h = line.split()
        info = art.atlas_info(name)
        if not info:
            warn(f"atlases.txt lists {name}, which the client doesn't have")
        elif (round(info["w"], 2), round(info["h"], 2)) != (round(float(w), 2), round(float(h), 2)):
            warn(f"atlases.txt gives {name} as {w} x {h}; the client has {info['w']:g} x {info['h']:g}")


def map_names():
    """Zone names for C_Map.GetMapInfo: the client's UiMap table, and the four the scenarios name."""
    names = {}
    path = os.path.join(TOOLS, "raw", "db2", "UiMap.csv")
    with open(path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            names[int(row["ID"])] = row["Name_lang"]
    names.update(MAP_OVERRIDES)
    return names


def plain(v):
    if lua51.lua_type(v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys):
            return [plain(v[k]) for k in sorted(keys)]
        return {k: plain(v[k]) for k in keys}
    return v


def render(scenario, out):
    rt = lua51.LuaRuntime(unpack_returned_tuples=True)
    maps = rt.table_from(map_names())
    items, tip, window, buttons = rt.eval("function(src, d, s, m, maps) return assert(loadstring(src))(d, s, m, maps) end")(
        SETUP, TOOLS, scenario, measure, maps)
    items = plain(items) or []
    tip = plain(tip) if tip is not None else None
    window = plain(window)
    buttons = plain(buttons) or []

    def shown(it):
        b, c = it["box"], it.get("clip")
        if c:
            b = (max(b[0], c[0]), max(b[1], c[1]), min(b[2], c[2]), min(b[3], c[3]))
        return b if b[2] > b[0] and b[3] > b[1] else None
    boxes = [b for b in (shown(it) for it in items) if b]
    if tip:
        boxes.append(tooltip_box(tip))
    pad = 6
    bounds = (min(b[0] for b in boxes) - pad, min(b[1] for b in boxes) - pad, max(b[2] for b in boxes) + pad, max(b[3] for b in boxes) + pad)
    cv = Canvas(bounds)
    items.sort(key=lambda it: (it["strata"], it["level"], it["layer"], it["sublevel"], it["order"]))
    texts = []
    for it in items:
        kind = it["kind"]
        if kind == "texture":
            draw_texture(cv, it)
        elif kind == "nineslice":
            draw_nineslice(cv, it)
        elif kind == "text":
            texts.append((it, draw_text(cv, it)))
    if tip:
        draw_tooltip(cv, tip)
    cv.img.convert("RGB").save(out)
    print(f"wrote {out} ({cv.img.size[0]} x {cv.img.size[1]} px; window {window[2] - window[0]:g} x {window[3] - window[1]:g} UI units, {S} px each)")
    for line in layout_findings(texts, buttons):
        print("  layout:", line)


# ------------------------------------------------------------------ layout checks
def plain_text(text):
    text = re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|H[^|]*\|h|\|h", "", text)
    text = re.sub(r"\|T[^|]*\|t|\|A[^|]*\|a", "[icon]", text)
    return text.replace("||", "|").replace("|n", " / ").replace("\n", " / ")


def visible_part(rect, clip):
    if rect is None:
        return None
    if clip:
        rect = (max(rect[0], clip[0]), max(rect[1], clip[1]), min(rect[2], clip[2]), min(rect[3], clip[3]))
    return rect if rect[2] - rect[0] > 0.5 and rect[3] - rect[1] > 0.5 else None


def overlap(a, b):
    return min(a[2], b[2]) - max(a[0], b[0]) > 0.5 and min(a[3], b[3]) - max(a[1], b[1]) > 0.5


def layout_findings(texts, buttons):
    """What the drawing shows that the game would show too: text cut short with "...", text drawn over
    other text, and text running under a button that isn't its own."""
    def name(it):
        where = ".".join(p for p in (it.get("row"), it.get("key")) if p) or it.get("font", "text")
        return f'{where} "{plain_text(it["text"])}"'
    found, seen = [], set()
    shown = [(it, info, visible_part(info["drawn"], it.get("clip"))) for it, info in texts]
    for it, info, rect in shown:
        if rect and info["cut"]:
            what = (f"cut short to {info['lines']} line(s) in its {it['box'][3] - it['box'][1]:g}-tall box" if it.get("wrap")
                    else f"cut short with \"...\": it needs {info['needed']:.0f} wide, its box is {info['width']:.0f}")
            found.append(f"{name(it)} {what}")
        elif rect and it.get("wrap") and it.get("fixedHeight") and info["lines"] > 1:
            found.append(f"{name(it)} wraps onto {info['lines']} lines in its {it['box'][3] - it['box'][1]:g}-tall box: "
                         f"it needs {info['needed']:.0f} wide on one line, its box is {info['width']:.0f}")
    for i, (a, _, ra) in enumerate(shown):
        for b, _, rb in shown[i + 1:]:
            if ra and rb and overlap(ra, rb):
                key = (name(a), name(b))
                if key not in seen:
                    seen.add(key)
                    found.append(f"{name(a)} overlaps {name(b)}")
    for it, info, rect in shown:
        for btn in buttons:
            if rect and btn["id"] not in (it.get("chain") or []):
                box = visible_part(btn["box"], btn.get("clip"))
                if box and overlap(rect, box):
                    where = ".".join(p for p in (btn.get("row"), btn.get("key")) if p) or "a button"
                    found.append(f"{name(it)} runs under {where}")
    return found


def main():
    global S
    ap = argparse.ArgumentParser(description="Draws Forever Loot's window with the game's art.")
    ap.add_argument("scenarios", nargs="*", default=SCENARIOS, help="any of: " + ", ".join(SCENARIOS))
    ap.add_argument("--out", help="output file (one scenario only)")
    ap.add_argument("--scale", type=float, default=2, help="pixels per UI unit (default 2)")
    args = ap.parse_args()
    S = args.scale
    bad = [s for s in args.scenarios if s not in SCENARIOS]
    if bad:
        ap.error("no scenario " + ", ".join(bad))
    if args.out and len(args.scenarios) != 1:
        ap.error("--out takes one scenario")
    check_atlases()
    for scenario in args.scenarios:
        print(scenario)
        render(scenario, args.out or os.path.join(HERE, f"preview-{scenario}.png"))


if __name__ == "__main__":
    main()
