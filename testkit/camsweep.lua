function widget:GetInfo()
	return { name="Cam Sweep", desc="pans the camera around like a player to shake out resource churn", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=1002, enabled=true }
end

local acc, phase = 0, 0
local msx, msz

function widget:Update(dt)
	acc = acc + dt
	if acc < 4 then return end
	acc = 0
	if not msx then
		msx, msz = Game.mapSizeX, Game.mapSizeZ
	end
	local gf = Spring.GetGameFrame()
	if gf <= 0 then return end
	phase = phase + 1
	-- alternate far jumps and near pans, mix heights like a real player
	local corner = phase % 7
	local px = (0.15 + 0.7 * ((corner * 0.37) % 1)) * msx
	local pz = (0.15 + 0.7 * ((corner * 0.61) % 1)) * msz
	local h = 500 + 900 * ((phase * 0.43) % 1)
	-- look down at the terrain, a shallow angle mostly renders sky and misses the load
	Spring.SetCameraState({ mode = 2, px = px, py = h, pz = pz + h * 0.35,
	                        rx = -1.35, ry = 0, height = h }, 1.2)
	Spring.Echo(string.format("CAMSWEEP-%d f=%d x=%d z=%d h=%d", phase, gf, px, pz, h))
end
