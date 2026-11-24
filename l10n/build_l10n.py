# Builds assets/l10n.json from l10n/ui_*.txt and checks it against the t('...') calls in lib/.
#   python3 l10n/build_l10n.py        (run from the project root)
# Each line of ui_*.txt: English|Polish|Simplified Chinese|Traditional Chinese|French|Italian|German|Spanish|Korean|
#   Russian|Turkish|Japanese|Portuguese (Brazil). "\n" = line break. Keep {0}, {1}... placeholders.
# Column names match the game's language names (assets/gamedb.json), which is how the app picks the table.
import glob, json, re, sys

LANGS = ['English', 'Polish', 'Simplified Chinese', 'Traditional Chinese', 'French', 'Italian', 'German',
         'Spanish - Spain', 'Korean', 'Russian', 'Turkish', 'Japanese', 'Portuguese - Brazil']
def literals(src):
    """Yield (start, end, quote, body) for single-line Dart string literals (no raw, no triple)."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i); i = n if j < 0 else j; continue
        if src.startswith('/*', i):
            j = src.find('*/', i); i = n if j < 0 else j + 2; continue
        if c in '\'"':
            raw = i > 0 and src[i - 1] == 'r'
            if src.startswith(c * 3, i):
                j = src.find(c * 3, i + 3); i = j + 3; continue
            j = i + 1; depth = 0
            while j < n:
                ch = src[j]
                if ch == '\\' and not raw: j += 2; continue
                if ch == '$' and src.startswith('${', j) and not raw:
                    # skip interpolation with nested braces/strings
                    k = j + 2; d = 1
                    while k < n and d:
                        if src[k] == '{': d += 1
                        elif src[k] == '}': d -= 1
                        elif src[k] in '\'"':
                            q = src[k]; k += 1
                            while k < n and src[k] != q:
                                k += 2 if src[k] == '\\' else 1
                        k += 1
                    j = k; continue
                if ch == c or ch == '\n': break
                j += 1
            yield i - (1 if raw else 0), j + 1, c, src[i + 1:j], raw
            i = j + 1; continue
        i += 1

def code_keys():
    keys = {'Good', 'Neutral', 'Bad', 'Disease symptoms'}  # perk group names translated via t(k)
    for p in glob.glob('lib/**/*.dart', recursive=True):
        s = open(p, encoding='utf-8').read()
        lits = list(literals(s))
        for m in re.finditer(r'\bt\(', s):
            parts, pos = [], m.end()
            for a, b, q, body, raw in lits:
                if a < pos: continue
                if s[pos:a].strip(): break
                parts.append(body); pos = b
            if parts:
                keys.add(re.sub(r'\\(.)', lambda x: {'n': '\n', 't': '\t'}.get(x.group(1), x.group(1)), ''.join(parts)))
    return keys

rows, bad = {}, 0
for f in sorted(glob.glob('l10n/ui_*.txt')):
    for n, line in enumerate(open(f, encoding='utf-8'), 1):
        line = line.rstrip('\n')
        if not line.strip() or line.startswith('#'): continue
        cols = [c.replace('\\n', '\n') for c in line.split('|')]
        if len(cols) != len(LANGS):
            print(f'{f}:{n}: {len(cols)} columns, expected {len(LANGS)}'); bad += 1; continue
        ph = sorted(re.findall(r'\{\d+\}', cols[0]))
        for lang, c in zip(LANGS[1:], cols[1:]):
            if sorted(re.findall(r'\{\d+\}', c)) != ph:
                print(f'{f}:{n}: {lang} placeholders differ: {c!r}'); bad += 1
        rows[cols[0]] = cols
keys = code_keys()
for k in sorted(keys - rows.keys()): print('missing translation:', repr(k)); bad += 1
for k in sorted(rows.keys() - keys): print('unused (not in code):', repr(k))
out = {lang: {en: cols[i] for en, cols in rows.items() if cols[i] != en} for i, lang in enumerate(LANGS) if i}
json.dump(out, open('assets/l10n.json', 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(f'{len(rows)} strings x {len(LANGS) - 1} languages -> assets/l10n.json' + (f'  ({bad} problems)' if bad else ''))
sys.exit(1 if bad else 0)
