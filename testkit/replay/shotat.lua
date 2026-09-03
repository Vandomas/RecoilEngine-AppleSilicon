function widget:GetInfo()
	return { name="Shot At", desc="screenshot at fixed sim frames from a fixed camera, for before/after comparison",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1007, enabled=true }
end

-- both the camera pose and the frames are fixed, so two runs of the same demo produce
-- images that only differ where the change under test actually changed something
local frames, idx, armed = {}, 1, false

do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	local list = f and f:match("shotAt=([%d,]+)")
	for n in (list or ""):gmatch("%d+") do frames[#frames + 1] = tonumber(n) end
end

function widget:Update()
	local gf = Spring.GetGameFrame()
	if idx > #frames or gf < frames[idx] then return end
	if not armed then
		armed = true
		local x, z = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
		Spring.SetCameraState({ mode = 2, px = x, py = 1800, pz = z + 600, rx = -1.05, ry = 0, height = 1800 }, 0)
		return
	end
	Spring.SendCommands("screenshot png")
	Spring.Echo(string.format("SHOTAT f=%d idx=%d", gf, idx))
	idx = idx + 1
	armed = false
end
