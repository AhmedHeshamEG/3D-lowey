"""The Kit: fetch CC0 packs from their official pages, check their licences, convert the curated assets.

    python Tools/fetch-kit.py download         # packs -> Tools/kit/.cache (licence checked per pack)
    python Tools/fetch-kit.py list [pack]      # the models in the downloaded packs (for curating)
    python Tools/fetch-kit.py build            # Tools/kit/curation.json -> App/Resources/Kit (.loweyasset folders)
    python Tools/fetch-kit.py check            # the built Kit matches the curation and fits the size budget (CI)

Sources: Kenney (kenney.nl, CC0) and Quaternius (itch.io, CC0). Nothing is used unless the pack's own licence file
says CC0. Each converted asset is a `.loweyasset` folder: `model.glb` (scaled to metres, pivot at the base centre)
and `asset.json` (name, set, category, tags, real size, the surfaces things can stand on, which way it faces, rig,
source and licence). Thumbnails are rendered by the app itself, in the Ink Look, the first time the Library shows
an asset (so they always match the renderer).
"""

import io
import json
import os
import re
import sys
import urllib.parse
import urllib.request
import zipfile
from http.cookiejar import CookieJar

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KIT_TOOLS = os.path.join(ROOT, "Tools", "kit")
CACHE = os.path.join(KIT_TOOLS, ".cache")
OUT = os.path.join(ROOT, "App", "Resources", "Kit")
BUDGET_MB = 150

sys.path.insert(0, KIT_TOOLS)

USER_AGENT = "3D-lowey kit fetcher (https://github.com/AhmedHeshamEG/3D-lowey)"


def load_packs():
    with open(os.path.join(KIT_TOOLS, "packs.json"), encoding="utf-8") as handle:
        return json.load(handle)["packs"]


# ------------------------------------------------------------------------------------------------ downloading


def opener():
    jar = CookieJar()
    built = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    built.addheaders = [("User-Agent", USER_AGENT)]
    return built


def kenney_zip_url(page, web):
    html = web.open(page, timeout=60).read().decode("utf-8", "replace")
    slug = page.rstrip("/").split("/")[-1]
    match = re.search(r"https://kenney\.nl/media/pages/assets/" + re.escape(slug) + r"/[^\"']+\.zip", html)
    if not match:
        raise RuntimeError(f"no download on {page}")
    return match.group(0)


def itch_zip_urls(page, web):
    """itch.io's free-download flow: the page's token -> a download key -> each upload's CDN URL."""
    html = web.open(page, timeout=60).read().decode("utf-8", "replace")
    token = re.search(r'name="csrf_token" value="([^"]+)"', html).group(1)
    body = urllib.parse.urlencode({"csrf_token": token}).encode()
    key_page = json.loads(web.open(page.rstrip("/") + "/download_url", data=body, timeout=60).read())["url"]
    listing = web.open(key_page, timeout=60).read().decode("utf-8", "replace")
    uploads = re.findall(r'data-upload_id="(\d+)"', listing)
    names = re.findall(r'class="upload_name"[^>]*>\s*<strong[^>]*title="([^"]+)"', listing) or [""] * len(uploads)
    urls = []
    for upload, name in zip(uploads, names + [""] * (len(uploads) - len(names))):
        if name and not re.search(r"(gltf|glb|standard|\.zip)", name, re.IGNORECASE):
            continue
        # The free "Download now" path, as the page's own button takes it.
        query = urllib.parse.urlencode({"source": "view_game", "as_props": "1", "after_download_lightbox": "true"})
        reply = json.loads(web.open(f"{page.rstrip('/')}/file/{upload}?{query}", data=body, timeout=60).read())
        urls.append((name or f"upload-{upload}.zip", reply["url"]))
    if not urls:
        raise RuntimeError(f"no downloads on {page}")
    return urls


def licence_is_cc0(archive):
    """The pack's own licence file (License.txt, LICENSE…) must say CC0 / public domain."""
    for name in archive.namelist():
        base = os.path.basename(name).lower()
        if base.startswith("licen") and base.endswith((".txt", ".md", "")):
            text = archive.read(name).decode("utf-8", "replace").lower()
            if "cc0" in text or "creative commons zero" in text or "public domain" in text:
                return name
    return None


def download(pack, web):
    folder = os.path.join(CACHE, pack["id"])
    marker = os.path.join(folder, ".licence")
    if os.path.exists(marker):
        print(f"  {pack['id']}: cached")
        return
    os.makedirs(folder, exist_ok=True)
    if pack["source"] == "kenney":
        archives = [("pack.zip", kenney_zip_url(pack["page"], web))]
    else:
        archives = itch_zip_urls(pack["page"], web)
    licences = []
    for name, url in archives:
        print(f"  {pack['id']}: {name}")
        data = web.open(url, timeout=600).read()
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            licence = licence_is_cc0(archive)
            if licence is None and pack["source"] == "itch":
                licence = itch_page_licence(pack["page"], web)
            if licence is None:
                raise RuntimeError(f"{pack['id']}: no CC0 licence in {name}; not used")
            licences.append(licence)
            archive.extractall(folder)
    with open(marker, "w", encoding="utf-8") as handle:
        json.dump({"page": pack["page"], "licence": licences}, handle)


def itch_page_licence(page, web):
    """Some itch packs carry the licence on the page only; it must name CC0 there."""
    html = web.open(page, timeout=60).read().decode("utf-8", "replace")
    if "creativecommons.org/publicdomain/zero" in html or re.search(r"\bCC0\b", html):
        return page + " (CC0 on the page)"
    return None


def command_download(only=None):
    web = opener()
    for pack in load_packs():
        if only and pack["id"] not in only:
            continue
        try:
            download(pack, web)
        except Exception as error:  # noqa: BLE001 — report and go on with the other packs
            print(f"  {pack['id']}: FAILED ({error})")


# ------------------------------------------------------------------------------------------------ listing


def models_in(pack):
    folder = os.path.join(CACHE, pack["id"])
    found = []
    for directory, _, files in os.walk(folder):
        for name in files:
            if name.lower().endswith((".glb", ".gltf")):
                found.append(os.path.relpath(os.path.join(directory, name), folder).replace("\\", "/"))
    return sorted(found)


def command_list(only=None):
    for pack in load_packs():
        if only and pack["id"] not in only:
            continue
        models = models_in(pack)
        print(f"{pack['id']}: {len(models)} models")
        for model in models:
            print("   ", model)


# ------------------------------------------------------------------------------------------------ building


def kit_folder(set_name):
    """A Set's folder name: plain ASCII, no spaces (it lives in the app bundle)."""
    return re.sub(r"[^A-Za-z0-9]+", "-", set_name).strip("-")


def command_build():
    import glb  # Tools/kit/glb.py (needs numpy and Pillow: only building the Kit does)
    import kitmeta  # Tools/kit/kitmeta.py

    with open(os.path.join(KIT_TOOLS, "curation.json"), encoding="utf-8") as handle:
        curation = json.load(handle)
    packs = {pack["id"]: pack for pack in load_packs()}
    index = {"version": 1, "sets": curation["sets"], "assets": []}
    total = 0
    for entry in curation["assets"]:
        pack = packs[entry["pack"]]
        source = os.path.join(CACHE, pack["id"], entry["file"])
        if not os.path.exists(source):
            raise SystemExit(f"missing {source}: run download first")
        model = glb.load(source)
        meta, placement = kitmeta.describe(model, entry, pack, curation, CACHE)
        folder = os.path.join(OUT, kit_folder(entry["set"]), entry["id"] + ".loweyasset")
        os.makedirs(folder, exist_ok=True)
        data = glb.save(glb.toon_ready(kitmeta.normalised(model, placement)))
        with open(os.path.join(folder, "model.glb"), "wb") as handle:
            handle.write(data)
        with open(os.path.join(folder, "asset.json"), "w", encoding="utf-8", newline="\n") as handle:
            json.dump(meta, handle, indent=1, sort_keys=True)
            handle.write("\n")
        total += len(data)
        index["assets"].append({"id": entry["id"], "set": entry["set"], "path": f"{kit_folder(entry['set'])}/{entry['id']}.loweyasset"})
    with open(os.path.join(OUT, "kit.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(index, handle, indent=1)
        handle.write("\n")
    print(f"Built {len(index['assets'])} assets, {total / 1e6:.1f} MB")


def command_check():
    with open(os.path.join(KIT_TOOLS, "curation.json"), encoding="utf-8") as handle:
        curation = json.load(handle)
    with open(os.path.join(OUT, "kit.json"), encoding="utf-8") as handle:
        index = json.load(handle)
    wanted = {entry["id"] for entry in curation["assets"]}
    built = {entry["id"] for entry in index["assets"]}
    problems = []
    if wanted != built:
        problems.append(f"curation and kit.json differ: missing {sorted(wanted - built)[:5]}, extra {sorted(built - wanted)[:5]}")
    size = 0
    for entry in index["assets"]:
        folder = os.path.join(OUT, entry["path"])
        for name in ("model.glb", "asset.json"):
            path = os.path.join(folder, name)
            if not os.path.exists(path):
                problems.append(f"missing {entry['path']}/{name}")
            else:
                size += os.path.getsize(path)
        meta_path = os.path.join(folder, "asset.json")
        if os.path.exists(meta_path):
            with open(meta_path, encoding="utf-8") as handle:
                meta = json.load(handle)
            if "cc0" not in meta.get("license", "").lower():
                problems.append(f"{entry['id']}: not CC0")
    if size > BUDGET_MB * 1e6:
        problems.append(f"the Kit is {size / 1e6:.1f} MB, over the {BUDGET_MB} MB budget")
    if problems:
        print("\n".join(problems))
        sys.exit(1)
    print(f"Kit OK: {len(built)} assets, {size / 1e6:.1f} MB of {BUDGET_MB} MB")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    command, rest = sys.argv[1], sys.argv[2:]
    if command == "download":
        command_download(set(rest) or None)
    elif command == "list":
        command_list(set(rest) or None)
    elif command == "build":
        command_build()
    elif command == "check":
        command_check()
    else:
        print(__doc__)
        sys.exit(2)


if __name__ == "__main__":
    main()
