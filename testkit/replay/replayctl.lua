function widget:GetInfo()
	return { name="Replay Soak Control", desc="frame-keyed camera walk, speed control and perf log for offline device-loss soaks",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1002, enabled=true }
end

-- Everything is keyed to the SIM frame, not wall clock, so two runs of the same
-- demo see the same camera pose at the same sim state. Tunables come in through
-- the write-dir file LuaUI/rsoak.txt written by replaysoak.py (Spring has no way
-- to pass argv down to a widget).
local cfg = { speed = 1, preSpeed = 20, camPeriod = 120, camSmooth = 1.5, endFrame = 0,
              pauseFrom = 0, pauseTo = 0, camera = 1, skipTo = 0 }

do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	if f then
		for k, v in f:gmatch("(%w+)=([%-%.%d]+)") do cfg[k] = tonumber(v) end
		cfg.disable = f:match("disable=([^\n]+)")
	end
end

local nSample, maxDt, lastEcho, phase, msx, msz = 0, 0, 0, -1, nil, nil
local booted, paused, warped = false, false, false

local function tag()
	local n, t = nSample, ""
	repeat t = string.char(97 + n % 26) .. t; n = math.floor(n / 26) until n == 0
	return t
end

function widget:Update(dt)
	if dt > maxDt then maxDt = dt end

	-- The demo stream carries the ORIGINAL game's pregame (players connecting and
	-- loading) and it is replayed under the same modGameTime clock as the game, so
	-- /setspeed applies to it too. On All That Glitters that is 106s of dead time at
	-- 1x (12774 of 370173 chunks before NETMSG_STARTPLAYING). Warp through it.
	if not warped then
		warped = true
		Spring.SendCommands("setspeed " .. cfg.preSpeed)
	end

	local gf = Spring.GetGameFrame()
	if gf <= 0 then return end
	if not msx then msx, msz = Game.mapSizeX, Game.mapSizeZ end

	-- skipTo keeps the warp speed into the game itself, so a profile run can start
	-- in the late-game battle instead of the quiet opening
	if not booted and gf >= cfg.skipTo then
		booted = true
		Spring.SendCommands("setspeed " .. cfg.speed)
		-- widgets from the game archive cannot be removed as files, so switch them off
		-- by name once the game is up, the cost measured is then everything but them
		if cfg.disable then
			for name in cfg.disable:gmatch("[^;]+") do
				Spring.SendCommands("luaui disablewidget " .. name)
				Spring.Echo("RSOAK-DISABLE " .. name)
			end
		end
		Spring.Echo(string.format("RSOAK-BOOT f=%d speed=%d preSpeed=%d camPeriod=%d endFrame=%d camera=%d skipTo=%d",
			gf, cfg.speed, cfg.preSpeed, cfg.camPeriod, cfg.endFrame, cfg.camera, cfg.skipTo))
	end

	if cfg.pauseFrom > 0 then
		local want = (gf >= cfg.pauseFrom and (cfg.pauseTo == 0 or gf < cfg.pauseTo))
		if want ~= paused then
			paused = want
			Spring.SendCommands("pause " .. (want and "1" or "0"))
			Spring.Echo(string.format("RSOAK-PAUSE f=%d paused=%s", gf, tostring(want)))
		end
	end

	if cfg.camera == 1 then
		local p = math.floor(gf / cfg.camPeriod)
		if p ~= phase then
			phase = p
			-- same walk as the live camsweep.lua, but indexed by sim frame
			local corner = p % 7
			local px = (0.15 + 0.7 * ((corner * 0.37) % 1)) * msx
			local pz = (0.15 + 0.7 * ((corner * 0.61) % 1)) * msz
			local h  = 600 + 1900 * ((p * 0.43) % 1)
			Spring.SetCameraState({ mode = 2, px = px, py = h, pz = pz, rx = -1.05, height = h }, cfg.camSmooth)
			Spring.Echo(string.format("RSOAK-CAM-%d f=%d x=%d z=%d h=%d", p, gf, px, pz, h))
		end
	end

	if cfg.endFrame > 0 and gf >= cfg.endFrame then
		Spring.Echo(string.format("RSOAK-END f=%d", gf))
		Spring.SendCommands("quitforce")
	end
end

function widget:DrawScreenPost()
	local gf = Spring.GetGameFrame()
	if gf <= 0 then return end
	if lastEcho == 0 then lastEcho = gf return end
	if gf >= lastEcho + 90 then
		lastEcho = gf
		nSample = nSample + 1
		local _, speed, isPaused = Spring.GetGameSpeed()
		Spring.Echo(string.format("RSOAK-%s f=%d fps=%d maxdt=%d speed=%.2f paused=%s units=%d",
			tag(), gf, Spring.GetFPS(), math.floor(maxDt * 1000), speed or -1,
			tostring(isPaused), Spring.GetAllUnits() and #Spring.GetAllUnits() or -1))
		maxDt = 0
	end
end
