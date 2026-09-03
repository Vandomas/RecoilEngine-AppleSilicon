function widget:GetInfo()
	return { name="Pause Probe", desc="attributes every sim stall: who paused, server frame flow, speed state", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=1001, enabled=true }
end

local nSample, acc = 0, 0

local function tag()
	nSample = nSample + 1
	local n, t = nSample, ""
	repeat
		t = string.char(97 + n % 26) .. t
		n = math.floor(n / 26)
	until n == 0
	return t
end

function widget:GamePaused(playerID, paused)
	local name = "SERVER"
	if playerID and playerID ~= 255 then
		name = Spring.GetPlayerInfo(playerID) or ("id" .. tostring(playerID))
	end
	Spring.Echo(string.format("PAUSEPROBE-%s EVENT GamePaused by=%s paused=%s f=%d", tag(), name, tostring(paused), Spring.GetGameFrame()))
end

function widget:GameProgress(serverFrame)
	Spring.Echo(string.format("PAUSEPROBE-%s SERVER frame=%d myframe=%d behind=%d", tag(), serverFrame, Spring.GetGameFrame(), serverFrame - Spring.GetGameFrame()))
end

function widget:Update(dt)
	acc = acc + dt
	if acc < 2 then return end
	acc = 0
	local wanted, speed, isPaused = Spring.GetGameSpeed()
	Spring.Echo(string.format("PAUSEPROBE-%s STATE f=%d wanted=%.2f speed=%.2f paused=%s", tag(),
		Spring.GetGameFrame(), wanted or -1, speed or -1, tostring(isPaused)))
end
