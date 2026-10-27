# ImageGen provenance

Mode: built-in `imagegen` tool.

The first-pass textures below are retained for provenance but are no longer referenced by the mechanism scenes. The final correction prompts are at the end of this file.

## Dark stone

Use case: stylized-concept

Asset type: seamless tileable 2D game texture

Input images: Image 1: material and palette reference only

Primary request: Create a square seamless dark stone surface texture derived from Image 1 for filling arbitrary Godot 2D polygons.

Style/medium: restrained stylized realism; fine charcoal stone grain with subtle mineral speckles.

Composition/framing: flat orthographic material swatch covering the entire square; uniform detail density; perfectly tileable on all four edges.

Lighting/mood: neutral diffuse lighting baked as little as possible; no directional shadow or highlight.

Color palette: charcoal gray and soft graphite, low saturation.

Constraints: no object silhouette, no border, no cracks forming symbols, no central focal patch, no perspective, no bevel, no text, no watermark; avoid high-contrast blobs; edges must wrap seamlessly.

## Light crystal

Use case: stylized-concept

Asset type: seamless tileable 2D game texture

Input images: Image 1: material and palette reference only

Primary request: Create a square seamless pale crystal material texture derived from Image 1 for filling arbitrary Godot 2D lens and ice polygons.

Style/medium: restrained translucent mineral surface; very subtle fine crystalline grain and soft small facets, suitable beneath adjustable color tint.

Composition/framing: flat orthographic material swatch covering the entire square; uniform detail density; perfectly tileable on all four edges.

Lighting/mood: neutral diffuse lighting; no directional highlight, shadow, depth, or object lighting.

Color palette: near-neutral pearl white, cool light gray and faint ice blue; low saturation and low contrast so shader tint remains predictable.

Constraints: no large triangles, no recognizable shard silhouette, no center point, no focal composition, no border, no perspective, no text, no watermark; avoid high-contrast patches and repeated symbols; edges must wrap seamlessly.

## Final correction: matte stone detail

Use case: stylized-concept

Asset type: seamless tileable 2D game material detail map

Input images: Image 1 is a palette and surface-character reference only.

Primary request: Create a restrained matte charcoal stone detail map for large flat Godot 2D walls and blocks. It must read as broad, soft, low-frequency mineral variation, not as a photograph or noisy wallpaper.

Style/medium: hand-painted stylized game material; diffuse-only surface information.

Composition/framing: flat orthographic square swatch filling the canvas; uniform detail density; seamless on all four edges; no focal point.

Lighting/mood: neutral diffuse lighting with no directional illumination or cast shadow.

Color palette: neutral middle-gray detail values with subtle charcoal variation; low contrast so code tint remains dominant.

Constraints: no object silhouette, no border, no bevel, no cracks, no symbols, no center patch, no perspective, no text, no watermark.

Avoid: fine grain, salt-and-pepper speckles, photographic grit, repetitive cells, strong veins, high contrast blobs.

## Final correction: pale ice frost detail

Use case: stylized-concept

Asset type: seamless tileable 2D game material detail map

Input images: Image 1 is a color and frost-character reference only.

Primary request: Create an extremely subtle pale ice frost detail map for a Godot 2D glacier fill. The map should provide only soft cloudy frost and a few broad translucent mineral variations; the glacier silhouette and facet lines will be drawn separately in code.

Style/medium: restrained hand-painted stylized game material; diffuse detail only.

Composition/framing: flat orthographic square swatch filling the canvas; uniform detail density; seamless on all four edges; no focal point.

Lighting/mood: neutral diffuse lighting, nearly flat.

Color palette: near-white, very pale blue-gray, faint warm pearl; very low saturation and low contrast so tint controls remain dominant.

Constraints: no object silhouette, no border, no bevel, no large polygons, no triangle network, no cracks, no center point, no perspective, no text, no watermark.

Avoid: visible low-poly pattern, shards, snowflakes, speckles, strong veins, high-contrast patches, photographic ice.
