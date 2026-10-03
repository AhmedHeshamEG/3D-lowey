"""The laptop tools against a fake iPad bridge (same endpoints and replies as the app): every MCP tool goes through it."""
import base64
import json
import pathlib
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

TOKEN = "t0ken"
RECEIVED = []
PAIRED = []
PNG = b"\x89PNG\r\n\x1a\nfake"
OBSERVE = {"summary": "Through “Shot”: “Paper” (mark 1) is the likely subject.", "report": {"objects": [{"name": "Paper", "mark": 1}]},
           "images": {"camera": base64.b64encode(PNG).decode(), "top": base64.b64encode(PNG).decode()}}


class FakeBridge(BaseHTTPRequestHandler):
    def log_message(self, *args):  # quiet
        pass

    def reply(self, status, payload, kind="application/json"):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self):
        return self.headers.get("Authorization") == f"Bearer {TOKEN}"

    def body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", 0)))

    def do_GET(self):  # noqa: N802
        if self.path == "/v1/hello":
            return self.reply(200, {"app": "lowey", "appVersion": "2.0.0", "device": "iPad", "bridgeVersion": 2, "pairing": True})
        if not self.authorized():
            return self.reply(401, {"error": "Pair first"})
        path = self.path.split("?")[0]
        RECEIVED.append((path, self.path, b"", self.headers.get("X-Lowey-Client")))
        if path == "/v2/status":
            return self.reply(200, {"app": "3D-lowey", "bridge": 2, "project": "Enigma", "scene": "Desk", "shot": "Shot", "autoApply": False})
        if path == "/v2/project":
            return self.reply(200, {"summary": "“Enigma”, scene “Desk”", "shots": [{"camera": "Shot", "at": [0]}], "cast": ["Hesham"]})
        if path == "/v2/transcript":
            return self.reply(200, {"language": "en-US", "words": [{"i": 0, "w": "Enigma", "t": 1.2, "e": 1.8}]})
        if path == "/v2/actions":
            return self.reply(200, b"# 3D-lowey Scene Script v3", "text/markdown")
        if path == "/v2/assets":
            return self.reply(200, [{"id": "kit.office-desk", "name": "Desk", "set": "Office & Computers", "size": [1.4, 0.75, 0.7],
                                     "surfaces": [0.75], "rigged": False, "tags": []}])
        if path == "/v2/thumbnail":
            return self.reply(200, PNG, "image/png")
        if path == "/v1/renders":
            return self.reply(200, ["Shot 16x9.mp4"])
        if path.startswith("/v1/renders/"):
            return self.reply(200, b"MP4DATA", "video/mp4")
        if path == "/v1/actions":
            return self.reply(200, b"# actions", "text/markdown")
        return self.reply(404, {"error": "no"})

    def do_POST(self):  # noqa: N802
        path = self.path.split("?")[0]
        body = self.body()
        if path == "/v1/pair":
            request = json.loads(body)
            PAIRED.append(request.get("client"))
            return self.reply(200, {"token": TOKEN, "client": "c1"}) if request["code"] == "123456" else self.reply(401, {"error": "Wrong code"})
        if not self.authorized():
            return self.reply(401, {"error": "Pair first"})
        RECEIVED.append((path, self.path, body, self.headers.get("X-Lowey-Client")))
        if path == "/v2/build":
            script = json.loads(body)
            dry = script.get("dry_run", False)
            return self.reply(200, {"proposal_id": "p-1" if dry else None, "applied": not dry,
                                    "diff": [f"Adds 1: {script['actions'][0].get('name', '?')}"], "report": ["did it"],
                                    "observe": OBSERVE, "message": "dry run" if dry else "Applied (one undo step)"})
        if path == "/v2/observe":
            return self.reply(200, OBSERVE)
        if path == "/v2/contact_sheet":
            return self.reply(200, {"summary": "6 frames over 4.0 s.", "report": {"frames": [], "motion": []},
                                    "image": base64.b64encode(PNG).decode()})
        if path == "/v2/commit":
            request = json.loads(body)
            if request["action"] == "undo":
                return self.reply(200, {"undone": request.get("steps", 1)})
            return self.reply(200, {"applied": True, "diff": ["Adds 1: Paper"], "report": [], "observe": OBSERVE, "message": "Applied"})
        if path == "/v1/library/import":
            return self.reply(200, {"imported": "tree.glb"})
        if path == "/v2/media":
            return self.reply(200, {"added": "graph.mov", "id": "id-9", "name": "graph"})
        return self.reply(404, {"error": "no"})


@pytest.fixture()
def bridge_host(tmp_path, monkeypatch):
    server = HTTPServer(("127.0.0.1", 0), FakeBridge)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    monkeypatch.setenv("LOWEY_CONFIG", str(tmp_path / "config.json"))
    import importlib

    from lowey_tools import client
    importlib.reload(client)
    yield f"127.0.0.1:{server.server_port}"
    server.shutdown()


def test_pairing_and_link_cli(bridge_host, tmp_path, monkeypatch):
    from lowey_tools import client, link
    importlib = __import__("importlib")
    importlib.reload(link)
    assert link.main(["pair", bridge_host, "000000"]) == 1, "wrong code fails cleanly"
    assert link.main(["pair", bridge_host, "123456"]) == 0
    config = json.loads(pathlib.Path(client.CONFIG).read_text())
    assert config["token"] == TOKEN
    model = tmp_path / "tree.glb"
    model.write_bytes(b"glTF")
    assert link.main(["push", str(model)]) == 0
    assert RECEIVED[-1][0] == "/v1/library/import" and "name=tree.glb" in RECEIVED[-1][1]
    monkeypatch.chdir(tmp_path)
    assert link.main(["pull"]) == 0
    assert (tmp_path / "renders" / "Shot 16x9.mp4").read_bytes() == b"MP4DATA"
    script = tmp_path / "shot.json"
    script.write_text(json.dumps({"title": "Shot", "actions": [{"do": "add", "name": "Paper"}]}))
    assert link.main(["script", str(script), "--dry-run"]) == 0
    assert RECEIVED[-1][0] == "/v2/build" and json.loads(RECEIVED[-1][2])["dry_run"] is True
    assert link.main(["observe", "--views", "camera", "top", "--to", str(tmp_path / "seen")]) == 0
    assert (tmp_path / "seen" / "top.png").read_bytes() == PNG
    assert json.loads((tmp_path / "seen" / "report.json").read_text())["objects"][0]["name"] == "Paper"


def _sent():
    return json.loads(RECEIVED[-1][2])


def test_the_sixteen_tools_go_through_the_bridge(bridge_host, monkeypatch, tmp_path):
    """MCP v2: exactly 16 tools, and each one reaches the right endpoint with the right Scene Script v3."""
    monkeypatch.setenv("LOWEY_HOST", bridge_host)
    monkeypatch.setenv("LOWEY_TOKEN", TOKEN)
    import asyncio
    import importlib

    from lowey_tools import manim_render, mcp_server
    importlib.reload(mcp_server)
    names = sorted(tool.name for tool in asyncio.run(mcp_server.mcp.list_tools()))
    assert names == sorted(["status", "read_project", "find_assets", "build", "frame_shot", "light", "set_look", "animate", "camera_move",
                            "add_overlay", "flipbook", "add_media", "render_manim", "observe", "contact_sheet", "commit"])

    # 1–3: reading
    assert '"bridge":2' in mcp_server.status() and RECEIVED[-1][0] == "/v2/status"
    project = json.loads(mcp_server.read_project(transcript=True))
    assert project["cast"] == ["Hesham"] and project["timedWords"][0]["w"] == "Enigma"
    found = mcp_server.find_assets("desk", set="Office & Computers", thumbnails=1)
    assert json.loads(found[0])[0]["id"] == "kit.office-desk" and len(found) == 2, "metadata + one thumbnail"
    assert any(entry[0] == "/v2/assets" and "set=Office" in entry[1] for entry in RECEIVED)
    assert RECEIVED[-1][0] == "/v2/thumbnail" and "id=kit.office-desk" in RECEIVED[-1][1]

    # 4: build — one batch, the diff, and an observe of the result with its pictures
    reply = mcp_server.build([{"do": "add", "asset": "kit.office-desk", "name": "Desk"},
                              {"do": "place", "target": "Lamp", "relation": "on", "reference": "Desk"}], title="Desk", views=["camera", "top"])
    assert reply[0].startswith("Applied.") and "Observe:" in reply[0] and len(reply) == 3
    assert _sent()["actions"][1]["relation"] == "on" and _sent()["title"] == "Desk"
    assert RECEIVED[-1][3] == "Claude (hmm-bridge)"
    dry = mcp_server.build([{"do": "add", "name": "Paper"}], dry_run=True)
    assert "proposal_id: p-1" in dry[0]

    # 5–11: directing, each one small build
    mcp_server.frame_shot("Hesham", shot_type="closeUp", composition="leftThird", lens=85, shot="Close", on_word="Nobody")
    assert _sent()["actions"][0] == {"do": "frameShot", "subject": "Hesham", "shotType": "closeUp", "composition": "leftThird", "lens": 85,
                                     "camera": "Close", "at": {"word": "Nobody"}}
    mcp_server.light("golden-rim", subject="Hesham", warmth=0.4)
    assert _sent()["actions"][0] == {"do": "lighting", "recipe": "golden-rim", "subject": "Hesham", "warmth": 0.4}
    assert _sent()["views"] == ["camera", "value"]
    mcp_server.set_look(look="comic", mood="dusk", per_object={"Robot": "sketch"})
    assert _sent()["actions"][0]["perObject"] == {"Robot": "sketch"} and _sent()["actions"][0]["look"] == "comic"
    mcp_server.animate("Hesham", "react", how="surprised", on_word="Nobody", frame_rate="twos")
    assert _sent()["actions"][0] == {"do": "intent", "target": "Hesham", "what": "react", "how": "surprised", "at": {"word": "Nobody"},
                                     "frameRate": "twos"}
    mcp_server.animate(["Screen 1", "Screen 2"], "popIn", at=2)
    assert _sent()["actions"][0] == {"do": "preset", "target": ["Screen 1", "Screen 2"], "preset": "popIn", "at": 2}
    mcp_server.animate("Hesham", "Wave", at=1)
    assert _sent()["actions"][0]["do"] == "clip"
    mcp_server.camera_move("pushIn", shot="Close", subject="Paper", on_word="message", duration=2)
    assert _sent()["actions"][0] == {"do": "cameraMove", "move": "pushIn", "camera": "Close", "subject": "Paper", "at": {"word": "message"},
                                     "duration": 2}
    mcp_server.add_overlay("title", text="BERLIN · 1941", on_word="1941", style={"at": [0, 0.6], "size": 0.8})
    overlay, pop = _sent()["actions"]
    assert overlay["shape"] == "title" and overlay["at"] == [0, 0.6] and pop == {"do": "preset", "target": "BERLIN · 1941",
                                                                                   "preset": "typewriter", "at": {"word": "1941"}}
    mcp_server.flipbook("impactBurst", "Screen 5", on_word="Nobody", color="#FFFFFF")
    assert _sent()["actions"][0] == {"do": "flipbook", "fx": "impactBurst", "anchor": "Screen 5", "at": {"word": "Nobody"}, "color": "#FFFFFF"}

    # 12–13: media from the laptop
    picture = tmp_path / "chart.png"
    picture.write_bytes(b"PNG")
    assert '"added":"graph.mov"' in mcp_server.add_media(str(picture), at=3, overlay=True)
    assert RECEIVED[-1][0] == "/v2/media" and "as=overlay" in RECEIVED[-1][1] and "at=3" in RECEIVED[-1][1]
    made = tmp_path / "Graph.mov"
    made.write_bytes(b"MOV")
    rendered = []
    monkeypatch.setattr(manim_render, "render", lambda source, scene, work, **kw: rendered.append(source.read_text()) or made)
    assert '"added"' in mcp_server.render_manim("from manim import *\nclass Graph(Scene): pass\n", "Graph", at=1.5)
    assert rendered and "class Graph" in rendered[0], "source code is written to a file and rendered"
    assert RECEIVED[-1][2] == b"MOV" and "as=overlay" in RECEIVED[-1][1]

    # 14–15: seeing
    seen = mcp_server.observe(views=["camera", "top", "nonsense"], subject="Paper")
    assert seen[0].startswith("Through") and len(seen) == 3
    assert _sent() == {"views": ["camera", "top"], "subject": "Paper", "long_side": 1280}
    sheet = mcp_server.contact_sheet(start=0, end=4, frames=6)
    assert sheet[0].startswith("6 frames") and len(sheet) == 2
    assert _sent() == {"from": 0, "to": 4, "frames": 6}

    # 16: commit and undo
    committed = mcp_server.commit(proposal_id="p-1")
    assert committed[0].startswith("Applied.") and _sent() == {"action": "commit", "proposal_id": "p-1"}
    assert mcp_server.commit("undo", steps=2) == "Undone 2 step(s)." and _sent() == {"action": "undo", "steps": 2}
    assert mcp_server.commit().startswith("Error"), "commit needs a proposal id"

    # Resources and the director prompt
    assert "Scene Script v3" in mcp_server.actions_resource()
    assert "find_assets" in mcp_server.direct("A robot finds a question mark in a cave.")


def test_pair_with_only_the_code(bridge_host, monkeypatch):
    """`lowey-link pair 123456` finds the iPad itself (Bonjour); when nothing answers it says what to do."""
    from lowey_tools import client, link
    importlib = __import__("importlib")
    importlib.reload(link)
    monkeypatch.setattr(link, "discover", lambda: [])
    assert link.main(["pair", "123456"]) == 1
    monkeypatch.setattr(link, "discover", lambda: [bridge_host])
    assert link.main(["pair", "123456"]) == 0
    assert json.loads(pathlib.Path(client.CONFIG).read_text())["host"] == bridge_host
    assert isinstance(client.discover(timeout=0.3), list), "discovery never raises (no network is fine)"


def test_finds_the_ipad_again_after_its_address_changed(bridge_host, monkeypatch):
    """The saved address stopped answering (Wi-Fi gave the iPad a new one): Bonjour finds it, the config remembers it."""
    from lowey_tools import client
    monkeypatch.delenv("LOWEY_HOST", raising=False)
    client.save_config({"host": "127.0.0.1:9", "token": TOKEN})
    monkeypatch.setattr(client, "discover", lambda timeout=3.0: [bridge_host])
    assert client.Bridge().status()["scene"] == "Desk"
    assert json.loads(pathlib.Path(client.CONFIG).read_text())["host"] == bridge_host


def test_pairing_needs_the_code_from_the_ipad(bridge_host, monkeypatch):
    """There is no default code: without the one on the iPad's screen, nothing is sent."""
    from lowey_tools import client, link
    importlib = __import__("importlib")
    importlib.reload(link)
    monkeypatch.setattr(link, "discover", lambda: [bridge_host])
    sent = []
    monkeypatch.setattr(client.Bridge, "pair", lambda self, code, client=None: sent.append(code))
    assert link.main(["pair"]) == 1
    assert sent == [], "no request without a code"
    assert not hasattr(client, "DEFAULT_CODE")


def test_pairing_names_this_laptop_and_any_order_works(bridge_host, monkeypatch):
    from lowey_tools import link
    importlib = __import__("importlib")
    importlib.reload(link)
    assert link.main(["pair", "123456", bridge_host]) == 0, "address and code in any order"
    assert PAIRED[-1], "the iPad gets a name to list (and revoke) this laptop by"


def test_discovery_keeps_only_3d_lowey(bridge_host, monkeypatch):
    """Other hmm apps advertise the same service type: /v1/hello tells them apart."""
    from lowey_tools import client
    monkeypatch.setattr(client, "_mdns_hosts", lambda timeout: ["127.0.0.1:9", bridge_host])
    assert client.discover(timeout=0.1) == [bridge_host]
    assert client.hello(bridge_host)["app"] == "lowey"


def test_errors_are_readable(tmp_path, monkeypatch):
    monkeypatch.setenv("LOWEY_CONFIG", str(tmp_path / "none.json"))
    monkeypatch.delenv("LOWEY_HOST", raising=False)
    import importlib

    from lowey_tools import client
    importlib.reload(client)
    with pytest.raises(client.BridgeError, match="hmm-bridge pair"):
        client.Bridge()
    unreachable = client.Bridge(host="127.0.0.1:9", token="x", timeout=2)
    with pytest.raises(client.BridgeError, match="Can't reach"):
        unreachable.status()
    assert client.normalize_host("http://10.0.0.2/") == "10.0.0.2:7717"


def test_media_and_manim_reach_the_shot(bridge_host, tmp_path, monkeypatch):
    from lowey_tools import link, manim_render
    importlib = __import__("importlib")
    importlib.reload(link)
    assert link.main(["pair", bridge_host, "123456"]) == 0
    picture = tmp_path / "chart.png"
    picture.write_bytes(b"PNG")
    assert link.main(["media", str(picture), "--at", "2.5"]) == 0
    assert RECEIVED[-1][0] == "/v2/media" and "name=chart.png" in RECEIVED[-1][1] and "at=2.5" in RECEIVED[-1][1]
    assert RECEIVED[-1][2] == b"PNG"
    assert "as=card" in RECEIVED[-1][1], "pictures stand in the world as cards by default"
    assert link.main(["media", str(picture), "--overlay"]) == 0
    assert "as=overlay" in RECEIVED[-1][1]

    # Manim: the command asks for transparent PNG frames at 30 fps in a private media folder…
    command = manim_render.manim_command(pathlib.Path("scene.py"), "Graph", tmp_path / "m", "high", 30, True)
    assert command[1:4] == ["-m", "manim", "render"] and "--transparent" in command and command[-2:] == ["scene.py", "Graph"]
    assert "--fps" in command and "30" in command
    assert "--format" in command and command[command.index("--format") + 1] == "png"

    # …and the frames become a ProRes 4444 movie with alpha (when PyAV is here: it comes with Manim).
    av = pytest.importorskip("av")
    image = pytest.importorskip("PIL.Image")
    frames = []
    for index in range(3):
        path = tmp_path / f"Graph{index:04d}.png"
        image.new("RGBA", (64, 36), (255, 0, 0, 120 + index * 40)).save(path)
        frames.append(path)
    movie = manim_render.pack_prores(frames, tmp_path / "Graph.mov", 30)
    with av.open(str(movie)) as container:
        stream = container.streams.video[0]
        assert stream.codec_context.name == "prores"
        assert "a" in stream.codec_context.pix_fmt, "the movie keeps its alpha"


def test_http_mode_is_localhost_only():
    from lowey_tools import remote
    assert remote.url() == "http://127.0.0.1:8765/mcp"
    assert remote.LOCALHOST == "127.0.0.1"
    import lowey_tools
    package = pathlib.Path(lowey_tools.__file__).parent
    assert not (package / "public.py").exists(), "no internet mode"
