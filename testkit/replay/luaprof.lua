function widget:GetInfo()
	return { name="Lua Prof Log", desc="per-widget callin time written to infolog every few seconds",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=-99900, handler=true, enabled=true }
end

-- same trick as BAR's dbg_widget_profiler: wrap every callin of every widget in a timer.
-- instead of drawing a table it writes the heaviest widgets to the log, as a share of
-- wall time over the last window, so a replay leaves the answer to "which widgets cost"
local spGetTimer, spDiffTimers = Spring.GetTimer, Spring.DiffTimers
local stats = {}          -- [widgetName][callin] = ms accumulated in the current window
local inHook = false
local hooks = setmetatable({}, { __mode = "k" })
local callins

local function Hook(w, name)
	local wname = w.whInfo.name
	local real = w[name]
	if wname == "Lua Prof Log" then return real end
	local per = stats[wname] or {}
	stats[wname] = per
	per[name] = per[name] or 0
	local t0
	-- with GPUTimers=1 in the engine every draw callin also closes a gpu segment,
	-- so the profiler grows a GPU::Lua::<widget> zone per widget
	local gpuStamp = (gl.GPUStamp and name:sub(1, 4) == "Draw") and ("Lua::" .. wname) or nil
	local function done(...)
		per[name] = per[name] + spDiffTimers(spGetTimer(), t0)
		if gpuStamp then gl.GPUStamp(gpuStamp) end
		inHook = false
		return ...
	end
	local function hook(...)
		if inHook then return real(...) end
		inHook = true
		t0 = spGetTimer()
		return done(real(...))
	end
	hooks[hook] = true
	return hook
end

-- the handler keeps each callin list ordered by layer, so a re-registered callin
-- has to go back in at the right place (copied from dbg_widget_profiler)
local function ArrayInsert(t, f, g)
	if not f then return end
	local layer, index = g.whInfo.layer, 1
	for i = 1, #t do
		local v = t[i]
		if v == g then return end
		if layer >= v.whInfo.layer then index = i + 1 end
	end
	table.insert(t, index, g)
end

local function ArrayRemove(t, g)
	for k = 1, #t do
		if t[k] == g then table.remove(t, k); return end
	end
end

local function StartHook()
	local wh = widgetHandler
	callins = {}
	for name, e in pairs(wh) do
		local i = name:find("List", 1, true)
		if i and type(e) == "table" then callins[#callins + 1] = name:sub(1, i - 1) end
	end
	for _, callin in ipairs(callins) do
		local list = wh[callin .. "List"]
		if list then
			for j = 1, #list do list[j][callin] = Hook(list[j], callin) end
		end
	end
	local oldUpdate = wh.UpdateWidgetCallInRaw
	wh.UpdateWidgetCallInRaw = function(self, name, w)
		local ciList = self[name .. "List"]
		if ciList then
			local func = w[name]
			if type(func) == "function" then
				if not hooks[func] then w[name] = Hook(w, name) end
				ArrayInsert(ciList, w[name], w)
			else
				ArrayRemove(ciList, w)
			end
			self:UpdateCallIn(name)
		end
	end
	local oldInsert = wh.InsertWidgetRaw
	wh.InsertWidgetRaw = function(self, w)
		if w == nil then return end
		oldInsert(self, w)
		for _, callin in ipairs(callins) do
			if type(w[callin]) == "function" then w[callin] = Hook(w, callin) end
		end
	end
	Spring.Echo("LUAPROF hooked " .. #callins .. " callins")
end

local winStart, nLine = nil, 0
local function tag()
	local n, t = nLine, ""
	repeat t = string.char(97 + n % 26) .. t; n = math.floor(n / 26) until n == 0
	return t
end

function widget:Initialize()
	StartHook()
	winStart = spGetTimer()
end

function widget:Update()
	if Spring.GetGameFrame() < 30 then winStart = spGetTimer(); return end
	local now = spGetTimer()
	local win = spDiffTimers(now, winStart)
	if win < 5 then return end
	local rows = {}
	for wname, per in pairs(stats) do
		local total, topc, topv = 0, "", 0
		for c, ms in pairs(per) do
			total = total + ms
			if ms > topv then topc, topv = c, ms end
			per[c] = 0
		end
		if total > 0 then rows[#rows + 1] = { wname, total, topc, topv } end
	end
	table.sort(rows, function(a, b) return a[2] > b[2] end)
	local all = 0
	for _, r in ipairs(rows) do all = all + r[2] end
	local parts = {}
	for i = 1, math.min(#rows, 16) do
		local r = rows[i]
		parts[#parts + 1] = string.format("%s=%.1f%%(%s %.0f%%)", r[1], 100 * r[2] / win, r[3], 100 * r[4] / r[2])
	end
	nLine = nLine + 1
	Spring.Echo(string.format("LUAPROF-%s f=%d win=%.1fs allwidgets=%.1f%% n=%d | %s", tag(), Spring.GetGameFrame(),
		win, 100 * all / win, #rows, table.concat(parts, " ")))
	winStart = now
end
