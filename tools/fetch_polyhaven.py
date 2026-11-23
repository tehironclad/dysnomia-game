#!/usr/bin/env python3
"""Fetch CC0 assets from Poly Haven (https://polyhaven.com, all assets CC0).

  tools/fetch_polyhaven.py model <asset_id> [res]     -> assets/models/polyhaven/<id>/<id>.gltf (+bin, textures)
  tools/fetch_polyhaven.py texture <asset_id> [res]   -> assets/textures/polyhaven/<id>/{diff,nor_gl,rough,arm}.jpg
  tools/fetch_polyhaven.py search <type> <words...>   -> list matching asset ids (type: models|textures)

Default resolution is 1k to keep the repo small. Every fetch is recorded in assets/CREDITS.md.
"""
import json, os, sys, urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
API = "https://api.polyhaven.com"
UA = {"User-Agent": "dysnomia-game-asset-fetch"}


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


def save(url, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if not os.path.exists(path):
        with open(path, "wb") as f:
            f.write(get(url))
    return path


def credit(kind, aid):
    info = json.loads(get(f"{API}/info/{aid}"))
    authors = ", ".join(info.get("authors", {}).keys())
    line = f"- `{aid}` ({kind}) — \"{info.get('name', aid)}\" by {authors}, CC0, https://polyhaven.com/a/{aid}\n"
    path = os.path.join(ROOT, "assets", "CREDITS.md")
    existing = open(path).read() if os.path.exists(path) else (
        "# Third-party asset credits\n\nAll assets below are CC0 (public domain). Credit is given as a courtesy.\n\n## Poly Haven\n\n")
    if f"`{aid}`" not in existing:
        open(path, "w").write(existing + line)


def model(aid, res="1k"):
    files = json.loads(get(f"{API}/files/{aid}"))
    g = files["gltf"].get(res) or files["gltf"][sorted(files["gltf"])[0]]
    g = g["gltf"]
    base = os.path.join(ROOT, "assets", "models", "polyhaven", aid)
    save(g["url"], os.path.join(base, os.path.basename(g["url"])))
    for rel, inc in g.get("include", {}).items():
        save(inc["url"], os.path.join(base, rel))
    credit("model", aid)
    print(os.path.relpath(os.path.join(base, os.path.basename(g["url"])), ROOT))


def texture(aid, res="1k"):
    files = json.loads(get(f"{API}/files/{aid}"))
    base = os.path.join(ROOT, "assets", "textures", "polyhaven", aid)
    for key, out in (("Diffuse", "diff"), ("nor_gl", "nor_gl"), ("Rough", "rough"), ("arm", "arm"), ("AO", "ao"), ("Metal", "metal")):
        if key in files and res in files[key] and "jpg" in files[key][res]:
            save(files[key][res]["jpg"]["url"], os.path.join(base, out + ".jpg"))
            print(os.path.relpath(os.path.join(base, out + ".jpg"), ROOT))
    credit("texture", aid)


def search(kind, words):
    data = json.loads(get(f"{API}/assets?t={kind}"))
    for aid, info in data.items():
        hay = " ".join([aid, info.get("name", "")] + info.get("tags", []) + info.get("categories", [])).lower()
        if all(w.lower() in hay for w in words):
            print(aid, "|", info.get("name"), "|", ",".join(info.get("categories", [])))


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "model":
        model(sys.argv[2], *(sys.argv[3:4]))
    elif cmd == "texture":
        texture(sys.argv[2], *(sys.argv[3:4]))
    elif cmd == "search":
        search(sys.argv[2], sys.argv[3:])
