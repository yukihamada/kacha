#!/usr/bin/env python3
"""Generate product renders using Gemini image generation models."""

import os, time
from pathlib import Path
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
client = genai.Client(api_key=API_KEY)

MODEL = "gemini-3.1-flash-image-preview"

OUT = Path("/Users/yuki/workspace/kacha/hardware/renders_gemini")
OUT.mkdir(exist_ok=True)

PROMPTS = [
    {
        "file": "kagi_minimal.png",
        "prompt": "Product photography of a smart home IoT sensor, clean white square device 68x68mm with subtle green LED strip, mounted on white wall, minimalist Japanese design, soft studio lighting, white background, ultra-detailed, photorealistic"
    },
    {
        "file": "kagi_industrial.png",
        "prompt": "Product photography of a smart home sensor device, matte black CNC-machined square housing with amber LED dot matrix display and corner bracket accents, dark background dramatic lighting, precision industrial design aesthetic, photorealistic"
    },
    {
        "file": "kagi_organic.png",
        "prompt": "Product photography of an egg-shaped smart home sensor, deep forest green soft-touch matte finish 68mm, glowing green LED from base, placed on wooden surface with moss, biomorphic organic design, natural bokeh background, photorealistic"
    },
    {
        "file": "koe_coin_dark.png",
        "prompt": "Macro product photography of a tiny coin-shaped IoT device 26mm diameter, matte black pebble-smooth finish, purple LED ring glow around edge, microphone mesh on face, dark slate surface with rim lighting, ultra-detailed macro photo"
    },
    {
        "file": "koe_coin_glass.png",
        "prompt": "Macro product photography of a coin-shaped IoT audio device 26mm, frosted translucent glass housing with golden amber internal LED glow, hexagonal crystal facets on surface, black reflective surface, studio product photography, photorealistic"
    },
    {
        "file": "koe_fill_speaker.png",
        "prompt": "Product photography of a slim wall-mounted speaker, vertical form factor, forest green housing, 8-inch woofer and tweeter behind premium metal mesh grille, green LED ring at top, mounted on grey wall, modern living room, photorealistic"
    },
    {
        "file": "koe_sub_speaker.png",
        "prompt": "Product photography of a compact subwoofer, wide low-profile matte black enclosure, 15-inch front-firing driver behind hexagonal metal mesh grille, red LED ring glowing at base, polished concrete floor, dramatic side lighting, photorealistic"
    },
    {
        "file": "koe_stage_monitor.png",
        "prompt": "Product photography of a stage monitor speaker with embedded display, Raspberry Pi powered, rectangular black unit with 4K touchscreen showing audio waveform, blue LED halo around speaker driver, concert stage environment, dramatic lighting, photorealistic"
    },
    {
        "file": "kagi_lineup.png",
        "prompt": "Product photography of three smart home sensors lined up: small white minimal square (Lite), medium forest green egg-shape (Hub), large black precision square (Pro), studio white background, professional product lineup shot, photorealistic"
    },
    {
        "file": "koe_lineup.png",
        "prompt": "Product photography lineup of IoT audio devices: tiny coin 26mm, slim vertical wall speaker, compact stage monitor with display, subwoofer, dark studio background, dramatic gradient lighting, professional hardware product photography, photorealistic"
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
                print(f"  ✓ {out_path}")
                saved = True
                break
        if not saved:
            txt = response.candidates[0].content.parts[0].text if response.candidates else "no response"
            print(f"  ✗ No image: {txt[:80]}")
        results.append((p["file"], saved))
    except Exception as e:
        print(f"  ✗ Error: {e}")
        results.append((p["file"], False))
    time.sleep(2)

print("\n=== Done ===")
ok = sum(1 for _, s in results if s)
print(f"{ok}/{len(results)} images generated")
for name, s in results:
    print(f"  {'✓' if s else '✗'} {name}")
