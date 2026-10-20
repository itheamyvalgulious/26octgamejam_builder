extends Control

var routes: Array = []

func _draw() -> void:
	for x in range(24, int(size.x), 32):
		for y in range(24, int(size.y), 32):
			draw_circle(Vector2(x, y), 1.0, Color("4e9ac2"))
	for route in routes:
		var a: Vector2 = route[0]
		var b: Vector2 = route[1]
		if route.size() > 3 and route[3] != 0:
			var bend := Vector2(150 * int(route[3]), 0)
			var points := PackedVector2Array()
			for step in range(33):
				points.append(a.bezier_interpolate(a + bend, b + bend, b, step / 32.0))
			draw_polyline(points, Color("235e83"), 4, true)
			continue
		if route.size() > 2 and route[2]: draw_dashed_line(a, b, Color("725328"), 3, 9)
		else: draw_line(a, b, Color("235e83"), 4, true)
