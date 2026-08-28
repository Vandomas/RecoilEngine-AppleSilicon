function widget:GetInfo()
	return { name="Instancing Probe", desc="rows of 1/2/8 instanced quads", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=1001, enabled=true }
end

local shader
local rows = {}   -- {vao=, n=}

local vsSrc = [[
#version 420
layout (location = 0) in vec2 pos;
layout (location = 1) in vec4 offs;
out vec4 col;
void main() {
	// row A (attribute-driven): y from offs; row B (pure gl_InstanceID): y = -0.2
	float useID = step(0.5, offs.w);   // offs.w==1 -> ID-driven row
	float x = mix(offs.x, -0.28 + float(gl_InstanceID) * 0.14, useID);
	float y = mix(offs.y, 0.1, useID);
	float h = mix(offs.z, float(gl_InstanceID) * 10.0, useID);
	col = vec4(fract(h*0.13+0.1), fract(h*0.37+0.5), fract(h*0.71+0.9), 1.0);
	gl_Position = vec4(pos * 0.035 + vec2(x, y), 0.0, 1.0);
}
]]
local fsSrc = [[
#version 420
in vec4 col;
out vec4 frag;
void main() { frag = col; }
]]

local function makeRow(y, n)
	local vbo = gl.GetVBO(GL.ARRAY_BUFFER, false)
	vbo:Define(4, { { id = 0, name = "pos", size = 2 } })
	vbo:Upload({ -1,-1,  1,-1,  1,1,  -1,1 })
	local ibo = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
	ibo:Define(6)
	ibo:Upload({ 0,1,2, 0,2,3 })
	local inst = gl.GetVBO(GL.ARRAY_BUFFER, false)
	inst:Define(8, { { id = 1, name = "offs", size = 4 } })
	local d = {}
	for i = 0, 7 do
		d[#d+1] = -0.28 + i * 0.14
		d[#d+1] = y
		d[#d+1] = i * 10 + y * 100
		d[#d+1] = 0
	end
	inst:Upload(d)
	local vao = gl.GetVAO()
	vao:AttachVertexBuffer(vbo)
	vao:AttachInstanceBuffer(inst)
	vao:AttachIndexBuffer(ibo)
	rows[#rows+1] = { vao = vao, n = n, keep = {vbo, ibo, inst} }
end

local inited = false
function widget:DrawScreen()
	if not inited then
		inited = true
		shader = gl.CreateShader({ vertex = vsSrc, fragment = fsSrc })
		if not shader then
			Spring.Echo("INSTPROBE: shader FAILED: " .. tostring(gl.GetShaderLog()))
			return
		end
		makeRow(0.80, 1)
		makeRow(0.62, 2)
		makeRow(0.44, 8)
		-- ID-driven row: mark data with w=1
		local r = rows[#rows]
		local idrow_inst = gl.GetVBO(GL.ARRAY_BUFFER, false)
		idrow_inst:Define(8, { { id = 1, name = "offs", size = 4 } })
		local dd = {}
		for i = 0, 7 do dd[#dd+1]=0 dd[#dd+1]=0 dd[#dd+1]=0 dd[#dd+1]=1 end
		idrow_inst:Upload(dd)
		local vbo2 = gl.GetVBO(GL.ARRAY_BUFFER, false)
		vbo2:Define(4, { { id = 0, name = "pos", size = 2 } })
		vbo2:Upload({ -1,-1, 1,-1, 1,1, -1,1 })
		local ibo2 = gl.GetVBO(GL.ELEMENT_ARRAY_BUFFER, false)
		ibo2:Define(6)
		ibo2:Upload({ 0,1,2, 0,2,3 })
		local vao2 = gl.GetVAO()
		vao2:AttachVertexBuffer(vbo2)
		vao2:AttachInstanceBuffer(idrow_inst)
		vao2:AttachIndexBuffer(ibo2)
		rows[#rows+1] = { vao = vao2, n = 8, keep = {vbo2, ibo2, idrow_inst} }
		Spring.Echo("INSTPROBE: rows ready")
	end
	if not shader then return end
	gl.UseShader(shader)
	for _, r in ipairs(rows) do
		r.vao:DrawElements(GL.TRIANGLES, 6, 0, r.n)
	end
	gl.UseShader(0)
end
