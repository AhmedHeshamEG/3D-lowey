import Foundation

/// The actions vocabulary in one short page — served at GET /v1/actions, used by lowey-mcp and the Claude skills.
/// Kept compact on purpose (it goes into AI context windows).
public enum ScriptReference {
    public static let text = """
    # 3D-lowey Scene Script (v2) — actions

    POST /v1/script  {"title": "...", "actions": [ {"do": ...}, ... ]}   (?dryRun=1 to preview)
    The whole script is ONE undo step. Hesham approves it on the iPad unless auto-apply is on.

    Conventions
    - Units: metres, degrees, seconds. Y is up; the ground is y = 0; objects stand on the ground unless "at" has a height.
    - Targets: an object name (case-insensitive), "Prefix*", an id, or a list. Names given earlier in the script work.
    - Times ("at"): seconds | "now" | "start" | "end" | {"word": "Enigma", "occurrence": 1, "edge": "start|end", "offset": -0.2} | {"marker": "name"}
      Prefer spoken words: shots stay synced if the voiceover moves.
    - Colours: "#RRGGBB" or "palette:N" (the project palette — prefer it, it keeps the look consistent).
    - Overlay "at" is frame space: [x, y] from -1 to 1 (0,0 = centre, y up).

    Build
    {"do":"add","shape":"cube|sphere|cylinder|cone|plane|torus|ramp|group","name":"Desk","at":[0,0,0],"size":[1.6,0.75,0.8],"color":"palette:1","rotation":[0,30,0],"glow":2,"parent":"Room"}
    {"do":"place","asset":"tiger","name":"Tiger","at":[2,0,0],"scale":1.2}        (library search; see GET /v1/assets?q=)
    {"do":"text","text":"1941","at":[0,0.8,0],"size":0.2,"style":"blocky|rounded|bold|serif|mono"}
    {"do":"light","type":"point|spot|sun","at":[0,2,0],"color":"#FFB347","intensity":2}
    {"do":"character","name":"Me","at":[1,0,0],"facing":-30,"recipe":{"hair":"short","top":"hoodie","extras":["beard"]}}
    {"do":"particles","preset":"fire|sparks|smoke|dust|magic|rain|snow|confetti|embers|explosion","at":"Lamp","amount":1,"time":{"word":"boom"}}
    {"do":"array","target":"Desk","count":6,"step":[2,0,0]}   {"do":"scatter","target":"Tree","count":30,"radius":8,"at":[0,0,0]}
    {"do":"group","target":["A","B"],"name":"Set"}  {"do":"rename","target":"Cube","name":"Box"}  {"do":"delete","target":"Box"}

    Change & animate
    {"do":"set","target":"Paper","property":"color","value":"#F2E8D5"}               (add "at" to key it instead)
    {"do":"transform","target":"Paper","position":[0,1,0],"rotation":[0,45,0],"scale":2,"relative":false,"at":2.5,"easing":"backOut"}
    {"do":"keys","target":"Paper","property":"scale","keys":[{"t":0,"value":[1,1,1]},{"t":{"word":"huge"},"value":[8,8,8],"easing":"easeInOut"}]}
    {"do":"preset","target":"Screen*","preset":"popIn|popOut|grow|shrink|bounce|wiggle|float|spin|shake|pulse|fadeIn|fadeOut|slideIn|dropIn|typewriter",
     "at":{"word":"Nobody"},"duration":0.5,"strength":1,"stagger":0.08,"order":"selection|leftToRight|rightToLeft|wave"}
    Properties: position, rotation, scale, color, opacity, emissiveIntensity (glow), lightIntensity, fieldOfView, reveal (0-1), emission.
    Easings: linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step.

    Camera
    {"do":"camera","name":"Desk cam","from":[0,1.6,2.2],"lookAt":"Paper","focalLength":35,"aperture":2.8,"active":true}
    {"do":"cameraMove","camera":"Desk cam","move":"pushIn|pullOut|punchIn|orbit|dolly|truck|crane|whipPan|shake|reveal","subject":"Paper","at":{"word":"message"},"duration":2}
    {"do":"cut","camera":"Room cam","at":{"word":"people"},"transition":"cut|fade|dipToBlack|wipe|zoomThrough","duration":0.6}

    Story
    {"do":"overlay","shape":"title|label|arrow|highlight|cross|question|exclamation|check|circle|rectangle|triangle|star","text":"1941","at":[0,0.55],"size":1.5,"follow":"Paper","color":"#E4572E"}
    {"do":"effect","kind":"flash|shake|speedLines|zoomBlur|glitch","at":{"word":"Nobody"},"duration":0.4,"strength":1}
    {"do":"clip","character":"Me","clip":"Idle|Walk|Run|Talk|Wave|Point|Type|Nod|Shrug|Celebrate","at":0,"loop":true}
    {"do":"lipSync","character":"Me","words":"optional phrase"}
    {"do":"marker","name":"enigma","at":{"word":"Enigma"}}   {"do":"captions","style":"punchy|subtitle|pill|outline","position":"bottom"}
    {"do":"look","mood":"day|goldenHour|dusk|night|space|studio","post":"clean|cinematic|dreamy|retro|comic|collage|oldFilm","fog":40,"sceneOnly":true}
    {"do":"length","seconds":12,"fps":30}
    {"do":"command","command":{...raw EditCommand...}}

    Good shots: one idea per shot; a clear subject; light the subject warm against a cool world; move the camera on a word;
    pop things in on the word that names them; keep 4–8 objects per shot unless it's a crowd (use array/scatter).
    """
}
