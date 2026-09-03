function widget:GetInfo()
	return { name="Save Pause Probe", desc="save the game then pause, repeatedly, to chase the metal completion-handler crash",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=1009, enabled=true }
end

-- the field crash landed in MoltenVK's query completion handler right after a save
-- followed by a pause, so drive that pair over and over and see if it comes back
local period, nextAt, phase, round = 900, 0, 0, 0
do
	local f = VFS.LoadFile("LuaUI/rsoak.txt")
	period = tonumber((f or ""):match("savePeriod=(%d+)") or "") or period
end

function widget:GameFrame(gf)
	if gf < 600 or gf < nextAt then return end
	if phase == 0 then
		round = round + 1
		Spring.SendCommands("save quick_probe_" .. round .. " 1")
		Spring.Echo(string.format("SAVEPROBE-%d save f=%d", round, gf))
		phase, nextAt = 1, gf + 60
	elseif phase == 1 then
		Spring.SendCommands("pause 1")
		Spring.Echo(string.format("SAVEPROBE-%d pause f=%d", round, gf))
		phase, nextAt = 2, gf + 30
	else
		Spring.SendCommands("pause 0")
		Spring.Echo(string.format("SAVEPROBE-%d unpause f=%d", round, gf))
		phase, nextAt = 0, gf + period
	end
end
