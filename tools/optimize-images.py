"""Generate web-sized derivatives of the site's source images.

The original headshot is 4000x4015 and ~20 MB; it was being shipped whole to
render a ~300 px avatar, three times over. This produces WebP (primary) and
JPEG (fallback) derivatives in assets/ at sizes that actually match how the
images are displayed.

Originals are kept in _originals/ so the derivatives can be regenerated. The
leading underscore matters: Quarto ignores files and directories beginning
with "_", so the 20 MB source never gets copied into the published site.
Run from the repo root:

    python tools/optimize-images.py
"""

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ORIGINALS = ROOT / "_originals"
ASSETS = ROOT / "assets"

# (original filename, output stem, max width in px)
# 800 px covers a ~400 px display slot at 2x; 1600 px likewise for the banner.
TARGETS = [
    ("mathieu.png", "mathieu", 800),
    ("media.png", "media", 1600),
]

WEBP_QUALITY = 82
JPEG_QUALITY = 85


def optimize(source: Path, stem: str, max_width: int) -> None:
    with Image.open(source) as img:
        original_size = source.stat().st_size
        img = img.convert("RGB")

        if img.width > max_width:
            height = round(img.height * max_width / img.width)
            img = img.resize((max_width, height), Image.LANCZOS)

        webp = ASSETS / f"{stem}.webp"
        jpg = ASSETS / f"{stem}.jpg"

        img.save(webp, "WEBP", quality=WEBP_QUALITY, method=6)
        img.save(jpg, "JPEG", quality=JPEG_QUALITY, optimize=True, progressive=True)

        print(
            f"{source.name}: {original_size / 1_048_576:.1f} MB "
            f"-> {stem}.webp {webp.stat().st_size / 1024:.0f} KB, "
            f"{stem}.jpg {jpg.stat().st_size / 1024:.0f} KB "
            f"({img.width}x{img.height})"
        )


def main() -> None:
    ASSETS.mkdir(parents=True, exist_ok=True)
    for filename, stem, max_width in TARGETS:
        source = ORIGINALS / filename
        if not source.exists():
            print(f"SKIP {filename}: not found in {ORIGINALS}")
            continue
        optimize(source, stem, max_width)


if __name__ == "__main__":
    main()
