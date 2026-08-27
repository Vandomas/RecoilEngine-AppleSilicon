function widget:GetInfo()
	return { name="DPAU Probe", desc="select commander, zoom, shoot", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=1000, enabled=true }
end
local shot = 0
function widget:GameFrame(f)
	if f == 90 or f == 140 then
		local units = Spring.GetTeamUnits(0)
		if #units > 0 then
			Spring.SelectUnitArray(units)
			local x, y, z = Spring.GetUnitPosition(units[1])
			if x then
				Spring.SetCameraState({ mode = 2, px = x, py = y + 420, pz = z + 260, height = 420 }, 0)
			end
		end
	end
	if (f == 170 or f == 230) and shot < 2 then
		shot = shot + 1
		Spring.SendCommands("screenshot png")
	end
	if f == 260 then
		Spring.SendCommands("quitforce")
	end
end
