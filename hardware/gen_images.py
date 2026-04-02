#!/usr/bin/env python3
"""Generate photo-realistic product renders for KAGI and Koe devices using Imagen."""

import os, base64, time
from pathlib import Path
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
client = genai.Client(api_key=API_KEY)

OUT = Path("/Users/yuki/workspace/kacha/hardware/renders")
OUT.mkdir(exist_ok=True)

PROMPTS = [
    # KAGI designs
    {
        "file": "kagi_hub_minimal.png",
        "prompt": (
            "Professional product photography of a smart home sensor device. "
            "Clean white matte plastic housing, square shape 68x68mm, "
            "subtle green LED strip glowing softly, mounted on white wall, "
            "minimalist Japanese design, floating in pure white studio background, "
            "soft diffused lighting, shot on Canon 5D, 50mm lens, f/8, "
            "product render style, ultra high detail, 4K"
        )
    },
    {
        "file": "kagi_hub_industrial.png",
        "prompt": (
            "Professional product photography of a smart home sensor device. "
            "Matte black CNC-machined aluminum housing, square 68x68mm, "
            "amber/gold LED corner accents and dot matrix display, "
            "sharp industrial design language, dark studio background with dramatic side lighting, "
            "precision engineering aesthetic like a Leica camera or Contax, "
            "shot on Hasselblad, product render, ultra high detail, 4K"
        )
    },
    {
        "file": "kagi_hub_organic.png",
        "prompt": (
            "Professional product photography of a smart home sensor device. "
            "Smooth egg-shaped housing in deep forest green soft-touch matte finish, 68mm, "
            "subtle green bioluminescent glow from base, organic biomorphic form, "
            "placed on natural wood surface with moss, soft bokeh background, "
            "nature-inspired design like a smooth river stone, "
            "shot on Sony A7R5, 85mm macro, f/2.8, product photography, 4K"
        )
    },
    # Koe Coin
    {
        "file": "koe_coin_pebble.png",
        "prompt": (
            "Professional product photography of a tiny circular IoT device, coin-shaped, "
            "26mm diameter, 8mm thick, smooth pebble-like matte black finish, "
            "small RGB LED ring around edge glowing purple, "
            "placed on dark slate surface with dramatic rim lighting, "
            "microphone mesh visible on face, ultra minimal design, "
            "shot on Sony A7R5, 100mm macro lens, f/5.6, product photography, 4K"
        )
    },
    {
        "file": "koe_coin_crystal.png",
        "prompt": (
            "Professional product photography of a tiny circular IoT audio device, coin-shaped, "
            "26mm diameter, translucent frosted glass housing, "
            "internal LED glowing golden-amber light through the diffused glass, "
            "hexagonal geometric facets on surface catching light like crystal, "
            "floating on reflective black acrylic surface, studio lighting, "
            "shot on Hasselblad X2D, 120mm macro, product photography, 4K"
        )
    },
    {
        "file": "koe_fill_wave.png",
        "prompt": (
            "Professional product photography of a wall-mounted smart speaker, "
            "tall slim vertical form factor 80x200mm, deep forest green housing, "
            "8-inch woofer and 1-inch horn tweeter visible behind premium metal mesh grille, "
            "circular green LED ring at top glowing, "
            "mounted on light grey textured wall, clean modern living room context, "
            "shot on Canon R5, 35mm, f/5.6, product lifestyle photography, 4K"
        )
    },
    {
        "file": "koe_sub_wave.png",
        "prompt": (
            "Professional product photography of a compact subwoofer speaker, "
            "wide low-profile form 300x200x120mm, matte black finish with subtle texture, "
            "15-inch front-firing driver behind hexagonal metal mesh grille, "
            "red LED ring glowing around base perimeter, "
            "placed on polished concrete floor, dramatic low-angle side lighting, "
            "industrial chic aesthetic, shot on Phase One IQ4, product photography, 4K"
        )
    },
    {
        "file": "koe_stage_wave.png",
        "prompt": (
            "Professional product photography of a stage monitor speaker system, "
            "compact rectangular unit 300x200mm, Raspberry Pi CM5 powered, "
            "4K HDMI display panel on front showing waveform visualization, "
            "blue LED ring glowing around speaker driver area, "
            "matte black aluminum chassis, placed on stage with dramatic concert lighting, "
            "professional audio equipment aesthetic, shot on Sony A1, 24mm, product photography, 4K"
        )
    },
]

results = []
for i, p in enumerate(PROMPTS):
    print(f"[{i+1}/{len(PROMPTS)}] Generating {p['file']}...")
    try:
        response = client.models.generate_images(
            model="imagen-4.0-generate-001",
            prompt=p["prompt"],
            config=types.GenerateImagesConfig(
                number_of_images=1,
                aspect_ratio="1:1",
                safety_filter_level="BLOCK_LOW_AND_ABOVE",
                person_generation="DONT_ALLOW",
            )
        )
        if response.generated_images:
            img_data = response.generated_images[0].image.image_bytes
            out_path = OUT / p["file"]
            out_path.write_bytes(img_data)
            print(f"  ✓ Saved {out_path}")
            results.append((p["file"], str(out_path), True))
        else:
            print(f"  ✗ No image returned")
            results.append((p["file"], "", False))
    except Exception as e:
        print(f"  ✗ Error: {e}")
        results.append((p["file"], "", False))
    time.sleep(1)

print("\n=== Results ===")
for name, path, ok in results:
    print(f"{'✓' if ok else '✗'} {name}")
