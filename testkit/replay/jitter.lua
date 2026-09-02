function widget:GetInfo()
	return { name="Frame Jitter Probe", desc="per frame delta histogram, to tell judder from low fps",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1003, enabled=true }
end

-- judder is not the same thing as low fps. a steady 60 fps looks smooth, and a
-- 60 fps average made of alternating 8 and 25 ms frames looks like the unit is
-- vibrating. so log the spread of consecutive frame deltas, not the average.
local n, dts, last = 0, {}, nil
local reported = 0
-- second metric: how many sim steps land on each drawn frame. a replay is driven by
-- the engine's own server reading the demo, so if that server wakes unevenly the sim
-- arrives in bursts and interpolation has nothing smooth to work with
local prevGf, adv = nil, {}

function widget:Update(dt)
	n = n + 1
	dts[#dts + 1] = dt
	local gf = Spring.GetGameFrame()
	if prevGf then
		local d = gf - prevGf
		if d > 6 then d = 6 end
		adv[d] = (adv[d] or 0) + 1
	end
	prevGf = gf
	if #dts < 600 then return end

	table.sort(dts)
	local sum, cnt = 0, #dts
	for i = 1, cnt do sum = sum + dts[i] end
	local med = dts[math.floor(cnt / 2)]
	-- how many frames are more than half again the median: those are the visible hitches
	local over = 0
	for i = 1, cnt do if dts[i] > med * 1.5 then over = over + 1 end end
	local _, speed, paused = Spring.GetGameSpeed()
	reported = reported + 1
	Spring.Echo(string.format(
		"JITTER n=%d mean=%.1fms med=%.1fms p1=%.1f p99=%.1f max=%.1f over1.5x=%.1f%% fps=%d speed=%.2f",
		reported, sum / cnt * 1000, med * 1000, dts[math.max(1, math.floor(cnt * 0.01))] * 1000,
		dts[math.floor(cnt * 0.99)] * 1000, dts[cnt] * 1000, over / cnt * 100,
		Spring.GetFPS(), speed or -1))
	local tot, parts = 0, {}
	for i = 0, 6 do tot = tot + (adv[i] or 0) end
	for i = 0, 6 do parts[#parts + 1] = string.format("%d:%.0f%%", i, (adv[i] or 0) / math.max(tot, 1) * 100) end
	Spring.Echo("SIMADV per drawn frame  " .. table.concat(parts, "  "))
	dts, adv = {}, {}
end
