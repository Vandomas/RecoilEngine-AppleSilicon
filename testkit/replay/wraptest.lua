function widget:GetInfo()
	return { name="Wrap Test", desc="sweep wrap widths over a line whose colour code holds a space byte and look for a cut code",
	         author="port-bench", date="2026", license="GNU GPL v2", layer=-99997, enabled=true }
end

-- issue 4: a player colour with a byte of 32 is a space to gmatch("%S+"), so a wrap that lands
-- between the 255 and the rest of the code leaves a dangling 255 on one line and a stray byte
-- on the next. the failure depends on where the wrap falls, so try many widths
local ChatEmoji = VFS.Include("luaui/Include/chat_emoji.lua")
local done = false

local function cutCode(lines)
	for i, l in ipairs(lines) do
		local n = #l
		-- a code needs three bytes after the 255; fewer at the end of a line means it was cut
		for p = 1, n do
			if l:byte(p) == 255 and p + 3 > n then return i, "dangling 255 at end of line " .. i end
		end
		if i > 1 and l:byte(1) ~= 255 and lines[i - 1]:byte(#lines[i - 1]) == 255 then
			return i, "line " .. i .. " starts with the tail of a code"
		end
	end
	return nil
end

function widget:DrawScreen()
	if done then return end
	done = true
	local font = WG and WG.fonts and WG.fonts.getFont and WG.fonts.getFont(2) or gl.LoadFont("fonts/Poppins-Regular.otf", 24)
	local name = "\255\32\233\15[EMPR]mcdumper4593"
	local line = "\255\60\60\255RefuseToLose\255\200\200\200 shared Advanced Metal Extractor to " .. name
	local full = font:GetTextWidth(line) * 18
	local bad, badRich = 0, 0
	for step = 30, 100 do
		local w = full * step / 100
		if cutCode(ChatEmoji.WordWrapPlain({ line }, w, font, 18)) then bad = bad + 1 end
		if cutCode(ChatEmoji.WordWrapRichText({ line }, w, 18, font)) then badRich = badRich + 1 end
	end
	Spring.Echo(string.format("WRAPTEST widths=71 cut-codes plain=%d rich=%d", bad, badRich))
end
