import re, sys
src=open('../ForeverLoot/Data.lua').read()
items=dict((int(m.group(1)),(m.group(2),int(m.group(3)),m.group(4))) for m in re.finditer(r'\[(\d+)\] = \{ "((?:[^"\\]|\\.)*)", (\d+), "((?:[^"\\]|\\.)*)" \}',src))
only=sys.argv[1:] 
cur=None; tot=0; empty=0
for line in src.splitlines():
    m=re.search(r'key = "(\w+)", name = "([^"]+)"',line)
    if m: cur=m.group(1); name=m.group(2); show=(not only or cur in only); 
    if m and show: print('\n##',name)
    if m: continue
    m=re.search(r'\{ name = "((?:[^"\\]|\\.)+)"(.*)loot = \{ ([^}]*) \}',line)
    if m and cur:
        ids=[int(x) for x in m.group(3).split(',') if x.strip()]
        tot+=len(ids); empty+= (len(ids)==0)
        if not show: continue
        tag=re.search(r'tag = "([^"]+)"',m.group(2)); wing=re.search(r'wing = "([^"]+)"',m.group(2))
        print(f"  {'['+wing.group(1)+'] ' if wing else ''}{m.group(1)}{' ('+tag.group(1)+')' if tag else ''}: {len(ids)} :: " + '; '.join(f"{items[i][0]}" for i in ids[:5]) + (' ...' if len(ids)>5 else ''))
print('\nitems placed:',tot,' bosses with no loot:',empty, ' unique items:', len(items))
