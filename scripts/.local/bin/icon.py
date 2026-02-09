#!/usr/bin/env python3
import argparse
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont

DEFAULT_SIZES = (16, 32, 64, 128, 256, 512)
FONT_SIZE_RATIO = 0.6

THEMES = {
    "default": {
        "bg": "#1a1a2e",
        "fg": "#eaeaea",
        "accent": "#4a90d9",
    },
    "ocean": {
        "bg": "#0f3460",
        "fg": "#e8f1f5",
        "accent": "#00b4d8",
    },
    "forest": {
        "bg": "#1b4332",
        "fg": "#d8f3dc",
        "accent": "#52b788",
    },
    "ember": {
        "bg": "#2d1b1b",
        "fg": "#fef3e2",
        "accent": "#e85d04",
    },
    "minimal": {
        "bg": "#ffffff",
        "fg": "#1a1a1a",
        "accent": "#666666",
    },
    "dark": {
        "bg": "#0d0d0d",
        "fg": "#f5f5f5",
        "accent": "#404040",
    },
}

FONT_CANDIDATES = [
    # macOS - prefer SF Pro for clean modern look
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/SFNSMono.ttf",
    "/Library/Fonts/SF-Pro-Display-Bold.otf",
    "/System/Library/Fonts/Helvetica.ttc",
    # Linux
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
]

_font_cache = {}


def hex_to_rgb(hex_color: str) -> tuple[int, int, int]:
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def load_font(size: int) -> ImageFont.FreeTypeFont:
    if size in _font_cache:
        return _font_cache[size]

    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                font = ImageFont.truetype(path, size)
                _font_cache[size] = font
                return font
            except OSError:
                continue

    print("Warning: no system font found, using PIL default")
    font = ImageFont.load_default()
    _font_cache[size] = font
    return font


def draw_rounded_rect(
    draw: ImageDraw.Draw,
    xy: tuple[int, int, int, int],
    radius: int,
    fill: str,
) -> None:
    x0, y0, x1, y1 = xy
    draw.rounded_rectangle(xy, radius=radius, fill=fill)


def render_icon(
    text: str,
    size: int,
    bg: str,
    fg: str,
    accent: str,
    out: Path,
    rounded: bool = True,
    shadow: bool = True,
) -> None:
    scale = 4
    render_size = size * scale
    radius = int(render_size * 0.18) if rounded else 0

    img = Image.new("RGBA", (render_size, render_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    draw_rounded_rect(draw, (0, 0, render_size, render_size), radius, bg)

    font_size = int(render_size * FONT_SIZE_RATIO)
    font = load_font(font_size)

    center = render_size // 2

    if shadow and size >= 32:
        shadow_color = (*hex_to_rgb(bg)[:3], 80)
        shadow_offset = max(2, render_size // 64)
        draw.text(
            (center + shadow_offset, center + shadow_offset),
            text,
            font=font,
            fill=shadow_color,
            anchor="mm",
        )

    draw.text((center, center), text, font=font, fill=fg, anchor="mm")

    img = img.resize((size, size), Image.Resampling.LANCZOS)
    img.save(out, "PNG")


def parse_sizes(raw: str) -> Iterable[int]:
    try:
        return tuple(int(x) for x in raw.split(","))
    except ValueError:
        raise argparse.ArgumentTypeError("sizes must be comma-separated integers")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate elegant text-based icons",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s A                     # Generate icons with letter 'A'
  %(prog)s PY --theme ocean      # Python icons with ocean theme
  %(prog)s RS --theme ember      # Rust icons with ember theme
  %(prog)s X --no-rounded        # Square corners
  %(prog)s GO --sizes 64,128     # Only specific sizes
        """,
    )
    parser.add_argument("text", help="1-3 characters to render")
    parser.add_argument(
        "-t", "--theme", default="default", choices=THEMES.keys(), help="Color theme"
    )
    parser.add_argument("--bg", help="Override background color (hex)")
    parser.add_argument("--fg", help="Override foreground color (hex)")
    parser.add_argument(
        "-s", "--sizes", type=parse_sizes, default=DEFAULT_SIZES, help="Icon sizes"
    )
    parser.add_argument("-o", "--out", default="icons", help="Output directory")
    parser.add_argument(
        "--no-rounded", action="store_true", help="Disable rounded corners"
    )
    parser.add_argument("--no-shadow", action="store_true", help="Disable text shadow")

    args = parser.parse_args()

    text = args.text.upper()
    if not (1 <= len(text) <= 3):
        parser.error("text must be 1-3 characters")

    theme = THEMES[args.theme]
    bg = args.bg or theme["bg"]
    fg = args.fg or theme["fg"]
    accent = theme["accent"]

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    for size in args.sizes:
        out = out_dir / f"icon-{size}.png"
        render_icon(
            text,
            size,
            bg,
            fg,
            accent,
            out,
            rounded=not args.no_rounded,
            shadow=not args.no_shadow,
        )

    print(f"Generated {len(list(args.sizes))} icons for '{text}' in {out_dir}/")


if __name__ == "__main__":
    main()
