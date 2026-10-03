import Foundation

/// The actions vocabulary in one short page — served at GET /v2/actions, used by hmm-bridge's MCP server and the
/// lowey skill. Kept compact on purpose (it goes into AI context windows).
public enum ScriptReference {
    public static let text = """
    # 3D-lowey Scene Script v3 — actions

    {"version": 3, "title": "...", "actions": [ {"do": ...}, ... ]}   (schemas/scene-script.v3.schema.json)
    The whole script is ONE undo step: a Proposal Hesham applies on the iPad (unless auto-apply is on). v2 scripts still
    work: they upgrade on the way in.

    Conventions
    - Units: metres, degrees, seconds. Y is up; the ground is y = 0. Say WHERE by relation, not coordinates.
    - Targets: an object name (case-insensitive), "Prefix*", an id, or a list. Names given earlier in the script work.
    - Times ("at"): seconds | "now" | "start" | "end" | {"word": "Enigma", "occurrence": 1, "edge": "start|end", "offset": -0.2} | {"marker": "name"}
      Prefer spoken words: shots stay synced if the voiceover moves.
    - Colours: "palette:N" (the project palette — prefer it) or "#RRGGBB".
    - Overlay "at" is frame space: [x, y] from -1 to 1 (0,0 = centre, y up).

    Build (Kit first: find_assets, then add by id; real sizes come with it)
    {"do":"add","asset":"kit.office-desk","name":"Desk","at":[0,0,0]}                 (an id, or words to search the Kit and library)
    {"do":"add","asset":"kit.room-lamproundtable","name":"Lamp","relation":"on","reference":"Desk","offset":[-0.4,0,0]}
    {"do":"place","target":"Lamp","relation":"on|beside_left|beside_right|in_front_of|behind|above|under|inside|facing|around|row|grid|scatter_in|stack",
     "reference":"Desk","offset":[x right, y up, z front],"radius":3,"spacing":0.2,"columns":3,"seed":1}
      Left/right as seen from the reference's front. Everything lands grounded and apart; the reply says where.
    {"do":"scaleTo","target":"Tree","meters":6,"axis":"height|width|depth|longest"}   {"do":"recolor","target":"Sofa","slot":2}
    {"do":"add","shape":"cube|sphere|cylinder|cone|plane|torus|ramp|group","name":"Wall","at":[0,0,-2],"size":[6,3,0.1],"color":"palette:1"}
    {"do":"text","text":"1941","at":[0,0.8,0],"size":0.2,"style":"blocky|rounded|bold|serif|mono"}
    {"do":"blob","likeness":"hesham|newton|einstein|turing|curie|darwin|tesla|lovelace|edison|sherlock|wizard","name":"Me","at":[0,0,0]}
    {"do":"blob","name":"Ada","facing":20,"label":"ADA","recipe":{"hat":"beret","hair":"bob","accessories":["glasses"],"prop":"gear"}}
    {"do":"particles","preset":"fire|sparks|smoke|dust|magic|rain|snow|confetti|embers|explosion","at":"Lamp","amount":1}
    {"do":"group","target":["A","B"],"name":"Set"}  {"do":"rename","target":"Cube","name":"Box"}  {"do":"remove","target":"Box"}
    {"do":"transform","target":"Paper","position":[0,1,0],"rotation":[0,45,0],"scale":2}   (edge cases only)

    Shoot and light
    {"do":"frameShot","subject":"Hesham","shotType":"extremeWide|wide|full|medium|closeUp|extremeCloseUp|overTheShoulder|twoShot|insert",
     "composition":"center|leftThird|rightThird|lowAngle|highAngle","lens":85,"other":"Ada","side":"left|right","camera":"Shot 2","at":{"word":"Nobody"}}
    {"do":"cameraMove","camera":"Shot 2","move":"pushIn|pullOut|punchIn|snapZoom|orbit|dolly|truck|crane|whipPan|shake|reveal","subject":"Paper","at":{"word":"message"},"duration":2,"strength":1}
    {"do":"cut","camera":"Room cam","at":{"word":"people"},"transition":"cut|fade|dipToBlack|wipe|zoomThrough","duration":0.6}
    {"do":"lighting","recipe":"key-warm-world-cool|noir-single-source|golden-rim|monitor-glow|moonlit|studio-soft","subject":"Hesham","intensity":1,"warmth":0.3}
    {"do":"look","look":"ink|comic|sketch|clay|lowpoly","mood":"day|goldenHour|dusk|night|space|studio","perObject":{"Robot":"sketch"},"fog":40,"sceneOnly":true}

    Animate (say the intent; the app picks the animation)
    {"do":"intent","target":"Hesham","what":"enter|exit|emphasise|react|walk_to|look_at|talk|idle","how":"surprised","to":"Door","at":{"word":"Nobody"},"frameRate":"twos"}
    {"do":"preset","target":"Screen*","preset":"popIn|popOut|grow|shrink|bounce|wiggle|float|spin|shake|pulse|fadeIn|fadeOut|slideIn|dropIn|typewriter",
     "at":{"word":"Nobody"},"duration":0.5,"strength":1,"stagger":0.08,"order":"selection|leftToRight|rightToLeft|wave"}
    {"do":"expression","target":"Me","name":"neutral|happy|laugh|smug|surprised|shocked|scared|sad|angry|sleepy|wink|thinking","at":{"word":"what"}}
    {"do":"clip","character":"Me","clip":"Idle|Walk|Run|Talk|Wave|Point|Type|Nod|Shrug|Celebrate","at":0,"loop":true}
    {"do":"lipSync","character":"Me","words":"optional phrase"}
    {"do":"keys","target":"Paper","property":"scale","keys":[{"t":0,"value":[1,1,1]},{"t":{"word":"huge"},"value":[8,8,8],"easing":"easeInOut"}]}
    {"do":"set","target":"Paper","property":"color|opacity|emissiveIntensity|stepping|accent|airborne|smear","value":"#F2E8D5","at":2}
    Easings: linear, easeIn, easeOut, easeInOut, backOut, bounce, elastic, step.

    Story
    {"do":"overlay","shape":"title|label|arrow|highlight|cross|question|exclamation|check|circle|rectangle|triangle|star","text":"1941","at":[0,0.55],"size":1.5,"follow":"Paper"}
    {"do":"flipbook","fx":"speedLines|impactBurst|sweatDrop|sparkle|smear","anchor":"Robot","at":{"word":"boom"},"until":3.2,"color":"#FFFFFF"}
    {"do":"effect","kind":"flash|shake|speedLines|zoomBlur|glitch","at":{"word":"Nobody"},"duration":0.4,"strength":1}
    {"do":"marker","name":"enigma","at":{"word":"Enigma"}}   {"do":"captions","style":"punchy|subtitle|pill|outline","position":"bottom"}
    {"do":"length","seconds":12,"fps":30}

    Good shots: one idea per shot; one subject, the biggest, brightest or most contrasty thing; build only what the lens
    sees; light the subject warm against a cool world; move the camera on a word; hold still between moves; ≤ 7 things.
    """
}
