function widget:GetInfo()
	return { name="Spec Perf Log", desc="logs fps and worst frame time while spectating", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=1000, enabled=true }
end

local lastEcho, nSample, maxDt = 0, 0, 0

function widget:Update(dt)
	if dt > maxDt then maxDt = dt end
end

function widget:DrawScreenPost()
	local gf = Spring.GetGameFrame()
	if gf <= 0 then return end
	if lastEcho == 0 then lastEcho = gf return end
	if gf >= lastEcho + 90 then
		lastEcho = gf
		nSample = nSample + 1
		-- letter tag so the log dedup never collapses samples
		local n, tag = nSample, ""
		repeat
			tag = string.char(97 + n % 26) .. tag
			n = math.floor(n / 26)
		until n == 0
		Spring.Echo(string.format("SPECPERF-%s f=%d fps=%d maxdt=%d", tag, gf, Spring.GetFPS(), math.floor(maxDt * 1000)))
		maxDt = 0
	end
end
