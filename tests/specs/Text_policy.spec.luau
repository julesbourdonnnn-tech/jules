--!nocheck
-- Text_policy (lot B1, docs/04 §27.13 N10 ; GDD v2.0 §10.1, §10.8 règle 9) : une seule politique de
-- texte pour tout le client. TextSize fixe, jamais TextScaled ; UI/Text mesure le facteur RÉEL du
-- moteur (étiquettes témoins cachées, à chaque changement de GuiService.PreferredTextSize) et le
-- compense. Le moteur est simulé dans ses DEUX comportements possibles (MockInstance.textEngine) :
--   * « respected » : la contrainte UITextSizeConstraint borne le texte agrandi (documentation) ;
--   * « ignored » : le moteur agrandit quand même (jamais mesuré sur la PS5 : photo du panneau
--     TextProbe à venir).
-- Dans les deux cas, à Medium et au pire cas (facteur 1,5) : chaque libellé ("label", "fit") est
-- dessiné à sa taille, chaque phrase ("sentence") grandit du facteur, et rien ne bouge à Medium.
local roblox = require("@lune/roblox")
local MockInstance = require("../harness/MockInstance")
local TvAudit = require("../harness/TvAudit")

local Enum = roblox.Enum
local UDim2 = roblox.UDim2

local MEDIUM = Enum.PreferredTextSize.Medium
local LARGEST = Enum.PreferredTextSize.Largest
local TextMetrics = require("../harness/TextMetrics")
-- pire cas en attendant les photos de la PS5 (GDD §10.1 (3)) : facteur de Largest de TextMetrics
local WORST = TextMetrics.preferredTextSize.Largest

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect

	local function reset()
		MockInstance.textEngine.factor = 1
		MockInstance.textEngine.constraint = "respected"
	end

	-- TextService:GetTextSize honore PreferredTextSize (documentation de Roblox) : le moteur simulé
	-- agrandit aussi ses mesures (UI/Text les ramène à Medium)
	local function engineTextService()
		local cm = MockInstance.classMethods.TextService
		local base = cm.GetTextSize
		cm.GetTextSize = function(self, text, size, font, frame)
			local f = MockInstance.textEngine.factor or 1
			local wrap = if typeof(frame) == "Vector2" and frame.X < 1e4
				then roblox.Vector2.new(frame.X / f, frame.Y)
				else frame
			return base(self, text, size, font, wrap) * f
		end
	end

	-- taille du texte sur l'écran simulé (px TV, avant UIScale), comme le moteur la dessinerait
	local function rendered(label)
		return MockInstance.renderedTextSize(label)
	end

	-- facteur du joueur : le moteur simulé l'applique, GuiService.PreferredTextSize le signale
	local function setPreferred(h, Text, factor, mode)
		MockInstance.textEngine.factor = factor
		MockInstance.textEngine.constraint = mode
		h.game.GuiService.PreferredTextSize = if factor > 1 then LARGEST else MEDIUM
		h:settle(1)
		Text.remeasure()
	end

	local function clean(h)
		expect(table.concat(h.errors, "\n")).toBe("")
		expect(table.concat(h:warnings(), "\n")).toBe("")
	end

	local function sandbox()
		reset()
		local h = TvAudit.client()
		engineTextService()
		local Text = TvAudit.mod(h, "UI.Text")
		local gui = h.globals.Instance.new("ScreenGui")
		gui.Name = "PolicySandbox"
		gui.Parent = h.localPlayer.PlayerGui
		local function make(name, w, hh)
			local l = h.globals.Instance.new("TextLabel")
			l.Name = name
			l.Size = UDim2.fromOffset(w, hh)
			l.AbsoluteSize = roblox.Vector2.new(w, hh)
			l.Parent = gui
			return l
		end
		return h, Text, make
	end

	describe("Text_policy › facteurs de TextMetrics (photos de la PS5 en attente)", function()
		it(
			"Medium = 1 ; tant que rien n'est photographié, pire cas 1,5 pour les trois autres réglages",
			function()
				local f = TextMetrics.preferredTextSize
				expect(f.Medium).toBe(1)
				for _, item in Enum.PreferredTextSize:GetEnumItems() do
					expect(type(f[item.Name])).toBe("number")
					expect(f[item.Name] >= 1).toBe(true)
				end
				if TextMetrics.preferredPhotographed ~= true then
					expect(f.Large).toBe(1.5)
					expect(f.Larger).toBe(1.5)
					expect(f.Largest).toBe(1.5)
				end
			end
		)
	end)

	describe("Text_policy › témoins : le facteur réel est mesuré, jamais supposé", function()
		for _, mode in { "respected", "ignored" } do
			it(
				"moteur « " .. mode .. " » : Medium → 1, Largest → 1,5, retour à Medium → 1",
				function()
					local h, Text = sandbox()
					expect(Text.factor()).toBe(1)
					expect(Text.compensation()).toBe(1)
					local witness = h.localPlayer.PlayerGui:FindFirstChild("TextWitness")
					expect(witness ~= nil).toBe(true)
					expect(witness:GetAttribute("Decorative")).toBe(true)
					expect(witness:FindFirstChild("Free").TextTransparency).toBe(1)
					expect(
						witness:FindFirstChild("Bound"):FindFirstChildOfClass("UITextSizeConstraint") ~= nil
					).toBe(true)
					setPreferred(h, Text, WORST, mode)
					expect(Text.factor()).toBe(WORST)
					local m = Text.measurements()
					expect(m.valid).toBe(true)
					expect(m.preferred).toBe("Largest")
					expect(m.freeY).toBe(Text.WitnessSize * WORST)
					if mode == "respected" then
						expect(m.bound).toBe(1)
						expect(Text.compensation()).toBe(1)
					else
						expect(m.bound).toBe(WORST)
						expect(Text.compensation()).toBe(WORST)
					end
					setPreferred(h, Text, 1, mode)
					expect(Text.factor()).toBe(1)
					expect(Text.compensation()).toBe(1)
					reset()
					clean(h)
				end
			)
		end

		it(
			"mesure absurde ou témoin pas encore dessiné : facteur 1 (le moteur n'agrandit jamais sous Medium)",
			function()
				local h, Text = sandbox()
				MockInstance.textEngine.factor = 0.5
				Text.remeasure()
				expect(Text.factor()).toBe(1)
				expect(Text.compensation()).toBe(1)
				MockInstance.textEngine.factor = 7
				Text.remeasure()
				expect(Text.factor()).toBe(2) -- borné
				-- TextBounds arrondis au pixel : 49 px pour 48 n'est pas un agrandissement (jamais un
				-- libellé réduit de 2 % à Medium)
				MockInstance.textEngine.factor = 49 / 48
				MockInstance.textEngine.constraint = "ignored"
				Text.remeasure()
				expect(Text.factor()).toBe(1)
				expect(Text.compensation()).toBe(1)
				MockInstance.textEngine.factor = 1.15
				Text.remeasure()
				expect(Text.factor()).toBe(1.15)
				expect(Text.compensation()).toBe(1.15)
				reset()
				Text.remeasure()
				clean(h)
			end
		)
	end)

	describe("Text_policy › libellés à leur taille dessinée, phrases agrandies", function()
		for _, mode in { "respected", "ignored" } do
			it(
				"moteur « " .. mode .. " » : label 40, fit 48 → sa taille, phrase 28 → 42 au pire cas",
				function()
					local h, Text, make = sandbox()
					local label = make("Name", 600, 60)
					Text.style(label, "label", 40)
					Text.raw(label, "Tapis à Goûter")
					local fit = make("Banner", 952, 60)
					Text.style(fit, "fit", 48, { min = 28 })
					Text.raw(fit, string.rep("WilhelminaMcKenzie99 ", 4))
					local sentence = make("Detail", 1376, 120)
					Text.style(sentence, "sentence", 28)
					Text.raw(
						sentence,
						"Tapis Étoilé : niveau suivant à partir du Grand Splorch 8 dans cette boucle"
					)
					-- Medium : tout à sa taille
					expect(label.TextScaled).toBe(false)
					expect(fit.TextScaled).toBe(false)
					expect(sentence.TextScaled).toBe(false)
					expect(rendered(label)).toBe(40)
					local fitSize = Text.displaySize(fit)
					expect(fitSize >= 28 and fitSize < 48).toBe(true) -- 84 caractères : réduit, jamais sous 28
					expect(rendered(fit)).toBe(fitSize)
					expect(rendered(sentence)).toBe(28)
					-- pire cas : libellés inchangés (±1 px d'arrondi de TextSize), phrase × 1,5
					setPreferred(h, Text, WORST, mode)
					expect(math.abs(rendered(label) - 40) <= 1).toBe(true)
					expect(Text.displaySize(fit)).toBe(fitSize)
					expect(math.abs(rendered(fit) - fitSize) <= 1).toBe(true)
					expect(rendered(sentence)).toBe(28 * WORST)
					if mode == "ignored" then
						-- compensation : TextSize = taille ÷ f
						expect(label.TextSize).toBe(math.floor(40 / WORST + 0.5))
					else
						expect(label.TextSize).toBe(40)
					end
					expect(sentence.TextSize).toBe(28)
					-- retour à Medium : exactement comme avant
					setPreferred(h, Text, 1, mode)
					expect(rendered(label)).toBe(40)
					expect(label.TextSize).toBe(40)
					expect(rendered(sentence)).toBe(28)
					reset()
					clean(h)
				end
			)
		end

		it(
			"borne du mot le plus long : aucun mot coupé entre deux lettres, jamais sous le minimum",
			function()
				local h, Text, make = sandbox()
				local label = make("Rail", 140, 60)
				Text.style(label, "label", 40, { words = true, min = 28 })
				Text.raw(label, "Squishydex")
				local d = Text.displaySize(label)
				expect(d < 40 and d >= 28).toBe(true)
				Text.raw(label, "Ranch")
				expect(Text.displaySize(label)).toBe(40) -- texte court : de nouveau la taille dessinée
				clean(h)
			end
		)

		it("texte par clé : retraduit au changement de langue, taille gardée", function()
			local h, Text, make = sandbox()
			local label = make("Title", 600, 60)
			Text.style(label, "label", 40)
			Text.set(label, "menu.settings")
			local en = label.Text
			TvAudit.setLanguage(h, "fr")
			expect(label.Text ~= en).toBe(true)
			expect(label.Text).toBe("Réglages")
			expect(Text.keyOf(label)).toBe("menu.settings")
			expect(label.TextSize).toBe(40)
			Text.raw(label, "Bob")
			expect(Text.keyOf(label)).toBe(nil)
			TvAudit.setLanguage(h, "en")
			expect(label.Text).toBe("Bob")
			clean(h)
		end)
	end)

	describe("Text_policy › le client entier (HUD, menu, panneaux construits)", function()
		local function texts(h)
			local out = {}
			for _, d in h.localPlayer.PlayerGui:GetDescendants() do
				if (d:IsA("TextLabel") or d:IsA("TextButton") or d:IsA("TextBox")) and d.Text ~= "" then
					local gui = d:FindFirstAncestorOfClass("ScreenGui")
					-- témoins (cachés de UI/Text, visibles du panneau TextProbe) : jamais stylés
					if (gui == nil or gui.Name ~= "TextWitness") and d:GetAttribute("TextProbe") ~= true then
						table.insert(out, d)
					end
				end
			end
			return out
		end

		for _, mode in { "respected", "ignored" } do
			it(
				"moteur « "
					.. mode
					.. " », Medium puis pire cas : aucun TextScaled, chaque texte suit la politique, libellés inchangés",
				function()
					reset()
					local h = TvAudit.client()
					engineTextService()
					local Text = TvAudit.mod(h, "UI.Text")
					local PC = TvAudit.mod(h, "UI.PanelController")
					-- tous les panneaux construits (et leurs textes posés)
					for _, panel in { "Ranch", "Squishydex", "Objectives", "Leaderboards", "Settings" } do
						PC.open(panel)
						h:settle(2)
						PC.closeAll()
						h:settle(1)
					end
					local list = texts(h)
					expect(#list > 100).toBe(true)
					local before = {}
					local bad = {}
					for _, d in list do
						if d.TextScaled then
							table.insert(bad, d:GetFullName() .. " : TextScaled")
						end
						local kind = Text.kind(d)
						if kind == nil then
							table.insert(
								bad,
								d:GetFullName() .. " « " .. d.Text .. " » : hors de la politique de UI/Text"
							)
						end
						before[d] = rendered(d)
					end
					expect(table.concat(bad, "\n")).toBe("")
					setPreferred(h, Text, WORST, mode)
					for _, d in list do
						local kind = Text.kind(d)
						local now = rendered(d)
						if kind == "sentence" then
							if math.abs(now - before[d] * WORST) > 1 then
								table.insert(
									bad,
									string.format(
										"%s : phrase %.1f → %.1f (×1,5 attendu)",
										d:GetFullName(),
										before[d],
										now
									)
								)
							end
						elseif math.abs(now - before[d]) > 1 then
							table.insert(
								bad,
								string.format(
									"%s « %s » : %.1f px à Medium, %.1f au pire cas",
									d:GetFullName(),
									d.Text,
									before[d],
									now
								)
							)
						end
					end
					expect(table.concat(bad, "\n")).toBe("")
					setPreferred(h, Text, 1, mode)
					for _, d in list do
						if rendered(d) ~= before[d] then
							table.insert(bad, d:GetFullName() .. " : taille changée après retour à Medium")
						end
					end
					expect(table.concat(bad, "\n")).toBe("")
					reset()
					clean(h)
				end
			)
		end
	end)
	describe("Text_policy › panneau TextProbe (Diagnostics, administrateurs)", function()
		for _, mode in { "respected", "ignored" } do
			it(
				"moteur « "
					.. mode
					.. " » : 6 témoins de 28, 36 et 48 px, libres et bornés, et leurs chiffres",
				function()
					reset()
					local h = TvAudit.client()
					engineTextService()
					local Text = TvAudit.mod(h, "UI.Text")
					local PC = TvAudit.mod(h, "UI.PanelController")
					h:fireClient("ReplicatedStorage.Remotes.DiagnosticsSnapshot", { tab = 0 })
					h:settle(1)
					PC.open("Diagnostics", "probe")
					h:settle(2)
					local page = h.localPlayer.PlayerGui:FindFirstChild("Page_probe", true)
					expect(page ~= nil).toBe(true)
					expect(page.Visible).toBe(true)
					local witnesses = {}
					for _, d in page:GetDescendants() do
						if d:GetAttribute("TextProbe") == true then
							table.insert(witnesses, d)
						end
					end
					expect(#witnesses).toBe(6)
					setPreferred(h, Text, WORST, mode)
					local state = page:FindFirstChild("State")
					expect(string.find(state.Text, "Largest", 1, true) ~= nil).toBe(true)
					for _, w in witnesses do
						local cell = w.Parent
						local bound = string.sub(cell.Name, 1, 5) == "Bound"
						local size = w.TextSize
						expect(Text.kind(w)).toBe(nil) -- jamais stylé ni compensé : le moteur tel quel
						local want = if bound and mode == "respected" then size else size * WORST
						expect(rendered(w)).toBe(want)
						local factor = cell:FindFirstChild("Factor")
						expect(factor.Text).toBe(if want == size then "×1.00" else "×1.50")
						local box = cell:FindFirstChild("DrawnBox")
						expect(box.Size.Y.Offset).toBe(size)
					end
					expect(page:FindFirstChild("Compensation").Text).toBe(
						if mode == "respected"
							then "Game labels compensated: ×1.00"
							else "Game labels compensated: ×1.50"
					)
					setPreferred(h, Text, 1, mode)
					PC.closeAll()
					reset()
					clean(h)
				end
			)
		end
	end)
end
