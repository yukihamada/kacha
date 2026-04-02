#!/usr/bin/env python3
"""More of the favorites: Coin hand scale, flat lay, orchestral."""

import os, time
from pathlib import Path
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
client = genai.Client(api_key=API_KEY)
MODEL = "gemini-3.1-flash-image-preview"

OUT = Path("/Users/yuki/workspace/kacha/hardware/renders_fav")
OUT.mkdir(exist_ok=True)

PROMPTS = [
    # === HAND SCALE SERIES ===
    {
        "file": "coin_hand_purple.png",
        "prompt": "Extreme close-up macro photography, tiny circular IoT device 26mm diameter held between two fingers, matte black coin-shaped, vivid purple LED ring glowing around the edge, dark dramatic background with bokeh, hyper detailed skin texture visible, photorealistic, Canon 100mm macro f/2.8"
    },
    {
        "file": "coin_hand_green.png",
        "prompt": "Product macro photography of a tiny 26mm coin-shaped IoT audio device resting on open palm, matte black pebble-smooth finish, bright green LED ring pulse glow, shallow depth of field background blur, dramatic side lighting, photorealistic, Leica Q3 50mm"
    },
    {
        "file": "coin_hand_blue.png",
        "prompt": "Close-up product photography, small circular 26mm smart device between thumb and index finger pinch gesture, glossy dark surface with ice-blue LED rim light, jet black background, ultra sharp detail on device surface, photorealistic macro"
    },
    {
        "file": "coin_hand_white_bg.png",
        "prompt": "Clean studio product photography of a tiny coin-shaped device 26mm on white marble surface with a hand placing it gently, matte black finish, soft amber LED glow, pure white background, Apple-style product photography, f/8 studio strobe lighting"
    },
    {
        "file": "coin_hand_compare.png",
        "prompt": "Scale comparison product photography: a tiny 26mm circular IoT device next to a Japanese 100 yen coin and a standard USB-C cable connector, all on black slate surface, purple LED ring on device glowing, dramatic rim lighting showing scale, photorealistic"
    },

    # === FLAT LAY SERIES ===
    {
        "file": "flatlay_rainbow.png",
        "prompt": "Top-down flat lay product photography, 9 small circular IoT devices 26mm each arranged in a 3x3 grid on dark textured slate, each device glowing a different color LED ring: red, orange, yellow, green, cyan, blue, indigo, violet, white, perfect overhead lighting, ultra sharp"
    },
    {
        "file": "flatlay_scatter.png",
        "prompt": "Artistic flat lay, dozens of tiny coin-shaped IoT devices scattered randomly on rich dark walnut wood surface, various colored LED rings glowing purple blue green amber, some overlapping, top-down overhead shot, moody dramatic lighting"
    },
    {
        "file": "flatlay_lineup.png",
        "prompt": "Clean product flat lay, 5 circular coin IoT devices 26mm arranged in a perfect row on black acrylic surface with mirror reflection, LED colors from left: purple, blue, green, amber, red, each glowing softly, minimal composition, studio overhead lighting"
    },
    {
        "file": "flatlay_hand_pour.png",
        "prompt": "Dynamic product photography, hand pouring multiple tiny circular IoT coin devices 26mm onto dark slate surface, devices tumbling mid-air and landing, purple and green LED rings visible, motion blur on falling devices, dramatic studio lighting"
    },
    {
        "file": "flatlay_packaging.png",
        "prompt": "Product unboxing flat lay, minimalist matte black box opened to reveal a tiny coin-shaped IoT device 26mm nestled in foam inset, USB-C cable, quick start card, dark wood background, soft diffused lighting, premium packaging photography"
    },

    # === ORCHESTRAL / CONCEPT SERIES ===
    {
        "file": "orchestral_topdown.png",
        "prompt": "Bird's eye view artistic concept photography, 200 tiny circular IoT devices arranged in perfect concentric circles like a vinyl record groove pattern on pure black surface, each device lit with different LED colors creating a rainbow gradient spiral pattern, stunning visual, ultra wide shot"
    },
    {
        "file": "orchestral_wave.png",
        "prompt": "Artistic installation photography, hundreds of small circular IoT devices arranged in a sine wave pattern across a large dark floor, LED colors transitioning from purple to blue to green creating a visual sound wave, long exposure photography, concert hall setting"
    },
    {
        "file": "orchestral_crowd.png",
        "prompt": "Conceptual art photography, aerial view of outdoor music festival crowd at night in Hawaii, each person holding or wearing a glowing small IoT device, thousands of colored LED lights creating patterns across the crowd like a living light show, photorealistic"
    },
    {
        "file": "orchestral_close.png",
        "prompt": "Close-up artistic photography of dozens of small circular IoT devices arranged tightly together, multiple LED colors purple blue green gold cyan glowing intensely, shallow depth of field bokeh background, abstract tech art, ultra detailed surface texture"
    },
    {
        "file": "orchestral_stage.png",
        "prompt": "Wide angle concert photography, large stage with massive LED screen background, musicians performing, and hundreds of audience members holding small glowing IoT coin devices creating synchronized rainbow light patterns throughout the crowd, Hawaii outdoor venue, palm trees visible, photorealistic"
    },
    {
        "file": "orchestral_floor_art.png",
        "prompt": "Architectural installation art photography, 500 tiny circular IoT devices arranged on gallery floor forming the shape of a sound wave or musical note, LED colors creating gradient, museum white walls and ceiling reflected in black polished floor, photorealistic installation art"
    },
]

results = []
for i, p in enumerate(PROMPTS):
    print(f"[{i+1}/{len(PROMPTS)}] {p['file']}...")
    try:
        response = client.models.generate_content(
            model=MODEL,
            contents=p["prompt"],
            config=types.GenerateContentConfig(
                response_modalities=["IMAGE", "TEXT"],
                temperature=1.0,
            )
        )
        saved = False
        for part in response.candidates[0].content.parts:
            if hasattr(part, "inline_data") and part.inline_data:
                out_path = OUT / p["file"]
                out_path.write_bytes(part.inline_data.data)
                print(f"  ✓ {p['file']}")
                saved = True
                break
        if not saved:
            txt = response.candidates[0].content.parts[0].text[:80] if response.candidates else ""
            print(f"  ✗ No image: {txt}")
        results.append((p["file"], saved))
    except Exception as e:
        print(f"  ✗ {e}")
        results.append((p["file"], False))
    time.sleep(1.5)

ok = sum(1 for _, s in results if s)
print(f"\n=== {ok}/{len(results)} generated ===")
for name, s in results:
    print(f"  {'✓' if s else '✗'} {name}")
