"""The laptop tools against a fake iPad bridge (same endpoints and replies as the app)."""
import json
import pathlib
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

TOKEN = "t0ken"
RECEIVED = []


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
        if not self.authorized():
            return self.reply(401, {"error": "Pair first"})
        path = self.path.split("?")[0]
        if path == "/v1/scene":
            return self.reply(200, {"scene": "Desk", "objects": [{"name": "Paper", "kind": "plane", "at": [0, 0.76, 0]}]})
        if path == "/v1/transcript":
            return self.reply(200, {"language": "en-US", "words": [{"i": 0, "w": "Enigma", "t": 1.2, "e": 1.8}]})
        if path == "/v1/assets":
            return self.reply(200, [{"name": "Tiger", "kind": "model", "tags": []}])
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
            code = json.loads(body)["code"]
            return self.reply(200, {"token": TOKEN}) if code == "123456" else self.reply(401, {"error": "Wrong code"})
        if not self.authorized():
            return self.reply(401, {"error": "Pair first"})
        RECEIVED.append((path, self.path, body, self.headers.get("X-Lowey-Client")))
        if path == "/v1/script":
            script = json.loads(body)
            dry = "dryRun=1" in self.path
            return self.reply(200, {"applied": not dry, "preview": [f"Adds 1: {script['actions'][0].get('name', '?')}"], "report": [],
                                    "created": {script["actions"][0].get("name", "x"): "id-1"}, "message": "ok"})
        if path == "/v1/snapshot":
            return self.reply(200, b"\x89PNG....", "image/png")
        if path == "/v1/library/import":
            return self.reply(200, {"imported": "tree.glb"})
        if path == "/v1/media/import":
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
    assert "dryRun=1" in RECEIVED[-1][1]


def test_mcp_tools_build_scripts(bridge_host, monkeypatch):
    monkeypatch.setenv("LOWEY_HOST", bridge_host)
    monkeypatch.setenv("LOWEY_TOKEN", TOKEN)
    import importlib

    from lowey_tools import mcp_server
    importlib.reload(mcp_server)
    assert "Paper" in mcp_server.get_scene()
    assert "Enigma" in mcp_server.get_transcript()
    assert "Tiger" in mcp_server.list_assets("tig")
    reply = mcp_server.create_object("cube", "Desk", at=[0, 0, 0], size=[1.6, 0.75, 0.8], color="palette:1")
    assert reply.startswith("Applied.") and "Desk" in reply
    sent = json.loads(RECEIVED[-1][2])
    assert sent["actions"][0] == {"do": "add", "shape": "cube", "name": "Desk", "at": [0, 0, 0], "size": [1.6, 0.75, 0.8], "color": "palette:1"}
    assert RECEIVED[-1][3] == "Claude (lowey-mcp)"
    mcp_server.attach_to_word("Nobody", {"do": "overlay", "shape": "cross"})
    sent = json.loads(RECEIVED[-1][2])
    assert sent["actions"][0]["at"] == {"word": "Nobody", "occurrence": 1, "offset": 0}
    mcp_server.camera_move("pushIn", subject="Paper", at={"word": "message"}, duration=2)
    assert json.loads(RECEIVED[-1][2])["actions"][0]["move"] == "pushIn"
    image = mcp_server.snapshot()
    assert not isinstance(image, str)
    assert "Not applied" in mcp_server.run_script("Preview", [{"do": "add", "name": "X"}], dry_run=True)
    assert mcp_server.actions_reference().startswith("# actions")
    assert "run_script" in mcp_server.plan_shots("Nobody could.")


def test_errors_are_readable(tmp_path, monkeypatch):
    monkeypatch.setenv("LOWEY_CONFIG", str(tmp_path / "none.json"))
    monkeypatch.delenv("LOWEY_HOST", raising=False)
    import importlib

    from lowey_tools import client
    importlib.reload(client)
    with pytest.raises(client.BridgeError, match="lowey-link pair"):
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
    assert RECEIVED[-1][0] == "/v1/media/import" and "name=chart.png" in RECEIVED[-1][1] and "at=2.5" in RECEIVED[-1][1]
    assert RECEIVED[-1][2] == b"PNG"

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
