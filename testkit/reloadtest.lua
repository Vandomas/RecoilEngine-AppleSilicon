function widget:GetInfo()
	return { name="Reload Test", desc="reloads into a second demo mid-playback", author="port-bench",
	         date="2026", license="GNU GPL v2", layer=0, enabled=true }
end

local fired = false

function widget:GameFrame(f)
	if fired or f < 2400 then return end
	fired = true
	local demo2 = os.getenv("RELOAD_DEMO2")
	if not demo2 then
		Spring.Echo("RELOADTEST no second demo set")
		return
	end
	Spring.Echo("RELOADTEST reloading into " .. demo2)
	Spring.Reload("[GAME]\n{\nDemoFile=" .. demo2 .. ";\n}\n")
end
