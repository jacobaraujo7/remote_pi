#!/usr/bin/env python3
"""Gera os PNGs do ícone do app no macOS a partir da arte de canto a canto.

O macOS (Big Sur em diante) não recorta o ícone: o app entrega o formato pronto.
A grade da Apple é um corpo de 824×824 px centrado numa tela transparente de
1024×1024, com cantos contínuos e uma sombra leve. Sem isso o ícone aparece
como um quadrado maior que os outros no Dock.

A fonte é a arte de canto a canto do iOS (o iOS e o Android aplicam a própria
máscara; ver `flutter_launcher_icons` no pubspec.yaml).

Uso (Python 3 + Pillow), a partir de `cockpit/`:

    python3 tool/macos_app_icon.py \\
        ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png \\
        macos/Runner/Assets.xcassets/AppIcon.appiconset
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

CANVAS = 1024
BODY = 824  # corpo do ícone na grade da Apple: margem de 100 px
# Superelipse |x|^n + |y|^n = 1: aproxima os cantos contínuos da Apple.
EXPONENT = 5.0
SUPERSAMPLE = 4  # borda da máscara suave
SHADOW_ALPHA = 77  # preto a ~30%
SHADOW_OFFSET_Y = 10
SHADOW_BLUR = 10
SIZES = (16, 32, 64, 128, 256, 512, 1024)


def squircle_mask(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    r = big / 2
    mask = Image.new("L", (big, big), 0)
    draw = ImageDraw.Draw(mask)
    for y in range(big):
        dy = abs((y + 0.5 - r) / r) ** EXPONENT
        if dy >= 1:
            continue
        half = (1 - dy) ** (1 / EXPONENT) * r
        draw.line([(r - half, y), (r + half, y)], fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def build_icon(art_path: Path) -> Image.Image:
    art = Image.open(art_path).convert("RGBA").resize((BODY, BODY), Image.LANCZOS)
    mask = squircle_mask(BODY)
    offset = (CANVAS - BODY) // 2

    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste(
        Image.new("RGBA", (BODY, BODY), (0, 0, 0, SHADOW_ALPHA)),
        (offset, offset + SHADOW_OFFSET_Y),
        mask,
    )
    icon = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR))

    body = Image.new("RGBA", (BODY, BODY), (0, 0, 0, 0))
    body.paste(art, (0, 0), mask)
    icon.alpha_composite(body, (offset, offset))
    return icon


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    art_path, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    icon = build_icon(art_path)
    for size in SIZES:
        out = icon if size == CANVAS else icon.resize((size, size), Image.LANCZOS)
        out.save(out_dir / f"app_icon_{size}.png")


if __name__ == "__main__":
    main()
