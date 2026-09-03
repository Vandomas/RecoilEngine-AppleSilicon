function widget:GetInfo()
	return { name="Cam Compare", desc="pause at a fixed sim frame and shoot a fixed set of camera poses",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1008, enabled=true }
end

-- the sim is paused and every pose is spelled out, so two runs of the same demo see the
-- same world from the same places and the images can be compared pixel by pixel
local atFrame = 21000
do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	atFrame = tonumber((f or ""):match("compareAt=(%d+)") or "") or atFrame
end

local poses, step, wait, shot = nil, 0, 0, 0

local function buildPoses()
	-- centre of mass of everything alive, deterministic for a given sim frame
	local sx, sz, n = 0, 0, 0
	for _, uid in ipairs(Spring.GetAllUnits()) do
		local x, _, z = Spring.GetUnitPosition(uid)
		if x then sx, sz, n = sx + x, sz + z, n + 1 end
	end
	local cx, cz = (n > 0) and sx / n or Game.mapSizeX * 0.5, (n > 0) and sz / n or Game.mapSizeZ * 0.5
	Spring.Echo(string.format("CAMCMP centre %d,%d units=%d", cx, cz, n))
	return {
		{ "wide",     cx, 2600, cz + 900,  -1.05 },
		{ "low",      cx,  700, cz + 420,  -0.75 },
		{ "top",      cx, 3200, cz +   1,  -1.57 },
		{ "close",    cx,  420, cz + 260,  -0.95 },
		{ "sideeast", cx + 900, 900, cz + 300, -0.85 },
		{ "far",      cx, 5200, cz + 1800, -1.10 },
	}
end

function widget:Update()
	if Spring.GetGameFrame() < atFrame then return end
	if not poses then
		Spring.SendCommands("pause 1")
		poses = buildPoses()
		wait = 30
		return
	end
	if wait > 0 then wait = wait - 1; return end

	if shot == 1 then
		Spring.SendCommands("screenshot png")
		Spring.Echo(string.format("CAMCMP shot %d %s", step, poses[step][1]))
		shot, wait = 0, 25
		return
	end

	step = step + 1
	if step > #poses then Spring.Echo("CAMCMP done"); Spring.SendCommands("quitforce"); return end
	local p = poses[step]
	Spring.SetCameraState({ mode = 2, px = p[2], py = p[3], pz = p[4], rx = p[5], ry = 0, height = p[3] }, 0)
	shot, wait = 1, 25
end
