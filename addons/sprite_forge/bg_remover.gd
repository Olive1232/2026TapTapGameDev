@tool

# Perceptual color distance flood-fill background remover with alpha matting.

const _K: int = 4
const _KMEANS_ITER: int = 12
const _MAT_RADIUS: int = 3

static func remove(image: Image, tolerance: float = 0.18, feather: bool = true) -> Image:
	var img: Image = image.duplicate()
	img.convert(Image.FORMAT_RGBA8)

	var W: int = img.get_width()
	var H: int = img.get_height()
	if W < 2 or H < 2:
		return img

	var bg_centers: Array = _edge_kmeans(img, W, H)

	var removed := PackedByteArray()
	removed.resize(W * H)
	removed.fill(0)

	for ci in range(bg_centers.size()):
		var bg: Color = bg_centers[ci]
		_bfs_fill(img, bg, tolerance, W, H, removed)

	_apply_matting(img, removed, W, H, feather)

	return img

static func _edge_kmeans(img: Image, W: int, H: int) -> Array:
	var samples: Array = []
	var step: int = max(1, min(W, H) / 60)

	for x in range(0, W, step):
		samples.append(img.get_pixel(x, 0))
		samples.append(img.get_pixel(x, H - 1))
	for y in range(0, H, step):
		samples.append(img.get_pixel(0, y))
		samples.append(img.get_pixel(W - 1, y))

	var corners: Array = [
		img.get_pixel(0, 0),
		img.get_pixel(W - 1, 0),
		img.get_pixel(0, H - 1),
		img.get_pixel(W - 1, H - 1)
	]
	for _r in range(8):
		for c in corners:
			samples.append(c)

	if samples.size() == 0:
		return [Color.WHITE]

	var k: int = min(_K, samples.size())
	var centers: Array = []
	for i in range(k):
		var idx: int = (i * samples.size()) / k
		centers.append(samples[idx])

	for _iter in range(_KMEANS_ITER):
		var sums_r: Array = []
		var sums_g: Array = []
		var sums_b: Array = []
		var counts: Array = []
		for i in range(k):
			sums_r.append(0.0)
			sums_g.append(0.0)
			sums_b.append(0.0)
			counts.append(0)

		for sv in samples:
			var s: Color = sv
			var best_ci: int = 0
			var best_d: float = _dist(s, centers[0])
			for ci in range(1, k):
				var d: float = _dist(s, centers[ci])
				if d < best_d:
					best_d = d
					best_ci = ci
			sums_r[best_ci] = sums_r[best_ci] + s.r
			sums_g[best_ci] = sums_g[best_ci] + s.g
			sums_b[best_ci] = sums_b[best_ci] + s.b
			counts[best_ci] = counts[best_ci] + 1

		for ci in range(k):
			var cnt: int = counts[ci]
			if cnt > 0:
				centers[ci] = Color(sums_r[ci] / cnt, sums_g[ci] / cnt, sums_b[ci] / cnt, 1.0)

	return centers

static func _bfs_fill(img: Image, bg: Color, tol: float,
		W: int, H: int, removed: PackedByteArray) -> void:
	var visited: PackedByteArray = removed.duplicate()

	var queue := PackedInt32Array()
	var head: int = 0

	for x in range(W):
		_try_seed(queue, visited, img, x, 0,     bg, tol, W)
		_try_seed(queue, visited, img, x, H - 1, bg, tol, W)
	for y in range(1, H - 1):
		_try_seed(queue, visited, img, 0,     y, bg, tol, W)
		_try_seed(queue, visited, img, W - 1, y, bg, tol, W)

	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		removed[idx] = 1

		var px: int = idx % W
		var py: int = idx / W

		var nx: int = px - 1
		if nx >= 0:
			_try_seed(queue, visited, img, nx, py, bg, tol, W)
		nx = px + 1
		if nx < W:
			_try_seed(queue, visited, img, nx, py, bg, tol, W)
		var ny: int = py - 1
		if ny >= 0:
			_try_seed(queue, visited, img, px, ny, bg, tol, W)
		ny = py + 1
		if ny < H:
			_try_seed(queue, visited, img, px, ny, bg, tol, W)

static func _try_seed(queue: PackedInt32Array, visited: PackedByteArray, img: Image,
		x: int, y: int, bg: Color, tol: float, W: int) -> void:
	var idx: int = y * W + x
	if visited[idx] != 0:
		return
	visited[idx] = 1
	var c: Color = img.get_pixel(x, y)
	if c.a < 0.05 or _dist(c, bg) <= tol:
		queue.append(idx)

static func _apply_matting(img: Image, removed: PackedByteArray,
		W: int, H: int, feather: bool) -> void:
	for y in range(H):
		for x in range(W):
			if removed[y * W + x]:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	if not feather:
		return

	var dist_map := PackedFloat32Array()
	dist_map.resize(W * H)
	var BIG: float = float(W + H + 1)

	for y in range(H):
		for x in range(W):
			if img.get_pixel(x, y).a < 0.01:
				dist_map[y * W + x] = 0.0
			else:
				dist_map[y * W + x] = BIG

	for y in range(H):
		for x in range(W):
			var idx: int = y * W + x
			if dist_map[idx] == 0.0:
				continue
			var best: float = dist_map[idx]
			if x > 0:
				var v: float = dist_map[idx - 1] + 1.0
				if v < best:
					best = v
			if y > 0:
				var v: float = dist_map[idx - W] + 1.0
				if v < best:
					best = v
			dist_map[idx] = best

	for y in range(H - 1, -1, -1):
		for x in range(W - 1, -1, -1):
			var idx: int = y * W + x
			if dist_map[idx] == 0.0:
				continue
			var best: float = dist_map[idx]
			if x < W - 1:
				var v: float = dist_map[idx + 1] + 1.0
				if v < best:
					best = v
			if y < H - 1:
				var v: float = dist_map[idx + W] + 1.0
				if v < best:
					best = v
			dist_map[idx] = best

	var snapshot: Image = img.duplicate()
	for y in range(H):
		for x in range(W):
			var c: Color = snapshot.get_pixel(x, y)
			if c.a < 0.01:
				continue
			var d: float = dist_map[y * W + x]
			if d > _MAT_RADIUS:
				continue
			var t: float = d / float(_MAT_RADIUS)
			var smooth_t: float = t * t * (3.0 - 2.0 * t)
			img.set_pixel(x, y, Color(c.r, c.g, c.b, c.a * smooth_t))

static func _dist(a: Color, b: Color) -> float:
	var dr: float = a.r - b.r
	var dg: float = a.g - b.g
	var db: float = a.b - b.b
	return sqrt(dr * dr * 0.299 + dg * dg * 0.587 + db * db * 0.114)

static func magic_wand_erase(image: Image, start_x: int, start_y: int, tolerance: float) -> Image:
	var img: Image = image.duplicate()
	img.convert(Image.FORMAT_RGBA8)

	var W: int = img.get_width()
	var H: int = img.get_height()
	if W < 2 or H < 2:
		return img
	if start_x < 0 or start_y < 0 or start_x >= W or start_y >= H:
		return img
		
	var bg: Color = img.get_pixel(start_x, start_y)
	if bg.a < 0.05:
		return img

	var removed := PackedByteArray()
	removed.resize(W * H)
	removed.fill(0)
	
	var visited := PackedByteArray()
	visited.resize(W * H)
	visited.fill(0)

	var queue := PackedInt32Array()
	var head: int = 0
	
	_try_seed(queue, visited, img, start_x, start_y, bg, tolerance, W)

	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		removed[idx] = 1

		var px: int = idx % W
		var py: int = idx / W

		var nx: int = px - 1
		if nx >= 0: _try_seed(queue, visited, img, nx, py, bg, tolerance, W)
		nx = px + 1
		if nx < W: _try_seed(queue, visited, img, nx, py, bg, tolerance, W)
		var ny: int = py - 1
		if ny >= 0: _try_seed(queue, visited, img, px, ny, bg, tolerance, W)
		ny = py + 1
		if ny < H: _try_seed(queue, visited, img, px, ny, bg, tolerance, W)

	for y in range(H):
		for x in range(W):
			if removed[y * W + x] != 0:
				img.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))

	return img

static func brush_erase(image: Image, center_x: int, center_y: int, radius: float, is_square: bool = false) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var W: int = image.get_width()
	var H: int = image.get_height()
	var r_ceil := int(ceil(radius))

	for y in range(max(0, center_y - r_ceil), min(H, center_y + r_ceil + 1)):
		for x in range(max(0, center_x - r_ceil), min(W, center_x + r_ceil + 1)):
			if is_square:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			else:
				var dx := x - center_x
				var dy := y - center_y
				if float(dx*dx + dy*dy) <= radius*radius:
					image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
	return image

static func brush_paint(image: Image, center_x: int, center_y: int, radius: float, color: Color, is_square: bool = false, order_behind: bool = false) -> Image:
	image.convert(Image.FORMAT_RGBA8)
	var W: int = image.get_width()
	var H: int = image.get_height()
	var r_ceil := int(ceil(radius))

	for y in range(max(0, center_y - r_ceil), min(H, center_y + r_ceil + 1)):
		for x in range(max(0, center_x - r_ceil), min(W, center_x + r_ceil + 1)):
			var apply_pixel := is_square
			if not apply_pixel:
				var dx := x - center_x
				var dy := y - center_y
				if float(dx*dx + dy*dy) <= radius*radius:
					apply_pixel = true
			if apply_pixel:
				if order_behind:
					var dst_color := image.get_pixel(x, y)
					var blended_color := color.blend(dst_color)
					image.set_pixel(x, y, blended_color)
				else:
					if color.a < 1.0:
						var dst_color := image.get_pixel(x, y)
						var blended_color := dst_color.blend(color)
						image.set_pixel(x, y, blended_color)
					else:
						image.set_pixel(x, y, color)
	return image

static func paste_frame_transformed(
	base_image: Image,
	frame_image: Image,
	pos: Vector2,
	scale: Vector2,
	rotation: float,
	pivot: Vector2,
	flip_h: bool = false,
	flip_v: bool = false,
	order_behind: bool = false
) -> Image:
	base_image.convert(Image.FORMAT_RGBA8)
	frame_image.convert(Image.FORMAT_RGBA8)
	
	var dst_w := base_image.get_width()
	var dst_h := base_image.get_height()
	var src_w := frame_image.get_width()
	var src_h := frame_image.get_height()
	
	var f_scale := scale
	if flip_h: f_scale.x *= -1.0
	if flip_v: f_scale.y *= -1.0
	
	var xform := Transform2D()
	xform.x = Vector2(cos(rotation), sin(rotation)) * f_scale.x
	xform.y = Vector2(-sin(rotation), cos(rotation)) * f_scale.y
	xform.origin = pos - (xform.x * pivot.x + xform.y * pivot.y)
	
	var inv := xform.affine_inverse()
	
	var corners = [
		xform * Vector2(0, 0),
		xform * Vector2(src_w, 0),
		xform * Vector2(0, src_h),
		xform * Vector2(src_w, src_h)
	]
	var min_x = dst_w
	var max_x = 0
	var min_y = dst_h
	var max_y = 0
	for c in corners:
		min_x = min(min_x, int(floor(c.x)))
		max_x = max(max_x, int(ceil(c.x)))
		min_y = min(min_y, int(floor(c.y)))
		max_y = max(max_y, int(ceil(c.y)))
		
	min_x = clamp(min_x, 0, dst_w - 1)
	max_x = clamp(max_x, 0, dst_w - 1)
	min_y = clamp(min_y, 0, dst_h - 1)
	max_y = clamp(max_y, 0, dst_h - 1)
	
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var src_pos := inv * Vector2(x, y)
			var sx := int(round(src_pos.x))
			var sy := int(round(src_pos.y))
			if sx >= 0 and sx < src_w and sy >= 0 and sy < src_h:
				var src_color := frame_image.get_pixel(sx, sy)
				if src_color.a > 0.0:
					var dst_color := base_image.get_pixel(x, y)
					var blended_color: Color
					if order_behind:
						blended_color = src_color.blend(dst_color)
					else:
						blended_color = dst_color.blend(src_color)
					base_image.set_pixel(x, y, blended_color)
					
	return base_image

static func paste_stamp_transformed(base_image: Image, stamp_image: Image, pos: Vector2, scale: Vector2, rotation: float, pivot: Vector2, order_behind: bool = false) -> Image:
	return paste_frame_transformed(base_image, stamp_image, pos, scale, rotation, pivot, order_behind)

static func magic_wand_recolor(image: Image, start_x: int, start_y: int, new_color: Color, tolerance: float) -> Image:
	var img: Image = image.duplicate()
	img.convert(Image.FORMAT_RGBA8)

	var W: int = img.get_width()
	var H: int = img.get_height()
	if W < 2 or H < 2:
		return img
	if start_x < 0 or start_y < 0 or start_x >= W or start_y >= H:
		return img
		
	var bg: Color = img.get_pixel(start_x, start_y)
	if bg.a < 0.01:
		return img

	var recolored := PackedByteArray()
	recolored.resize(W * H)
	recolored.fill(0)
	
	var visited := PackedByteArray()
	visited.resize(W * H)
	visited.fill(0)

	var queue := PackedInt32Array()
	var head: int = 0
	
	_try_seed(queue, visited, img, start_x, start_y, bg, tolerance, W)

	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		recolored[idx] = 1

		var px: int = idx % W
		var py: int = idx / W

		var nx: int = px - 1
		if nx >= 0: _try_seed(queue, visited, img, nx, py, bg, tolerance, W)
		nx = px + 1
		if nx < W: _try_seed(queue, visited, img, nx, py, bg, tolerance, W)
		var ny: int = py - 1
		if ny >= 0: _try_seed(queue, visited, img, px, ny, bg, tolerance, W)
		ny = py + 1
		if ny < H: _try_seed(queue, visited, img, px, ny, bg, tolerance, W)

	for y in range(H):
		for x in range(W):
			if recolored[y * W + x] != 0:
				var original := img.get_pixel(x, y)
				# Recolor while keeping original pixel's alpha!
				img.set_pixel(x, y, Color(new_color.r, new_color.g, new_color.b, original.a))

	return img

static func paste_stamp(base_image: Image, stamp_image: Image, center_x: int, center_y: int) -> Image:
	base_image.convert(Image.FORMAT_RGBA8)
	stamp_image.convert(Image.FORMAT_RGBA8)
	
	var stamp_w := stamp_image.get_width()
	var stamp_h := stamp_image.get_height()
	
	# Calculate top-left destination position
	var dest_x := center_x - stamp_w / 2
	var dest_y := center_y - stamp_h / 2
	
	# Fast alpha blending blit via C++!
	base_image.blend_rect(stamp_image, Rect2i(0, 0, stamp_w, stamp_h), Vector2i(dest_x, dest_y))
	return base_image
