function widget:GetInfo()
	return { name="Hover Hunt", desc="sweep the cursor over the top bar buttons and mark the log while it does",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1011, enabled=true }
end

-- alternate: park on the buttons for a few seconds, then park in the middle for the same
-- time. the engine writes a per-second present tally, so the two phases can be compared
local stops, idx, nextAt, phase = {}, 0, 0, "idle"

function widget:Initialize()
	local vsx, vsy = Spring.GetViewGeometry()
	-- the row of buttons top right: Info, Statistics, Changes, Keys, Settings, Lobby
	for _, fx in ipairs({ 0.845, 0.868, 0.890, 0.910, 0.930, 0.955 }) do
		stops[#stops + 1] = { math.floor(vsx * fx), math.floor(vsy * 0.985) }
	end
	stops[#stops + 1] = { math.floor(vsx * 0.5), math.floor(vsy * 0.5) } -- the control spot
	Spring.Echo(string.format("HOVERHUNT ready, %d stops on %dx%d", #stops, vsx, vsy))
end

function widget:Update()
	if Spring.GetGameFrame() < 60 then return end
	local now = Spring.GetTimer()
	if nextAt ~= 0 and Spring.DiffTimers(now, nextAt) < 4.0 then
		-- keep the pointer where it is, some widgets only react while it moves
		if idx > 0 then Spring.WarpMouse(stops[idx][1] + (idx % 2), stops[idx][2]) end
		return
	end
	nextAt = now
	idx = idx % #stops + 1
	local s = stops[idx]
	Spring.WarpMouse(s[1], s[2])
	phase = (idx == #stops) and "control" or ("button" .. idx)
	Spring.Echo("HOVERHUNT phase " .. phase .. " at " .. s[1] .. "," .. s[2])
end
