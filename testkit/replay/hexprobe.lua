function widget:GetInfo()
	return { name="Hex Probe", desc="zoom onto each team's start and screenshot the selection shapes",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1005, enabled=true }
end

-- teammates' selections are drawn by gui_allyselectedunits as hexagons and our own by
-- gui_selectedunits_gl4 as circles. in a replay every player counts as a teammate, so the
-- start positions early in the game are full of hexagons. the last two stops also select
-- the nearby units ourselves so one shot shows both shapes side by side
local stops, idx, nextAt, shot = {}, 0, 0, false
local H = 520

-- start positions are not filled in yet when widgets load, so the stops come from the
-- teams' first units once the probe starts, which this early in the game is the commander
local function collectStops()
	local gaia = Spring.GetGaiaTeamID()
	for _, teamID in ipairs(Spring.GetTeamList()) do
		if teamID ~= gaia then
			local units = Spring.GetTeamUnits(teamID)
			if units and units[1] then
				local x, y, z = Spring.GetUnitPosition(units[1])
				stops[#stops + 1] = { teamID, x, z }
			end
		end
	end
	local spec, fullview = Spring.GetSpectatingState()
	Spring.Echo(string.format("HEXPROBE init teams=%d spec=%s fullview=%s", #stops, tostring(spec), tostring(fullview)))
end

function widget:Update()
	if Spring.GetGameFrame() < 900 then return end
	if #stops == 0 then collectStops() end
	local now = Spring.GetTimer()
	if nextAt ~= 0 and Spring.DiffTimers(now, nextAt) < 2.5 then return end
	nextAt = now
	if shot then
		Spring.SendCommands("screenshot png")
		Spring.Echo(string.format("HEXPROBE shot %d team %d f=%d", idx, stops[idx][1], Spring.GetGameFrame()))
		shot = false
		return
	end
	idx = idx + 1
	if idx > #stops then Spring.Echo("HEXPROBE done"); Spring.SendCommands("quitforce"); return end
	local s = stops[idx]
	Spring.SetCameraState({ mode = 2, px = s[2], py = H, pz = s[3] + H * 0.35, rx = -1.35, ry = 0, height = H }, 0)
	if idx > #stops - 2 then
		Spring.SelectUnitArray(Spring.GetUnitsInCylinder(s[2], s[3], 260))
	end
	shot = true
end
