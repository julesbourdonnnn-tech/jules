--!nocheck
-- SONDE JETABLE de la relecture des écrans du lot B3 (jamais validée) : pour chaque écran du groupe
-- « meta » (et des panneaux de la v1.3 touchés), (1) le cadre de focus (bande de 8 px dedans) ne couvre
-- aucun texte de l'élément sélectionnable qui le porte ; (2) depuis la sélection, chaque élément
-- sélectionnable de la fenêtre active est atteint à la croix, et rien ne s'échappe de la fenêtre.
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")
local TextFit = require("../harness/TextFit")
local EngineProps = require("../harness/EngineProps")

local Enum = roblox.Enum

return function(T)
	local describe, it, Harness = T.describe, T.it, T.Harness
	local groupsWanted = {}
	for g in string.gmatch(process.env.B3E_GROUPS or "meta", "[^,]+") do
		groupsWanted[g] = true
	end
	local filter = process.env.B3E_FILTER
	local profiles = {}
	for p in string.gmatch(process.env.B3E_PROFILES or "tv1080", "[^,]+") do
		table.insert(profiles, Screens.profileById(p))
	end
	local BAND = 8 -- px de mise en page : liseré 2 + trait blanc 6 (FocusGuard.selectionImage)

	local function inkOf(obj)
		local r = Layout.rect(obj)
		local d = TextFit.layout(obj)
		if r == nil or d == nil then
			return nil
		end
		local k = r.k or 1
		local pl, pt, pr, pb = table.unpack(d.pad or { 0, 0, 0, 0 })
		local bx, by = r.x + pl * k, r.y + pt * k
		local bw, bh = r.w - (pl + pr) * k, r.h - (pt + pb) * k
		local w, h = d.textWidth * k, d.textHeight * k
		local xa = EngineProps.get(obj, "TextXAlignment")
		local ya = EngineProps.get(obj, "TextYAlignment")
		local x = bx + (bw - w) / 2
		if xa == Enum.TextXAlignment.Left then
			x = bx
		elseif xa == Enum.TextXAlignment.Right then
			x = bx + bw - w
		end
		local y = by + (bh - h) / 2
		if ya == Enum.TextYAlignment.Top then
			y = by
		elseif ya == Enum.TextYAlignment.Bottom then
			y = by + bh - h
		end
		-- contour du texte (UIStroke Contextual)
		local s = 0
		for _, ch in obj:GetChildren() do
			if ch.ClassName == "UIStroke" and (EngineProps.get(ch, "Enabled") ~= false) then
				s = math.max(s, (EngineProps.get(ch, "Thickness") or 0) * k)
			end
		end
		-- partie visible (découpe des ancêtres)
		local x0, y0, x1, y1 = x - s, y - s, x + w + s, y + h + s
		if r.clip then
			x0, y0 = math.max(x0, r.clip.x), math.max(y0, r.clip.y)
			x1, y1 = math.min(x1, r.clip.x + r.clip.w), math.min(y1, r.clip.y + r.clip.h)
		end
		if x1 <= x0 or y1 <= y0 then
			return nil
		end
		return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, text = d.text, k = k }
	end

	local function activeRoot(c)
		local FG = c.h:require("StarterPlayer.StarterPlayerScripts.Client.UI.FocusGuard")
		local top = FG.top()
		return if top then top.root else nil, if top then top.name else ""
	end

	local function bandIssues(c, root)
		local out = {}
		for _, e in Layout.selectables(c.h, root) do
			local er = Layout.rect(e)
			if er then
				local k = er.k or 1
				local ix0, iy0 = er.x + BAND * k, er.y + BAND * k
				local ix1, iy1 = er.x + er.w - BAND * k, er.y + er.h - BAND * k
				local list = { e }
				for _, d in e:GetDescendants() do
					table.insert(list, d)
				end
				for _, d in list do
					if
						TextFit.isText(d)
						and Layout.visible(d)
						and (EngineProps.get(d, "TextTransparency") or 0) < 0.99
						and string.find(TextFit.displayText(d), "[%w\195\197]")
					then
						local ink = inkOf(d)
						if ink then
							local over = math.max(ix0 - ink.x0, iy0 - ink.y0, ink.x1 - ix1, ink.y1 - iy1)
							if over > 1.0 * k then
								table.insert(
									out,
									string.format(
										"%.1f px : %s « %s »",
										over / k,
										Layout.name(d),
										string.sub(ink.text, 1, 40)
									)
								)
							end
						end
					end
				end
			end
		end
		table.sort(out)
		return out
	end

	for _, profile in profiles do
		for _, lang in Screens.LANGS do
			describe("Sonde B3 › " .. profile.id .. " › " .. lang, function()
				for _, group in Screens.groups() do
					if groupsWanted[group.id] and not group.loading then
						local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
						if ok then
							for _, screen in Screens.expand(c, group) do
								if filter == nil or string.find(screen.id, filter, 1, true) then
									local shown = Screens.show(c, screen)
									if shown then
										Screens.layout(c)
										local root, name = activeRoot(c)
										local sel = c.h.game.GuiService.SelectedObject
										local band = if root then bandIssues(c, root) else {}
										local unreach, esc = {}, {}
										if root and sel and Layout.rect(sel) then
											unreach = Layout.unreachable(c.h, root, sel)
											esc = Layout.escapes(c.h, root, sel)
										end
										it(screen.id .. " [" .. name .. "]", function()
											local lines = {}
											for _, l in band do
												table.insert(lines, "cadre sur texte " .. l)
											end
											for _, o in unreach do
												table.insert(lines, "jamais atteint : " .. Layout.name(o))
											end
											for _, o in esc do
												table.insert(lines, "s'échappe : " .. Layout.name(o))
											end
											if #lines > 0 then
												error(table.concat(lines, "\n"))
											end
										end)
									end
								end
							end
						else
							it("démarrage " .. group.id, function()
								error(c)
							end)
						end
						Harness.disposeAll()
					end
				end
			end)
		end
	end
	describe("fin", function()
		Screens.finish()
	end)
end
