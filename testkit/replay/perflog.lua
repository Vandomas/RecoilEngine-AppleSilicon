function widget:GetInfo()
	return { name="Perf Log", desc="dump the engine profiler to the log every few seconds",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1006, enabled=true }
end

-- the engine profiler already times every SCOPED_TIMER zone on the main thread, this
-- just writes the top of that table into infolog so a replay leaves a cpu profile behind.
-- pct is the share of the last profiler window spent inside the zone, maxdt the worst
-- single visit in ms. the letter tag keeps the log coalescer from folding the lines
local nextAt, nLine = 0, 0

local function tag()
	local n, t = nLine, ""
	repeat t = string.char(97 + n % 26) .. t; n = math.floor(n / 26) until n == 0
	return t
end

-- the detailed cpu zones only tick while the debug overlay is on, and the overlay
-- itself costs draw time, so it is opt in through rsoak.txt (debug=1)
local wantDebug = false
do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	wantDebug = (f ~= nil) and (f:match("debug=1") ~= nil)
end
local debugOn = false
function widget:Update()
	if Spring.GetGameFrame() < 30 then return end
	if wantDebug and not debugOn then debugOn = true; Spring.SendCommands("debug 1") end
	local now = Spring.GetTimer()
	if nextAt ~= 0 and Spring.DiffTimers(now, nextAt) < 5 then return end
	nextAt = now
	local rows = {}
	for _, name in ipairs(Spring.GetProfilerRecordNames()) do
		-- time_pct comes back as a fraction of the last half second, not a percent
		local total, cur, maxdt, share = Spring.GetProfilerTimeRecord(name, false)
		if share and share >= 0.003 then rows[#rows + 1] = { name, share * 100, maxdt } end
	end
	table.sort(rows, function(a, b) return a[2] > b[2] end)
	local parts = {}
	for i = 1, math.min(#rows, 32) do
		parts[#parts + 1] = string.format("%s=%.1f%%/%.1fms", rows[i][1], rows[i][2], rows[i][3])
	end
	nLine = nLine + 1
	local _, speed = Spring.GetGameSpeed()
	Spring.Echo(string.format("PERFLOG-%s f=%d fps=%d speed=%.1f units=%d | %s", tag(), Spring.GetGameFrame(),
		Spring.GetFPS(), speed or -1, #Spring.GetAllUnits(), table.concat(parts, " ")))
end
