@tool

## BFS-based sprite auto-slicer.
## Uses PackedInt32Array queues and bulk raw pixel access for maximum throughput.

static func slice(image: Image, alpha_threshold: float = 0.1, min_size: Vector2i = Vector2i(4, 4)) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not image:
		return rects

	var width: int  = image.get_width()
	var height: int = image.get_height()

	# visited tracks both transparent (marked inline) and flood-filled pixels
	var visited := PackedByteArray()
	visited.resize(width * height)
	# PackedByteArray.resize() zero-inits — no need for fill(0)

	# Raw pixel bytes: FORMAT_RGBA8 = 4 bytes per pixel; alpha is at offset 3
	var conv_img := image
	if image.get_format() != Image.FORMAT_RGBA8:
		conv_img = image.duplicate()
		conv_img.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = conv_img.get_data()

	for y in range(height):
		for x in range(width):
			var idx: int = y * width + x
			if visited[idx] != 0:
				continue
			# alpha is at byte index idx*4 + 3
			var alpha: int = raw[idx * 4 + 3]
			if float(alpha) / 255.0 > alpha_threshold:
				var bounds: Rect2 = _flood_fill(raw, x, y, width, height, visited, alpha_threshold)
				if bounds.size.x >= min_size.x and bounds.size.y >= min_size.y:
					rects.append(bounds)
			else:
				visited[idx] = 1

	return rects

## BFS flood-fill using PackedInt32Array queue (no heap Vector2i allocations).
## Pre-checks neighbor alpha before enqueuing to keep the queue small.
static func _flood_fill(raw: PackedByteArray, start_x: int, start_y: int, width: int, height: int, visited: PackedByteArray, alpha_threshold: float) -> Rect2:
	var queue := PackedInt32Array()
	var start_flat: int = start_y * width + start_x
	visited[start_flat] = 1
	queue.append(start_flat)

	var min_x: int = start_x; var max_x: int = start_x
	var min_y: int = start_y; var max_y: int = start_y
	var alpha_byte := int(alpha_threshold * 255.0)

	var head: int = 0
	while head < queue.size():
		var flat: int = queue[head]
		head += 1

		var x: int = flat % width
		var y: int = flat / width

		# Only pixels above threshold are enqueued — bounds update is always valid
		if x < min_x: min_x = x
		if x > max_x: max_x = x
		if y < min_y: min_y = y
		if y > max_y: max_y = y

		var n_flat: int
		var n_byte: int

		# Left
		if x > 0:
			n_flat = flat - 1
			if visited[n_flat] == 0:
				visited[n_flat] = 1
				n_byte = n_flat * 4 + 3
				if raw[n_byte] > alpha_byte:
					queue.append(n_flat)

		# Right
		if x < width - 1:
			n_flat = flat + 1
			if visited[n_flat] == 0:
				visited[n_flat] = 1
				n_byte = n_flat * 4 + 3
				if raw[n_byte] > alpha_byte:
					queue.append(n_flat)

		# Up
		if y > 0:
			n_flat = flat - width
			if visited[n_flat] == 0:
				visited[n_flat] = 1
				n_byte = n_flat * 4 + 3
				if raw[n_byte] > alpha_byte:
					queue.append(n_flat)

		# Down
		if y < height - 1:
			n_flat = flat + width
			if visited[n_flat] == 0:
				visited[n_flat] = 1
				n_byte = n_flat * 4 + 3
				if raw[n_byte] > alpha_byte:
					queue.append(n_flat)

	return Rect2(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func slice_grid(image: Image, cell_w: int, cell_h: int, off_x: int, off_y: int, sep_x: int, sep_y: int, keep_empty: bool = false, alpha_threshold: float = 0.05) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not image:
		return rects

	var img_w: int = image.get_width()
	var img_h: int = image.get_height()

	# Pre-convert once for bulk alpha checks
	var conv_img := image
	if image.get_format() != Image.FORMAT_RGBA8:
		conv_img = image.duplicate()
		conv_img.convert(Image.FORMAT_RGBA8)
	var raw: PackedByteArray = conv_img.get_data()
	var alpha_byte := int(alpha_threshold * 255.0)

	for y in range(off_y, img_h - cell_h + 1, cell_h + sep_y):
		for x in range(off_x, img_w - cell_w + 1, cell_w + sep_x):
			if keep_empty or not _is_region_transparent_raw(raw, x, y, cell_w, cell_h, img_w, img_h, alpha_byte):
				rects.append(Rect2(x, y, cell_w, cell_h))

	return rects

## Fast raw-byte transparency check — avoids per-pixel get_pixel() calls.
static func _is_region_transparent_raw(raw: PackedByteArray, rx: int, ry: int, rw: int, rh: int, img_w: int, img_h: int, alpha_byte: int) -> bool:
	var x_end: int = mini(rx + rw, img_w)
	var y_end: int = mini(ry + rh, img_h)
	for py in range(ry, y_end):
		var row_base: int = py * img_w
		for px in range(rx, x_end):
			# Alpha byte is at (row_base + px) * 4 + 3
			if raw[(row_base + px) * 4 + 3] > alpha_byte:
				return false
	return true
