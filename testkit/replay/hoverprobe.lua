function widget:GetInfo()
	return { name="Hover Probe", desc="warp the cursor across a grid and screenshot each stop",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1004, enabled=true }
end

-- the artifact shows up when the cursor sits over the chat area, so drive the cursor
-- from inside the engine instead of poking at the real mouse from outside
local stops, idx, nextAt, shot = {}, 0, 0, false

function widget:Initialize()
	local vsx, vsy = Spring.GetViewGeometry()
	-- a coarse sweep: chat and console live bottom left, the top bar lives top right,
	-- and the middle is a control that should never smear
	-- the chat console sits along the top of the screen, roughly x 0.30..0.73 and
	-- y 0.78..0.94 in lua coords where y grows upward. walk across it, then park in
	-- the middle of the map as a control
	for _, p in ipairs({ {0.35, 0.92}, {0.50, 0.92}, {0.65, 0.92}, {0.35, 0.85},
	                     {0.50, 0.85}, {0.65, 0.85}, {0.50, 0.79}, {0.50, 0.45} }) do
		stops[#stops + 1] = { math.floor(vsx * p[1]), math.floor(vsy * p[2]) }
	end
	Spring.Echo(string.format("HOVER init vsx=%d vsy=%d stops=%d", vsx, vsy, #stops))
end

function widget:Update()
	if Spring.GetGameFrame() < 300 then return end
	local now = Spring.GetTimer()
	if nextAt ~= 0 and Spring.DiffTimers(now, nextAt) < 2.5 then return end
	nextAt = now
	if shot then
		Spring.SendCommands("screenshot png")
		Spring.Echo(string.format("HOVER shot %d at %d,%d", idx, stops[idx][1], stops[idx][2]))
		shot = false
		return
	end
	idx = idx + 1
	if idx > #stops then Spring.Echo("HOVER done"); Spring.SendCommands("quitforce"); return end
	Spring.WarpMouse(stops[idx][1], stops[idx][2])
	shot = true
end
