#!/usr/bin/env python3
"""More product renders - angles, environments, colors, lifestyle."""

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
    # KAGI - different angles & colors
    {
        "file": "kagi_white_angle.png",
        "prompt": "Product photography, 45-degree angle top-down view of a white square smart home sensor device 68mm, subtle LED indicator, clean white desk surface, premium minimal Japanese tech aesthetic, soft shadow, studio lighting"
    },
    {
        "file": "kagi_beige.png",
        "prompt": "Product photography of a warm beige/sand colored smart home IoT sensor device, square form 68mm, matte ceramic-like finish, small circular microphone mesh, placed on linen fabric texture, Scandinavian design aesthetic, warm studio lighting"
    },
    {
        "file": "kagi_black_closeup.png",
        "prompt": "Extreme close-up macro product photography of a matte black precision smart home sensor, 68mm square, deep dark surface texture, tiny amber LED dot glow, carbon fiber pattern texture, dark dramatic studio background"
    },
    {
        "file": "kagi_living_room.png",
        "prompt": "Lifestyle photography of a small white smart home sensor mounted on living room wall, modern Japanese interior, warm evening light through window, bookshelf in background, cozy atmosphere, subtle green LED visible"
    },
    {
        "file": "kagi_bedroom.png",
        "prompt": "Lifestyle photography of an egg-shaped dark green smart home sensor on bedside table, minimal Japanese bedroom interior, soft morning light, white bed linen, the device glowing softly green"
    },
    {
        "file": "kagi_hotel.png",
        "prompt": "Lifestyle photography of a sleek white smart home sensor device mounted beside hotel room door, luxury hotel interior, marble wall, warm ambient lighting, premium hospitality IoT device"
    },
    # Koe - more variations
    {
        "file": "koe_coin_hand.png",
        "prompt": "Product photography of a tiny circular IoT audio device being held between thumb and index finger, coin 26mm diameter matte black, purple LED ring glowing, dark background with rim lighting, scale reference showing how small it is"
    },
    {
        "file": "koe_coin_table.png",
        "prompt": "Product photography of multiple small circular IoT devices scattered on dark wood table, coin-shaped 26mm, some glowing different LED colors purple blue green, top-down flat lay shot, minimalist arrangement"
    },
    {
        "file": "koe_fill_concert.png",
        "prompt": "Lifestyle photography of slim vertical wall-mounted speakers at a festival venue, forest green housing, multiple units in a line along venue wall, concert crowd in background, dramatic stage lighting, professional audio installation"
    },
    {
        "file": "koe_sub_room.png",
        "prompt": "Lifestyle photography of a compact subwoofer in modern home listening room, matte black 15-inch driver, red LED base glow, vinyl records on shelf, warm ambient light, audiophile room setup"
    },
    {
        "file": "koe_stage_closeup.png",
        "prompt": "Close-up product photography of a stage monitor speaker with embedded touchscreen display showing real-time audio waveform visualization, Raspberry Pi powered, blue LED ring, dark concert stage background, professional audio equipment"
    },
    {
        "file": "koe_festival.png",
        "prompt": "Wide shot lifestyle photography at an outdoor music festival, multiple Koe speaker devices mounted on poles and walls throughout the venue, crowd enjoying music, sunset sky, LED lights glowing, immersive spatial audio atmosphere, Hawaii festival"
    },
    {
        "file": "koe_pick_ear.png",
        "prompt": "Product photography of a futuristic wireless earpiece IoT device, sleek dark matte finish, small LED indicator, placed on white marble surface with reflection, premium audio accessory, studio lighting, photorealistic"
    },
    {
        "file": "kagi_sensor_exploded.png",
        "prompt": "Technical product illustration of a smart home IoT sensor device exploded view showing internal components: ESP32-S3 circuit board, temperature humidity sensor, PIR motion sensor, ambient light sensor, all floating in white space, clean engineering diagram style"
    },
    {
        "file": "kagi_dashboard.png",
        "prompt": "Lifestyle photography of a smartphone showing a smart home sensor dashboard app, the phone placed next to a white square IoT sensor device, dark wood desk, data visualization charts showing temperature humidity air quality, modern UI"
    },
    {
        "file": "koe_orchestral.png",
        "prompt": "Artistic conceptual photography of dozens of small coin-shaped IoT audio devices arranged in a circular orchestra formation on black surface, each glowing different colors purple blue green amber, top-down bird's eye view, beautiful LED light pattern"
    },
    {
        "file": "kagi_pro_dark.png",
        "prompt": "Dramatic product photography of a premium black square smart home sensor Pro model, matte black CNC housing, purple LED matrix indicator, floating against pure black background, neon lighting effect, luxury tech product, ultra sharp"
    },
    {
        "file": "koe_sub_bass.png",
        "prompt": "Dynamic product photography of a powerful subwoofer speaker, 15-inch driver, matte black enclosure with hexagonal grille pattern, red LED ring illuminating floor beneath it, dramatic studio lighting showing speaker cone texture in detail"
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
            txt = response.candidates[0].content.parts[0].text[:80] if response.candidates else "no response"
            print(f"  ✗ No image: {txt}")
        results.append((p["file"], saved))
    except Exception as e:
        print(f"  ✗ Error: {e}")
        results.append((p["file"], False))
    time.sleep(1.5)

ok = sum(1 for _, s in results if s)
print(f"\n=== {ok}/{len(results)} generated ===")
