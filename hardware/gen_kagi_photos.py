#!/usr/bin/env python3
"""
KAGI予約サイト用の写真を生成する
ミッション: 「人が一人で死んでいく世界を、テクノロジーで終わらせる」
感情に訴えかける高品質な写真を複数パターン生成
"""
import os, time
from pathlib import Path
from google import genai
from google.genai import types

API_KEY = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
client = genai.Client(api_key=API_KEY)
MODEL = "imagen-4.0-ultra-generate-001"

OUT = Path("/Users/yuki/workspace/kacha/hardware/renders_kagi_new")
OUT.mkdir(exist_ok=True)

PROMPTS = [
    # === 製品ショット ===
    {
        "file": "product_hero_white.png",
        "prompt": "Professional product photography, minimalist Japanese smart home sensor, small white square device 68x68x25mm, soft matte finish, single green breathing LED on front face, floating on pure white background, dramatic side lighting, sharp focus, ultra-high-end consumer electronics aesthetic, Apple-style product shot, 8K photorealistic"
    },
    {
        "file": "product_hero_dark.png",
        "prompt": "Professional product photography, premium smart home safety device, dark matte black square 68x68mm, subtle green glowing LED ring on front, floating in pure darkness with soft rim lighting, mysterious and premium aesthetic, cinematic product shot, ultra-detailed photorealistic"
    },
    {
        "file": "product_trio.png",
        "prompt": "Professional product lineup photography, three smart home devices on white surface: small white square labeled 'Lite', medium warm beige square labeled 'Hub', larger dark square labeled 'Pro', arranged diagonally, soft studio gradient lighting, Japanese minimalist design, premium consumer electronics, photorealistic"
    },
    {
        "file": "product_hand.png",
        "prompt": "Person's hand gently holding a small white square smart home sensor 68x68mm, soft green LED glowing, warm natural light from window, shallow depth of field, care and protection feeling, Japanese aesthetic, photorealistic lifestyle photography"
    },

    # === ライフスタイル / 感情 ===
    {
        "file": "lifestyle_elderly_living.png",
        "prompt": "Warm interior photography, cozy Japanese living room, elderly Japanese woman sitting peacefully reading a book on sofa, small white smart home device mounted discreetly on wall in background, green LED glowing softly, afternoon golden light through shoji screen window, safety and peace feeling, cinematic, photorealistic"
    },
    {
        "file": "lifestyle_family_phone.png",
        "prompt": "Warm lifestyle photography, adult Japanese daughter checking smartphone app showing parent's wellness status with green checkmark and 'お父さん 安全' notification, sitting in modern kitchen with coffee, relieved warm smile, soft morning light, emotional family safety theme, cinematic photorealistic"
    },
    {
        "file": "lifestyle_bedroom_night.png",
        "prompt": "Bedroom interior photography at night, peaceful elderly Japanese person sleeping in bed, small white device on nightstand with soft green LED breathing light pulse, warm ambient nightlight, safety and comfort atmosphere, security without surveillance, cinematic photorealistic"
    },
    {
        "file": "lifestyle_airbnb.png",
        "prompt": "Modern Japanese minimalist Airbnb room photography, clean white walls, wooden furniture, small premium white smart device mounted on wall with subtle green indicator light, hotel-quality interior design, natural afternoon light, guest room safety and hospitality theme, photorealistic"
    },

    # === テクノロジー ===
    {
        "file": "tech_radar_visualization.png",
        "prompt": "Abstract technology visualization, dark background, 60GHz radar wave visualization showing human breathing pattern as concentric green wave rings emanating from a person's silhouette, data visualization aesthetic, green on dark background, futuristic medical monitoring concept, beautiful data art, photorealistic render"
    },
    {
        "file": "tech_board_beauty.png",
        "prompt": "Macro photography of a precision PCB circuit board, green solder mask with gold traces, small IoT sensors mounted including radar module and environmental sensors, technical beauty, shallow depth of field, dramatic top-down lighting, engineering precision aesthetic, high-end electronics manufacturing, photorealistic macro"
    },

    # === アプリUI ===
    {
        "file": "app_dashboard.png",
        "prompt": "Smartphone mockup showing a wellness monitoring app UI, dark elegant interface, large green circle showing 'ACS 94' score with breathing animation, below shows timeline: 'お父さん 最終確認 2分前', clean Japanese typography, premium app design, iPhone 15 Pro held in hand, soft background, photorealistic"
    },
    {
        "file": "app_alert.png",
        "prompt": "Smartphone showing a gentle safety alert notification, dark app interface in Japanese showing amber warning: '3時間反応がありません。確認しますか？' with three buttons: 問題なし / 確認中 / 訪問する, caring design not alarming, iPhone held by worried but hopeful adult, soft light, photorealistic"
    },
]

results = []
for i, p in enumerate(PROMPTS):
    print(f"\n[{i+1}/{len(PROMPTS)}] {p['file']} ...")
    try:
        response = client.models.generate_images(
            model=MODEL,
            prompt=p["prompt"],
            config=types.GenerateImagesConfig(
                number_of_images=1,
                aspect_ratio="16:9",
                output_mime_type="image/png",
            )
        )
        if response.generated_images:
            out_path = OUT / p["file"]
            out_path.write_bytes(response.generated_images[0].image.image_bytes)
            print(f"  ✓ {out_path}")
            results.append((p["file"], True))
        else:
            print(f"  ✗ No image returned")
            results.append((p["file"], False))
    except Exception as e:
        print(f"  ✗ Error: {e}")
        results.append((p["file"], False))
    time.sleep(3)

print("\n=== 完了 ===")
ok = sum(1 for _, s in results if s)
print(f"{ok}/{len(PROMPTS)} 枚生成")
for name, s in results:
    print(f"  {'✓' if s else '✗'} {name}")
