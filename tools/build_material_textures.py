from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter, ImageOps, ImageStat


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = PROJECT_ROOT / "assets" / "materials" / "_source"
TEXTURE_DIR = PROJECT_ROOT / "assets" / "materials" / "textures"
SOURCE_SIZE = 256
OUTPUT_SIZE = SOURCE_SIZE * 2


def _center_square(image: Image.Image) -> Image.Image:
    width, height = image.size
    size = min(width, height)
    left = (width - size) // 2
    top = (height - size) // 2
    return image.crop((left, top, left + size, top + size))


def _prepare_source(path: Path, contrast: float, saturation: float) -> Image.Image:
    with Image.open(path) as image:
        prepared = _center_square(image.convert("RGB"))
        prepared = prepared.resize((SOURCE_SIZE, SOURCE_SIZE), Image.Resampling.LANCZOS)
    prepared = ImageEnhance.Contrast(prepared).enhance(contrast)
    prepared = ImageEnhance.Color(prepared).enhance(saturation)
    return prepared.filter(ImageFilter.GaussianBlur(radius=0.35))


def _prepare_detail_map(path: Path, contrast: float, blur_radius: float) -> Image.Image:
    with Image.open(path) as image:
        prepared = _center_square(image.convert("RGB"))
        prepared = prepared.resize((SOURCE_SIZE, SOURCE_SIZE), Image.Resampling.LANCZOS)
    grayscale = ImageOps.grayscale(prepared)
    grayscale = ImageEnhance.Contrast(grayscale).enhance(contrast)
    grayscale = grayscale.filter(ImageFilter.GaussianBlur(radius=blur_radius))
    mean_value = ImageStat.Stat(grayscale).mean[0]
    offset = int(round(128.0 - mean_value))
    grayscale = grayscale.point(lambda value: max(0, min(255, value + offset)))
    return Image.merge("RGB", (grayscale, grayscale, grayscale))


def _make_mirror_tile(source: Image.Image) -> Image.Image:
    tile = Image.new("RGB", (OUTPUT_SIZE, OUTPUT_SIZE))
    tile.paste(source, (0, 0))
    tile.paste(ImageOps.mirror(source), (SOURCE_SIZE, 0))
    tile.paste(ImageOps.flip(source), (0, SOURCE_SIZE))
    tile.paste(ImageOps.flip(ImageOps.mirror(source)), (SOURCE_SIZE, SOURCE_SIZE))
    return tile


def _save_texture(source_name: str, output_name: str, contrast: float, saturation: float) -> None:
    source = _prepare_source(SOURCE_DIR / source_name, contrast, saturation)
    texture = _make_mirror_tile(source)
    output_path = TEXTURE_DIR / output_name
    texture.save(output_path, optimize=True)
    print(f"wrote {output_path.relative_to(PROJECT_ROOT)} ({texture.width}x{texture.height})")


def _save_detail_map(source_name: str, output_name: str, contrast: float, blur_radius: float) -> None:
    source = _prepare_detail_map(SOURCE_DIR / source_name, contrast, blur_radius)
    texture = _make_mirror_tile(source)
    output_path = TEXTURE_DIR / output_name
    texture.save(output_path, optimize=True)
    print(f"wrote {output_path.relative_to(PROJECT_ROOT)} ({texture.width}x{texture.height})")


def _save_preview() -> None:
    names = ("stone_matte_detail.png", "ice_frost_detail.png")
    preview = Image.new("RGB", (1024, 512), "#202126")
    for index, name in enumerate(names):
        with Image.open(TEXTURE_DIR / name) as image:
            tile = image.convert("RGB").resize((256, 256), Image.Resampling.LANCZOS)
        repeated = Image.new("RGB", (512, 512))
        for x in (0, 256):
            for y in (0, 256):
                repeated.paste(tile, (x, y))
        preview.paste(repeated, (index * 512, 0))
    preview.save(SOURCE_DIR / "material_tiles_preview.png", optimize=True)


def main() -> None:
    TEXTURE_DIR.mkdir(parents=True, exist_ok=True)
    _save_detail_map("stone_matte_imagegen.png", "stone_matte_detail.png", 0.52, 1.2)
    _save_detail_map("ice_frost_imagegen.png", "ice_frost_detail.png", 0.36, 1.6)
    _save_preview()


if __name__ == "__main__":
    main()
