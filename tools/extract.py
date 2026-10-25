"""
ASBuilder data extractor.

Reads Azeroth Survivors' own data straight out of AzerothSurvivors.exe and writes the addon's
Data.lua (classes, spells, rings, trinkets, amulets, legendary amulets) and Names.lua (the names
of every piece of jewelry in the game's 14 languages, so a worn piece is recognised in any of
them). Run it again after a game update and new spells and jewelry are in the addon.

Usage:  python extract.py [path\\to\\AzerothSurvivors.exe]
        (default: the game one folder up, as when this file sits in <game>\\.asb_tools;
        it writes into <game>\\AddOns\\ASBuilder)

Standard library only. It does not change the game; it only reads the exe.
"""
import hashlib
import json
import os
import re
import struct
import sys
import time

KEY_RE = re.compile(r'^[a-z0-9_]+$')
ICON_RE = re.compile(r'^(INV|Spell|Ability|Racial|Achievement|Trade|Temp)_[A-Za-z0-9_]+$')
LEG_ICON_RE = re.compile(r'INV_Jewelry_Necklace_(?:[A-Za-z]+_\d+|\d+(?:Naxxramas)?)')
RARITY = ["Common", "Uncommon", "Rare", "Epic", "Legendary", "PvP"]
LOC_LANGS = ['zh', 'es', 'fr', 'pt', 'ru', 'de', 'ja', 'tr', 'ko']   # the addon's languages besides English (the most spoken ones the game ships)
LOC_UI = ['Remove', 'Close', 'Done', 'Banish', 'Import', 'Unsaved changes', 'Legendary amulet · remakes {spell}',
          'Banish', 'Language', 'Rings', 'Trinkets', 'Amulet', 'Ring', 'Trinket', 'Endless', 'Damage', 'Cooldowns', 'Area', 'Speed',
          'Lifesteal', 'Pickup', 'Luck', 'Gold', 'Common', 'Uncommon', 'Rare', 'Epic', 'Legendary']   # addon words the game's own table has too


class Exe:
    def __init__(self, path):
        with open(path, 'rb') as fh:
            self.data = fh.read()
        d = self.data
        pe = struct.unpack_from('<I', d, 0x3c)[0]
        if d[pe:pe + 4] != b'PE\0\0':
            raise SystemExit('not a Windows exe: ' + path)
        nsec = struct.unpack_from('<H', d, pe + 6)[0]
        optsz = struct.unpack_from('<H', d, pe + 20)[0]
        opt = pe + 24
        self.base = struct.unpack_from('<Q', d, opt + 24)[0]
        self.secs = []
        for i in range(nsec):
            o = opt + optsz + i * 40
            vsz, va, rsz, rptr = struct.unpack_from('<IIII', d, o + 8)
            self.secs.append((d[o:o + 8].rstrip(b'\0'), va, vsz, rptr, rsz))
        rd = [s for s in self.secs if s[0] == b'.rdata']
        if not rd:
            raise SystemExit('no .rdata section')
        _, self.rva, _, self.rptr, self.rsz = rd[0]

    def off2va(self, o):
        for _, va, vs, rp, rs in self.secs:
            if rp <= o < rp + rs:
                return self.base + va + o - rp
        return None

    def va2off(self, v):
        r = v - self.base
        for _, va, vs, rp, rs in self.secs:
            if va <= r < va + vs and r - va < rs:
                return rp + r - va
        return None

    def u64(self, o):
        return struct.unpack_from('<Q', self.data, o)[0]

    def s(self, o):
        """the Rust &str (pointer, length) stored at file offset o, or None"""
        if o < 0 or o + 16 > len(self.data):
            return None
        p, n = struct.unpack_from('<QQ', self.data, o)
        if not (0 < n < 2048):
            return None
        oo = self.va2off(p)
        if oo is None:
            return None
        try:
            return self.data[oo:oo + n].decode('utf8')
        except UnicodeDecodeError:
            return None

    def u8slice(self, o, maxlen=64):
        p, n = struct.unpack_from('<QQ', self.data, o)
        oo = self.va2off(p)
        if oo is None or n > maxlen:
            return None
        return list(self.data[oo:oo + n])

    def str_slice(self, o, maxlen=64):
        p, n = struct.unpack_from('<QQ', self.data, o)
        oo = self.va2off(p)
        if oo is None or n > maxlen:
            return None
        return [self.s(oo + i * 16) for i in range(n)]

    def refs(self, text, limit=400):
        """file offsets of &str pairs pointing at `text` (inside .rdata)"""
        b = text.encode('utf8')
        d = self.data
        lo, hi = self.rptr, self.rptr + self.rsz
        out, start, seen = [], lo, 0
        while seen < limit:
            i = d.find(b, start, hi)
            if i < 0:
                break
            seen += 1
            start = i + 1
            pat = struct.pack('<QQ', self.off2va(i), len(b))
            j = d.find(pat, lo, hi)
            while j >= 0:
                if j % 8 == 0:
                    out.append(j)
                j = d.find(pat, j + 1, hi)
        return out


def walk_table(exe, anchor_key, stride, valid, key_offset=0):
    """Finds the table holding `anchor_key`, then walks it back to its first entry and
    forward to its last. Returns the file offsets of every entry."""
    for r in exe.refs(anchor_key):
        o = r - key_offset
        if valid(o) and (valid(o + stride) or valid(o - stride)):
            while valid(o - stride):
                o -= stride
            rows = []
            while valid(o):
                rows.append(o)
                o += stride
            return rows
    raise SystemExit('could not find the table of "%s": the game layout changed, the extractor needs an update' % anchor_key)


# ------------------------------------------------------------------ translations
FINGERPRINT = [  # language of a translation block, from two of its texts
    ('en', 'common.male', 'Male'), ('tr', 'common.male', 'Erkek'), ('pl', 'ability.fireball.name', 'Kula Ognia'),
    ('cs', 'ability.fireball.name', 'Ohnivá koule'), ('de', 'ability.fireball.name', 'Feuerball'),
    ('pt', 'ability.fireball.name', 'Bola de Fogo'), ('es', 'ability.fireball.name', 'Bola de Fuego'),
    ('fr', 'ability.fireball.name', 'Boule de feu'), ('ro', 'ability.fireball.name', 'Minge de foc'),
    ('ru', 'common.male', 'Мужчина'), ('uk', 'common.male', 'Чоловік'), ('zh', 'ability.fireball.name', '火球术'),
    ('ja', 'ability.fireball.name', 'ファイアボール'), ('ko', 'ability.fireball.name', '화염구'),
]


def translations(exe):
    d = exe.data
    blocks, seen = [], set()
    for m in re.finditer(rb'"jewel\.[a-z0-9_]+":', d):
        a = max(d.rfind(b'{\n', 0, m.start()), d.rfind(b'{\r\n', 0, m.start()))  # CRLF since 0.108.0
        if a in seen:
            continue
        seen.add(a)
        e = d.find(b'\n}', m.start())
        try:
            j = json.loads(d[a:e + 2].decode('utf8'))
        except ValueError:
            continue
        lang = '?%d' % len(blocks)
        for code, key, text in FINGERPRINT:
            if j.get(key) == text:
                lang = code
                break
        blocks.append((lang, j))
    if not blocks:
        raise SystemExit('no translation tables found')
    if 'en' not in dict(blocks):
        # since 0.105.0 the English table has no jewel.* keys: find it by its own text
        m = d.find(b'"common.male": "Male"')
        if m >= 0:
            a, e = d.rfind(b'{\r\n', 0, m), d.find(b'\r\n}', m)
            try:
                blocks.insert(0, ('en', json.loads(d[a:e + 3].decode('utf8'))))
            except ValueError:
                pass
    return blocks


# ------------------------------------------------------------------ the tables
def extract(path):
    exe = Exe(path)
    blocks = translations(exe)
    en = dict(blocks)['en'] if 'en' in dict(blocks) else blocks[0][1]
    ekeys = list(en)
    warn = []

    # rings and trinkets: key, name, icon, stat template, two numbers (72 bytes)
    jkeys = [k[6:] for k in ekeys if k.startswith('jewel.')]
    def jvalid(o):
        k, n, i, t = exe.s(o), exe.s(o + 16), exe.s(o + 32), exe.s(o + 48)
        return bool(k and KEY_RE.match(k) and n and i and ICON_RE.match(i) and t and '{' in t)
    jrows = walk_table(exe, jkeys[0], 72, jvalid)
    jewels = [dict(key=exe.s(o), name=exe.s(o + 16), icon=exe.s(o + 32), stat=exe.s(o + 48)) for o in jrows]
    # the rings come first (all with a ring icon), then the trinkets
    nring = 0
    while nring < len(jewels) and '_Ring' in jewels[nring]['icon']:
        nring += 1
    rings, trinkets = jewels[:nring], jewels[nring:]
    for j in trinkets:
        if '_Ring' in j['icon']:
            warn.append('"%s" has a ring icon among the trinkets: check Data.lua' % j['name'])

    # amulets: key, name, icon, effects, rarity (80 bytes)
    akeys = [k[7:] for k in ekeys if k.startswith('amulet.')]
    def avalid(o):
        k, n, i = exe.s(o), exe.s(o + 16), exe.s(o + 32)
        return bool(k and KEY_RE.match(k) and n and i and ICON_RE.match(i) and exe.u64(o + 64) <= 5)
    arows = walk_table(exe, akeys[0], 80, avalid)
    amulets = [dict(key=exe.s(o), name=exe.s(o + 16), icon=exe.s(o + 32), rarity=RARITY[exe.u64(o + 64)]) for o in arows]

    # legendary amulets: their names and icons follow each other in the game's own order
    names = [k for k in ekeys if ' ' in k and k[:1].isupper() and len(k) < 40]
    d = exe.data
    hits = []
    for k in names:
        i = d.find(k.encode('utf8') + b'INV_Jewelry_Necklace')
        if i >= 0:
            hits.append(i)
    if not hits:
        raise SystemExit('could not find the legendary amulets')
    a = min(hits)
    # since 0.105.0 a "legendary:" marker sits inside the list: read up to the amulet table's tag
    b = d.find(b'amulet.', a)
    if b < 0:
        b = a + 4096
    region = d[a:b].decode('latin1')
    byfirst = {}
    for k in names:
        byfirst.setdefault(k[0], []).append(k)
    for v in byfirst.values():
        v.sort(key=len, reverse=True)
    def name_at(pos):
        for k in byfirst.get(region[pos], []):
            if region.startswith(k, pos):
                return k
        return None
    legend, pos = [], 0
    while pos < len(region):
        k = name_at(pos)
        if not k:
            pos += 1
            continue
        pos += len(k)
        m = LEG_ICON_RE.match(region, pos)
        legend.append(dict(name=k, icon=m.group() if m else None))
        if m:
            pos = m.end()

    # spells: key, name, icon, effects, numbers; spell id at +64, legendary kind at +117 (120 bytes)
    abkeys = [k[8:-5] for k in ekeys if k.startswith('ability.') and k.endswith('.name')]
    def bvalid(o):
        k, n, i = exe.s(o), exe.s(o + 16), exe.s(o + 32)
        return bool(k and KEY_RE.match(k) and n and i and ICON_RE.match(i) and exe.u8slice(o + 48, 16) is not None)
    brows = walk_table(exe, abkeys[0], 120, bvalid)
    # shortcut: the game names Demonic Empowerment's amulet in code, outside the kind list; recheck on updates
    LEGION = "The Legionlord's Medallion"
    legion = [x for x in legend if x['name'] == LEGION]
    legend = [x for x in legend if x['name'] != LEGION]
    spells = {}
    for o in brows:
        kind = d[o + 117]
        spells[exe.s(o)] = dict(key=exe.s(o), name=exe.s(o + 16), icon=exe.s(o + 32),
                                id=struct.unpack_from('<I', d, o + 64)[0],
                                amulet=legend[kind]['name'] if kind < len(legend) else None, kind=kind)
    legend = legend[:max(sp['kind'] for sp in spells.values()) + 1]
    if legion and 'demonic_empowerment' in spells:
        spells['demonic_empowerment']['amulet'] = LEGION
        legend += legion

    # classes: key, name, spells, starting spell, colour, icon, blurb (144 bytes)
    ckeys = [k[6:-5] for k in ekeys if k.startswith('class.') and k.endswith('.name')]
    def cvalid(o):
        k, c = exe.s(o), exe.s(o + 64)
        return bool(k and KEY_RE.match(k) and c and c.startswith('#') and exe.str_slice(o + 32) is not None)
    crows = walk_table(exe, ckeys[0], 144, cvalid)
    classes = []
    for o in crows:
        keys = exe.str_slice(o + 32)
        row = dict(key=exe.s(o), name=exe.s(o + 16), color=exe.s(o + 64).lstrip('#'), icon=exe.s(o + 80),
                   start=exe.s(o + 48), spells=[])
        for k in keys:
            sp = spells.get(k)
            if not sp:
                warn.append('spell "%s" of %s is not in the spell table' % (k, row['name']))
                continue
            if not sp['amulet']:
                warn.append('spell "%s" has a legendary amulet kind (%d) the extractor does not know' % (k, sp['kind']))
            row['spells'].append(sp)
        classes.append(row)

    # names in every language -> English, for recognising worn jewelry
    tr_names = {}
    for lang, j in blocks:
        for x in rings + trinkets:
            v = j.get('jewel.' + x['key'])
            if v and v != x['name']:
                tr_names[v] = x['name']
        for x in amulets:
            v = j.get('amulet.' + x['key'])
            if v and v != x['name']:
                tr_names[v] = x['name']
        for x in legend:
            v = j.get(x['name'])
            if v and v != x['name']:
                tr_names[v] = x['name']

    # English text -> the game's own text, per addon language (names, stat lines, a few UI words)
    texts = set(LOC_UI)
    for x in rings + trinkets + amulets + legend:
        texts.add(x['name'])
    texts.update(x['stat'] for x in rings + trinkets)
    for c in classes:
        texts.add(c['name'])
        texts.update(s['name'] for s in c['spells'])
    ekey = {}
    for k, v in en.items():
        ekey.setdefault(v, k)
    loc = {}
    for lang, j in blocks:
        if lang in LOC_LANGS:
            loc[lang] = {t: j[ekey[t]] for t in texts if t in ekey and j.get(ekey[t]) and j[ekey[t]] != t}
    # the addon's own texts, translated by hand (ui-i18n.json: English -> one text per LOC_LANGS language)
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ui-i18n.json'), encoding='utf8') as fh:
        ui = json.load(fh)
    for i, lang in enumerate(LOC_LANGS):
        for k, cols in ui.items():
            if cols[i] and k not in loc.get(lang, {}):
                loc.setdefault(lang, {})[k] = cols[i]
    for t in texts:
        if t not in ekey:
            warn.append('"%s" has no entry in the game\'s translation table' % t)

    remakes = en.get('Legendary amulet · remakes {spell}', 'Legendary amulet · remakes {spell}')
    sha = hashlib.sha1(exe.data).hexdigest()[:12]
    return dict(rings=rings, trinkets=trinkets, amulets=amulets, legend=legend, classes=classes, loc=loc,
                names=tr_names, langs=[l for l, _ in blocks], remakes=remakes, sha=sha, warn=warn)


# ------------------------------------------------------------------ writing Lua
def lua(s):
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\r', '')
    return '"' + s + '"'


def write(out, data_path, names_path, loc_path):
    stamp = time.strftime('%Y-%m-%d %H:%M')
    L = []
    L.append('-- ASBuilder data, generated by tools/extract.py from AzerothSurvivors.exe. Do not edit:')
    L.append('-- run the extractor again after a game update instead.')
    L.append('ASBuilder_Data = {}')
    L.append('ASBuilder_Data.source = { exe = %s, generated = %s }' % (lua(out['sha']), lua(stamp)))
    L.append('ASBuilder_Data.remakes = %s' % lua(out['remakes']))
    for group in ('rings', 'trinkets'):
        L.append('ASBuilder_Data.%s = {' % group)
        for x in out[group]:
            L.append('  { key = %s, name = %s, icon = %s, stat = %s },' % (lua(x['key']), lua(x['name']), lua(x['icon']), lua(x['stat'])))
        L.append('}')
    L.append('ASBuilder_Data.amulets = {')
    for x in out['amulets']:
        L.append('  { key = %s, name = %s, icon = %s, rarity = %s },' % (lua(x['key']), lua(x['name']), lua(x['icon']), lua(x['rarity'])))
    L.append('}')
    L.append('ASBuilder_Data.legendaries = {')
    for x in out['legend']:
        L.append('  { name = %s%s },' % (lua(x['name']), (', icon = ' + lua(x['icon'])) if x['icon'] else ''))
    L.append('}')
    L.append('ASBuilder_Data.classes = {')
    for c in out['classes']:
        L.append('  { key = %s, name = %s, color = %s, icon = %s, start = %s, spells = {' % (
            lua(c['key']), lua(c['name']), lua(c['color']), lua(c['icon']), lua(c['start'])))
        for s in c['spells']:
            L.append('    { key = %s, name = %s, icon = %s, id = %d%s },' % (
                lua(s['key']), lua(s['name']), lua(s['icon']), s['id'], (', amulet = ' + lua(s['amulet'])) if s['amulet'] else ''))
        L.append('  } },')
    L.append('}')
    with open(data_path, 'w', encoding='utf8', newline='\n') as fh:
        fh.write('\n'.join(L) + '\n')

    N = ['-- ASBuilder: jewelry names in the game\'s languages (%s) -> English. Generated by' % ', '.join(out['langs']),
         '-- tools/extract.py from AzerothSurvivors.exe; run it again after a game update.',
         'ASBuilder_Names = {']
    for k in sorted(out['names']):
        N.append('  [%s] = %s,' % (lua(k), lua(out['names'][k])))
    N.append('}')
    N.append('ASBuilder_AmuletIcons = {')
    for x in out['legend']:
        if x['icon']:
            N.append('  [%s] = %s,' % (lua(x['name']), lua(x['icon'])))
    N.append('}')
    with open(names_path, 'w', encoding='utf8', newline='\n') as fh:
        fh.write('\n'.join(N) + '\n')

    X = ['-- ASBuilder: the game\'s own words for the names and stat lines the addon shows, English -> language.',
         '-- Generated by tools/extract.py from AzerothSurvivors.exe; run it again after a game update.',
         'ASBuilder_Loc = {']
    for lang in LOC_LANGS:
        X.append('  %s = {' % lang)
        for k in sorted(out['loc'].get(lang, {})):
            X.append('    [%s] = %s,' % (lua(k), lua(out['loc'][lang][k])))
        X.append('  },')
    X.append('}')
    with open(loc_path, 'w', encoding='utf8', newline='\n') as fh:
        fh.write('\n'.join(X) + '\n')


def stats_gaps(out, stats_path):
    """Stats.lua is written by hand (the game keeps amulet stats in code): name what it lacks."""
    try:
        with open(stats_path, encoding='utf8') as fh:
            text = fh.read()
    except OSError:
        return ['Stats.lua is missing: amulets will show their stats only after being worn']
    am, _, lg = text.partition('ASBuilder_LegendStats')
    have = set(re.findall(r'^\s*([a-z0-9_]+) = \{ "', am, re.M))
    gaps = ['amulet "%s" is new: Stats.lua has no stats for it yet (it shows them once worn)' % x['name']
            for x in out['amulets'] if x['key'] not in have]
    have_l = {}
    cls = None
    for line in lg.splitlines():
        m = re.match(r'^  ([a-z0-9_]+) = \{\s*$', line)
        if m:
            cls = m.group(1)
            continue
        m = re.match(r'^    ([a-z0-9_]+) = \{ "', line)
        if m and cls:
            have_l.setdefault(cls, set()).add(m.group(1))
    for c in out['classes']:
        for sp in c['spells']:
            if sp.get('amulet') and sp['key'] not in have_l.get(c['key'], ()):
                gaps.append('legendary amulet for %s %s is new: Stats.lua has no effects for it yet' % (c['name'], sp['name']))
    return gaps


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    exe = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(here, '..', 'AzerothSurvivors.exe'))
    if not os.path.isfile(exe):
        raise SystemExit('AzerothSurvivors.exe not found at ' + exe + '\nGive its path: python extract.py "C:\\...\\AzerothSurvivors.exe"')
    addon = os.path.normpath(os.path.join(here, '..', 'AddOns', 'ASBuilder'))
    print('Reading', exe)
    t = time.time()
    out = extract(exe)
    write(out, os.path.join(addon, 'Data.lua'), os.path.join(addon, 'Names.lua'), os.path.join(addon, 'Locale.lua'))
    nsp = sum(len(c['spells']) for c in out['classes'])
    print('Classes %d, spells %d, rings %d, trinkets %d, amulets %d, legendary amulets %d, names %d (%s)' % (
        len(out['classes']), nsp, len(out['rings']), len(out['trinkets']), len(out['amulets']), len(out['legend']),
        len(out['names']), ' '.join(out['langs'])))
    for w in out['warn'] + stats_gaps(out, os.path.join(addon, 'Stats.lua')):
        print('WARNING:', w)
    print('Wrote Data.lua, Names.lua and Locale.lua in %s (%.1fs). Type /reload in the game.' % (addon, time.time() - t))


if __name__ == '__main__':
    main()
