from __future__ import annotations

import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT / "assets"
ORIGINAL_ROOT = SOURCE_ROOT / "_source_originals"
OUTPUT_ROOT = SOURCE_ROOT / "mechanisms"
MAX_SPRITE_EDGE = 512
SPRITE_PADDING = 16
ALPHA_THRESHOLD = 32


def load_rgba(filename: str) -> Image.Image:
    return Image.open(ORIGINAL_ROOT / filename).convert("RGBA")


def trim_alpha(image: Image.Image, padding: int = SPRITE_PADDING) -> Image.Image:
    alpha = image.getchannel("A")
    bbox = alpha.point(lambda value: 255 if value > ALPHA_THRESHOLD else 0).getbbox()
    if bbox is None:
        raise ValueError("Asset has no visible pixels")
    cropped = image.crop(bbox)
    canvas = Image.new(
        "RGBA",
        (cropped.width + padding * 2, cropped.height + padding * 2),
        (0, 0, 0, 0),
    )
    canvas.alpha_composite(cropped, (padding, padding))
    return canvas


def fit_sprite(image: Image.Image, max_edge: int = MAX_SPRITE_EDGE) -> Image.Image:
    image = trim_alpha(image)
    longest = max(image.size)
    if longest <= max_edge:
        return image
    scale = max_edge / float(longest)
    size = (
        max(1, round(image.width * scale)),
        max(1, round(image.height * scale)),
    )
    return image.resize(size, Image.Resampling.LANCZOS)


def isolate_component(image: Image.Image, target: tuple[int, int]) -> Image.Image:
    rgba = np.asarray(image).copy()
    mask = (rgba[:, :, 3] > ALPHA_THRESHOLD).astype(np.uint8)
    count, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, 8)
    candidates: list[tuple[float, int]] = []
    for label in range(1, count):
        area = int(stats[label, cv2.CC_STAT_AREA])
        if area < 1000:
            continue
        center_x, center_y = centroids[label]
        distance = (center_x - target[0]) ** 2 + (center_y - target[1]) ** 2
        candidates.append((distance, label))
    if not candidates:
        raise ValueError(f"No connected component found near {target}")
    selected = min(candidates)[1]
    rgba[labels != selected] = 0
    return Image.fromarray(rgba, "RGBA")


def crop_region(image: Image.Image, region: tuple[int, int, int, int]) -> Image.Image:
    return image.crop(region)


def resize_texture(image: Image.Image, max_edge: int) -> Image.Image:
    longest = max(image.size)
    if longest <= max_edge:
        return image
    scale = max_edge / float(longest)
    return image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.LANCZOS,
    )


def save_asset(
    image: Image.Image,
    relative_path: str,
    source: str,
    role: str,
    manifest: list[dict[str, object]],
    *,
    sprite: bool = True,
    texture_max_edge: int = 1024,
) -> None:
    output = OUTPUT_ROOT / relative_path
    output.parent.mkdir(parents=True, exist_ok=True)
    processed = fit_sprite(image) if sprite else resize_texture(image, texture_max_edge)
    processed.save(output, "PNG", optimize=True)
    manifest.append(
        {
            "file": output.relative_to(SOURCE_ROOT).as_posix(),
            "source": source,
            "role": role,
            "width": processed.width,
            "height": processed.height,
            "sprite": sprite,
        }
    )


def build_preview(manifest: list[dict[str, object]]) -> None:
    entries = [entry for entry in manifest if bool(entry["sprite"])]
    columns = 4
    cell_width = 260
    cell_height = 220
    rows = (len(entries) + columns - 1) // columns
    preview = Image.new(
        "RGB",
        (columns * cell_width, rows * cell_height),
        (24, 27, 34),
    )
    draw = ImageDraw.Draw(preview)
    font = ImageFont.load_default()
    for index, entry in enumerate(entries):
        row, column = divmod(index, columns)
        left = column * cell_width
        top = row * cell_height
        for y in range(top + 8, top + 178, 16):
            for x in range(left + 8, left + cell_width - 8, 16):
                color = (43, 47, 57) if ((x // 16 + y // 16) % 2 == 0) else (55, 60, 72)
                draw.rectangle((x, y, x + 15, y + 15), fill=color)
        asset = Image.open(SOURCE_ROOT / str(entry["file"])).convert("RGBA")
        asset.thumbnail((cell_width - 28, 156), Image.Resampling.LANCZOS)
        asset_x = left + (cell_width - asset.width) // 2
        asset_y = top + 12 + (156 - asset.height) // 2
        preview.paste(asset, (asset_x, asset_y), asset)
        label = Path(str(entry["file"])).name
        draw.text((left + 10, top + 184), label, font=font, fill=(230, 235, 245))
        draw.text(
            (left + 10, top + 200),
            f"{entry['width']}x{entry['height']}",
            font=font,
            fill=(155, 165, 185),
        )
    preview_path = OUTPUT_ROOT / "_source" / "_preview.png"
    preview_path.parent.mkdir(parents=True, exist_ok=True)
    preview.save(preview_path, "PNG", optimize=True)


def main() -> None:
    manifest: list[dict[str, object]] = []

    optics_source = "微信图片_20261026215723_148_4.png"
    optics = load_rgba(optics_source)
    optics_components = {
        "optics/convex_lens.png": ((274, 358), "凸透镜"),
        "optics/concave_lens.png": ((813, 358), "凹透镜"),
        "optics/triangular_prism.png": ((1358, 380), "三棱镜"),
        "optics/glass_plate.png": ((1933, 362), "玻璃板"),
    }
    for relative_path, (target, role) in optics_components.items():
        save_asset(
            isolate_component(optics, target),
            relative_path,
            optics_source,
            role,
            manifest,
        )

    atlas_source = "微信图片_20261026141344_43_4.png"
    atlas = load_rgba(atlas_source)
    atlas_components = {
        "props/mirror_panel.png": ((1364, 222), "镜面板"),
        "ice/glacier_cluster.png": ((198, 601), "冰川簇"),
        "props/stone_a.png": ((580, 615), "石块 A"),
        "props/stone_b.png": ((988, 609), "石块 B"),
        "props/stone_c.png": ((1359, 603), "石块 C"),
        "terrain/dark_bar.png": ((1277, 899), "深色长条平台"),
    }
    for relative_path, (target, role) in atlas_components.items():
        save_asset(
            isolate_component(atlas, target),
            relative_path,
            atlas_source,
            role,
            manifest,
        )

    cleaned_mirror_source = OUTPUT_ROOT / "_source" / "mirror_panel_clean_source.png"
    if cleaned_mirror_source.exists():
        save_asset(
            Image.open(cleaned_mirror_source).convert("RGBA"),
            "props/mirror_panel_clean.png",
            cleaned_mirror_source.relative_to(SOURCE_ROOT).as_posix(),
            "镜面板（透明边缘清理版，推荐）",
            manifest,
        )

    atlas_regions = {
        "switches/ring_neutral.png": ((64, 786, 286, 996), "中性圆环"),
        "switches/ring_cyan.png": ((294, 786, 516, 996), "青色圆环"),
        "switches/ring_empty.png": ((548, 786, 768, 996), "空心圆环"),
        "switches/ring_orange.png": ((814, 786, 1020, 996), "橙色圆环"),
    }
    for relative_path, (region, role) in atlas_regions.items():
        save_asset(
            crop_region(atlas, region),
            relative_path,
            atlas_source,
            role,
            manifest,
        )

    individual_sprites = {
        "微信图片_20261026141344_50_4.png": (
            "switches/disc_orange.png",
            "橙色圆盘",
        ),
        "微信图片_20261026141344_51_4.png": (
            "switches/disc_cyan.png",
            "青色圆盘",
        ),
        "微信图片_20261026141344_53_4.png": (
            "terrain/prism_wedge.png",
            "紫色三角坡面",
        ),
        "微信图片_20261026141344_54_4.png": (
            "terrain/dark_slope_long.png",
            "深色长斜坡",
        ),
        "微信图片_20261026141344_55_4.png": (
            "terrain/dark_slope_short.png",
            "深色短斜坡",
        ),
        "微信图片_20261026141344_56_4.png": (
            "ice/ice_crystal_tall.png",
            "高冰晶",
        ),
        "微信图片_20261026141344_57_4.png": (
            "ice/ice_crystal_wide_a.png",
            "宽冰晶 A",
        ),
        "微信图片_20261026141344_58_4.png": (
            "ice/ice_crystal_wide_b.png",
            "宽冰晶 B",
        ),
        "微信图片_20261026141344_59_4.png": (
            "ice/ice_crystal_peak.png",
            "山峰冰晶",
        ),
    }
    for source, (relative_path, role) in individual_sprites.items():
        save_asset(load_rgba(source), relative_path, source, role, manifest)

    texture_sources = {
        "微信图片_20261026141344_46_4.png": (
            "textures/dark_stone.png",
            "深色石材纹理",
            512,
        ),
        "微信图片_20261026141344_47_4.png": (
            "textures/light_crystal.png",
            "浅色晶体纹理",
            512,
        ),
        "微信图片_20261026141344_49_4.png": (
            "textures/light_background.png",
            "浅色背景纹理",
            1024,
        ),
    }
    for source, (relative_path, role, max_edge) in texture_sources.items():
        save_asset(
            load_rgba(source),
            relative_path,
            source,
            role,
            manifest,
            sprite=False,
            texture_max_edge=max_edge,
        )

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    with (OUTPUT_ROOT / "manifest.json").open("w", encoding="utf-8") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write("\n")
    build_preview(manifest)
    print(f"Generated {len(manifest)} assets in {OUTPUT_ROOT}")


if __name__ == "__main__":
    main()
