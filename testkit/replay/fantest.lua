function widget:GetInfo()
	return { name="Fan Test", desc="draw the same wedge as a triangle fan and as a triangle list, side by side",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=-99999, enabled=true }
end

-- the build menu draws its progress pie with gl.Shape(GL.TRIANGLE_FAN, ...) and it comes
-- out wrong here. metal has no fan primitive, so the row drawn as a fan and the row drawn
-- as plain triangles from the same vertices tell us whether the conversion is at fault
local function wedge(w, h, progress)
	local xcen, ycen = w * 0.5, h * 0.5
	local alpha = 360 * progress
	local ar = math.rad(alpha)
	local br = math.pi / 2 - ar
	local list = { { v = { xcen, ycen } }, { v = { xcen, h } } }
	local x = (h - ycen) * math.tan(ar) + xcen
	if alpha < 90 and x < w then
		list[3] = { v = { x, h } }
	else
		list[3] = { v = { w, h } }
		local y = (w - xcen) * math.tan(br) + ycen
		if alpha < 180 and y > 0 then
			list[4] = { v = { w, y } }
		else
			list[4] = { v = { w, 0 } }
			x = (h - ycen) * math.tan(-ar) + xcen
			if alpha < 270 and x > 0 then
				list[5] = { v = { x, 0 } }
			else
				list[5] = { v = { 0, 0 } }
				y = (w - xcen) * math.tan(-br) + ycen
				if alpha < 350 and y < h then
					list[6] = { v = { 0, y } }
				else
					list[6] = { v = { 0, h } }
					list[7] = { v = { (h - ycen) * math.tan(ar) + xcen, h } }
				end
			end
		end
	end
	return list
end

local function asTriangles(list)
	local out = {}
	for i = 2, #list - 1 do
		out[#out + 1] = list[1]
		out[#out + 1] = list[i]
		out[#out + 1] = list[i + 1]
	end
	return out
end

function widget:DrawScreen()
	local size, pad = 110, 14
	local x0, y0 = 60, 300
	-- also draw an indexed fan through a vao, to see whether the broken path is only
	-- the non-indexed one that glBegin/glEnd produces
	for i = 1, 8 do
		local p = i / 9
		local list = wedge(size, size, p)
		for row = 0, 1 do
			gl.PushMatrix()
			gl.Translate(x0 + (i - 1) * (size + pad), y0 + row * (size + pad), 0)
			gl.Color(0.15, 0.15, 0.15, 0.9)
			gl.Rect(0, 0, size, size)
			gl.Color(0.9, 0.5, 0.1, 0.85)
			gl.Translate(size * 0.5, size * 0.5, 0)
			gl.Scale(-1, 1, 1)
			gl.Translate(-size * 0.5, -size * 0.5, 0)
			if row == 1 then
				gl.Shape(GL.TRIANGLE_FAN, list)
			else
				gl.Shape(GL.TRIANGLES, asTriangles(list))
			end
			gl.PopMatrix()
		end
	end
	gl.Color(1, 1, 1, 1)
	gl.Text("top row: TRIANGLE_FAN    bottom row: TRIANGLES", 60, y0 + 2 * 110 + 40, 18, "o")
end
