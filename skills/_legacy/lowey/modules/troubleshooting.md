# Troubleshooting

| What happened | Do this |
|---|---|
| `409 Open a project on the iPad first` | Ask Hesham to open the project; don't retry in a loop. |
| `422` from `run_script` | The message names the action (`Action 4: …`). Fix that action only and resend. Use `dry_run=True` to check. |
| "Hesham said no" | Ask what to change. Don't resend the same script. |
| `unknown likeness` | Use a `recipe` with 2–3 clues (see `characters.md`). |
| A word isn't found | `get_transcript` again; words are matched case-insensitively; use `occurrence` for repeats. |
| Snapshot shows floating/overlapping things | A small follow-up script moving by name; never rebuild the shot. |
| Manim render fails | Show the Manim error line; common fixes: install LaTeX for `MathTex`, or use `Text`. PyAV/ffmpeg come with Manim. |
| Media doesn't play on the iPad | It must be H.264/HEVC (.mp4/.mov) or ProRes 4444 (transparent). `render_manim` already produces the right thing. |
| The bridge is unreachable | `lowey-link status`; the iPad must be on the same Wi-Fi with the bridge on and this laptop paired (Actions ▸ AI & laptop ▸ Pair a laptop, then `lowey-link pair <code>`). |
