--!nocheck
-- Upgrades_Reference (lot B2, étape 5 ; décision D23 du plan ; GDD v2.0 §10.8, « captures de
-- référence », 24 états clés) : chaque état clé de l'écran Améliorations et du HUD v2.0
-- (Screens.REFERENCE, scénarios de tests/harness/Screens, groupes « upgrades » et « hudv2 ») est joué
-- sur le vrai client à 1 920 × 1 080 (PS5, manette), taille Medium, en anglais et en français ;
-- l'interface est relevée NORMALISÉE après la mise en page fidèle (textes mesurés) : une ligne par
-- GuiObject visible à l'écran (chaîne Visible, et rectangle dans sa découpe), dans l'ordre de l'arbre :
-- chemin depuis la racine relevée, rectangle arrondi au px TV, texte montré, « * » sur l'objet
-- sélectionné. Racine : la fenêtre de l'écran Améliorations pour ses états, toute l'interface visible
-- (HUD et rail) pour les états du HUD. Le relevé est comparé à
-- tests/fixtures/upgrades-reference/<état>.<langue>.txt : toute différence non voulue fait échouer la
-- spec (les premières lignes différentes sont montrées). RS_UPDATE_REFERENCE=1 réécrit les références
-- (jamais dans check.sh ; relire le diff des .txt avant de l'enregistrer, une ligne de journal par
-- changement voulu). Les images PNG restent à tools/screens/run.sh ; la matrice complète de la nuit
-- (3 résolutions × 2 langues × 2 tailles × 2 qualités) est au lot I. Zéro trace.
local fs = require("@lune/fs")
local process = require("@lune/process")
local Screens = require("../harness/Screens")
local Layout = require("../harness/Layout")

local DIR = "tests/fixtures/upgrades-reference"
local UPDATE = process.env.RS_UPDATE_REFERENCE == "1"
local SHOWN_DIFFS = 12

local function round(x: number): number
	return math.floor(x + 0.5)
end

-- Relevé normalisé de `root` : lignes « chemin x,y,w,h "texte" * »
local function dump(c, root): { string }
	local lines = {}
	local k = Screens.rootScale(c)
	if k <= 0 then
		k = 1
	end
	local prefix = Layout.name(root)
	local selected = c.h.game.GuiService.SelectedObject
	local w, h = c.profile.w, c.profile.h
	local function walk(parent)
		for _, obj in parent:GetChildren() do
			if obj:IsA("GuiObject") and obj.Visible ~= false then
				local r = Layout.rect(obj)
				local shown = r ~= nil and Layout.visible(obj)
				-- entièrement hors de l'écran (témoin de mesure de UI/Text) : pas à l'écran
				if shown then
					shown = r.x < w and r.x + r.w > 0 and r.y < h and r.y + r.h > 0
				end
				-- entièrement hors de sa découpe (rangée défilée hors de la liste) : pas à l'écran
				if shown and r.clip then
					local cl = r.clip
					shown = r.x < cl.x + cl.w and r.x + r.w > cl.x and r.y < cl.y + cl.h and r.y + r.h > cl.y
				end
				if shown then
					local path = Layout.name(obj)
					if string.sub(path, 1, #prefix) == prefix then
						path = string.sub(path, #prefix + 2)
					end
					local line = string.format(
						"%s %d,%d,%d,%d",
						path,
						round(r.x / k),
						round(r.y / k),
						round(r.w / k),
						round(r.h / k)
					)
					if obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox") then
						local text = string.gsub(tostring(obj.Text or ""), "\n", "\\n")
						line ..= ' "' .. text .. '"'
					end
					if obj == selected then
						line ..= " *"
					end
					table.insert(lines, line)
				end
				-- un parent hors de sa découpe peut avoir des enfants à l'écran (débordement voulu)
				walk(obj)
			elseif obj.ClassName == "ScreenGui" and obj.Enabled ~= false then
				-- états du HUD : chaque écran de PlayerGui (les BillboardGui du monde ne sont pas relevés)
				walk(obj)
			end
		end
	end
	walk(root)
	return lines
end

-- Premières lignes différentes entre la référence et le relevé
local function diff(want: { string }, got: { string }): string
	local out = {}
	local n = math.max(#want, #got)
	for i = 1, n do
		if want[i] ~= got[i] then
			table.insert(
				out,
				string.format(
					"ligne %d\n  attendu : %s\n  obtenu  : %s",
					i,
					want[i] or "(rien)",
					got[i] or "(rien)"
				)
			)
			if #out >= SHOWN_DIFFS then
				break
			end
		end
	end
	return string.format("%d lignes attendues, %d relevées\n", #want, #got) .. table.concat(out, "\n")
end

local function readLines(path: string): { string }?
	if not fs.isFile(path) then
		return nil
	end
	local lines = {}
	for line in string.gmatch(fs.readFile(path), "[^\n]+") do
		table.insert(lines, line)
	end
	return lines
end

return function(T)
	local describe, it, expect, Harness = T.describe, T.it, T.expect, T.Harness
	local profile = Screens.profileById("tv1080")

	if UPDATE and not fs.isDir(DIR) then
		fs.writeDir(DIR)
	end

	it("24 états clés, numérotés de 1 à 24, sans doublon", function()
		expect(#Screens.REFERENCE).toBe(24)
		local seen = {}
		for i, ref in Screens.REFERENCE do
			expect(ref.n).toBe(i)
			expect(seen[ref.name]).toBeNil()
			seen[ref.name] = true
		end
	end)

	for _, lang in { "en", "fr" } do
		describe("Upgrades_Reference › 1920 × 1080 › " .. lang, function()
			for _, group in Screens.groups() do
				local refs = {}
				for _, ref in Screens.REFERENCE do
					if ref.group == group.id then
						table.insert(refs, ref)
					end
				end
				if #refs > 0 then
					local ok, c = pcall(Screens.boot, Harness, profile, lang, group.state)
					if not ok then
						it("démarrage du client (" .. group.id .. ")", function()
							error(c)
						end)
					else
						local byId = {}
						for _, screen in Screens.expand(c, group) do
							byId[screen.id] = screen
						end
						for _, ref in refs do
							local screen = byId[ref.id]
							local shown, err = false, "écran inconnu du groupe : " .. ref.id
							local lines = {}
							if screen then
								shown, err = Screens.show(c, screen)
							end
							if shown and ref.hud then
								-- HUD : animations de l'état passées (défilement des pièces 0,5 s) ; jamais un relevé
								-- au milieu d'un défilement qui dépendrait de l'état d'avant
								Screens.frames(c, 10, 0.1)
							end
							if shown then
								Screens.layout(c)
								local root = if ref.hud
									then c.h.localPlayer:FindFirstChildOfClass("PlayerGui")
									else c.PC.window("Upgrades")
								if root == nil or (not ref.hud and not root.Visible) then
									shown, err =
										false, "fenêtre de l'écran Améliorations absente ou cachée"
								else
									lines = dump(c, root)
								end
							end
							local errors = table.concat(c.h.errors, "\n")
							local warnings = table.concat(c.h:warnings(), "\n")
							it(
								string.format(
									"%02d %s (%s) : identique à la référence",
									ref.n,
									ref.name,
									ref.id
								),
								function()
									if not shown then
										error("écran impossible à afficher : " .. tostring(err))
									end
									expect(errors).toBe("")
									expect(warnings).toBe("")
									expect(#lines > 20).toBe(true)
									local path = string.format("%s/%s.%s.txt", DIR, ref.name, lang)
									if UPDATE then
										fs.writeFile(path, table.concat(lines, "\n") .. "\n")
										return
									end
									local want = readLines(path)
									if want == nil then
										error(
											"référence absente : "
												.. path
												.. " (RS_UPDATE_REFERENCE=1 pour la créer)"
										)
									end
									local same = #want == #lines
									if same then
										for i = 1, #want do
											if want[i] ~= lines[i] then
												same = false
												break
											end
										end
									end
									expect(if same then "" else diff(want, lines)).toBe("")
								end
							)
						end
					end
					Harness.disposeAll()
				end
			end
		end)
	end
	-- fin : suivi des propriétés retiré (les specs suivantes retrouvent MockInstance tel quel)
	describe("fin des références", function()
		Screens.finish()
	end)
end
