function widget:GetInfo()
	return { name="VAO Fan Test", desc="same wedge through an indexed vao fan, to isolate which draw path breaks",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=-99998, enabled=true }
end

local vao, vbo, ibo, count
local function build()
	local verts, idx = {}, {}
	local n = 12
	verts[1], verts[2] = 0, 0
	for i = 0, n do
		local a = (i / n) * math.pi * 1.5
		verts[#verts + 1] = math.cos(a) * 50
		verts[#verts + 1] = math.sin(a) * 50
	end
	for i = 0, n + 1 do idx[#idx + 1] = i end
	vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	vbo:Define(#verts / 2, { { id = 0, name = "pos", size = 2 } })
	vbo:Upload(verts)
	ibo = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
	ibo:Define(#idx)
	ibo:Upload(idx)
	vao = gl.GetVAO()
	vao:AttachVertexBuffer(vbo)
	vao:AttachIndexBuffer(ibo)
	count = #idx
end

function widget:DrawScreen()
	if not vao then build() end
	gl.PushMatrix()
	gl.Translate(700, 200, 0)
	gl.Color(0.2, 0.8, 0.3, 0.9)
	vao:DrawElements(GL.TRIANGLE_FAN, count)
	gl.Color(1, 1, 1, 1)
	gl.PopMatrix()
	gl.Text("green wedge = indexed VAO fan", 620, 120, 18, "o")
end
