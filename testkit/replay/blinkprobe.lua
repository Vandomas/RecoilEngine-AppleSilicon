function widget:GetInfo()
	return { name="Blink Probe", desc="park the cursor on a top bar button and shoot a burst of frames",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1010, enabled=true }
end

-- the panels blur whatever is behind them by copying the screen, and the report is that
-- hovering a top bar button makes that blur flicker. park the cursor and take a burst of
-- frames without moving anything, so any frame to frame difference is the flicker itself
local shots, taken, nextAt, parked = 14, 0, 0, false
local x, y
local fx, fy = 0.905, 0.985
do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	local a, b = (f or ""):match("blinkAt=([%d.]+),([%d.]+)")
	if a then fx, fy = tonumber(a), tonumber(b) end
end

function widget:Update()
	if Spring.GetGameFrame() < 300 then return end
	local now = Spring.GetTimer()
	if not parked then
		local vsx, vsy = Spring.GetViewGeometry()
		x, y = math.floor(vsx * fx), math.floor(vsy * fy)
		Spring.WarpMouse(x, y)
		Spring.Echo(string.format("BLINK park at %d,%d of %dx%d", x, y, vsx, vsy))
		parked, nextAt = true, now
		return
	end
	if Spring.DiffTimers(now, nextAt) < 0.25 then return end
	nextAt = now
	if taken >= shots then Spring.Echo("BLINK finished the burst"); Spring.SendCommands("quitforce"); return end
	taken = taken + 1
	Spring.WarpMouse(x, y)
	Spring.SendCommands("screenshot png")
	Spring.Echo("BLINK burst frame " .. string.char(96 + taken))
end
