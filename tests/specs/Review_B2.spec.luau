--!nocheck
-- Relecture indépendante du lot B2 (écran Améliorations et HUD v2.0) : défauts réels trouvés par la
-- relecture, chacun montré rouge sur le code du lot avant sa correction (docs/04 §27.12, lignes B2-65
-- et suivantes). Vrai client console, instantanés fabriqués avec UpgradeMath.snapshot (profil témoin
-- v2, interrupteurs v2.0 ouverts DANS le test), réponses du serveur fabriquées. Zéro trace.
local TvAudit = require("../harness/TvAudit")
local UpgradeScreen = require("../harness/UpgradeScreen")

return function(T)
	local describe, it, expect = T.describe, T.it, T.expect
	local S = UpgradeScreen.new(T.Harness)

	local function celebrate(c, kind, userId, startedAt)
		c.h:fireClient("ReplicatedStorage.Remotes.Celebrate", {
			kind = kind,
			data = {
				userId = userId,
				startedAt = startedAt,
				burstAt = startedAt + 3.2,
				endsAt = startedAt + 7.5,
			},
		})
		c.h:settle(1)
	end

	describe("Review_B2 › ligne Tapis et Tapis Étoilé (GDD §10.7.5, D7, D8)", function()
		-- Défaut 1 : le Tapis Étoilé n'a de plafond qu'APRÈS le Tapis 12 (UpgradeMath.cap) ; ouvert au
		-- Tapis 11, l'écran figeait caps.star = 0 et lisait le Tapis 12 acheté écran ouvert comme un
		-- Tapis Étoilé coupé par son interrupteur : « 12/12 », MAX, « Tout est au maximum », jusqu'à la
		-- réouverture (le dénominateur doit toujours être 20, et la même ligne continue avec l'Étoilé)
		it(
			"Tapis 12 acheté écran ouvert : la ligne reste « 12/20 » et continue avec le Tapis Étoilé",
			function()
				local function at(snack)
					return function(p)
						p.tiles.snack = snack
						p.tiles.star = 0
						p.coins = 1e30
					end
				end
				local c = S.client({ snap = S.snap(1, at(11)) })
				local Format = TvAudit.mod(c.h, "UI.Format")
				S.open(c, "ranch")
				local row = c.Up._row("snack")
				local v = c.Up._view(row)
				expect(v.state).toBe("ready")
				expect(v.levelText).toBe(Format.level(11, 20))
				S.hold(c, row, 0.7)
				local sent = S.sent(c, "BuyUpgrade")
				expect(#sent).toBe(1)
				expect({ sent[1][1], sent[1][2], sent[1][3] }).toEqual({ "snack", 1, 11 })
				S.answer(c, sent[1], { to = 12, spent = 1, snap = S.snap(2, at(12)) })
				S.run(c, 2)
				v = c.Up._view(row)
				expect(v.levelText).toBe(Format.level(12, 20))
				expect(v.state).toBe("ready")
				expect(v.sendId).toBe("star")
				expect(v.expectedLevel).toBe(0)
				-- le maintien suivant achète le Tapis Étoilé (BuyUpgrade("star"), niveau attendu 0)
				S.hold(c, row, 0.7)
				sent = S.sent(c, "BuyUpgrade")
				expect(#sent).toBe(2)
				expect({ sent[2][1], sent[2][2], sent[2][3] }).toEqual({ "star", 1, 0 })
				S.clean(c, expect)
			end
		)
	end)

	describe("Review_B2 › prestige appliqué écran ouvert (D7, D28)", function()
		-- Défaut 2 : l'écran se fermait au début de SON spectacle, mais rouvert pendant le spectacle (avant
		-- l'éclatement à 3,2 s), il gardait r, Record R, A et les plafonds de l'ANCIENNE boucle avec les
		-- niveaux remis à zéro de la nouvelle : prix de l'ancienne boucle (r 12 au lieu de 13), « Prêt » ou
		-- « Il manque » faux jusqu'à la fermeture
		it(
			"rouvert pendant SON Grand Splorch : à l'éclatement, l'écran se ferme (jamais un prix de l'ancienne boucle)",
			function()
				local function rich(p)
					p.coins = 1e30
				end
				local function burst(p)
					p.R = 13
					p.bestR = 13
					p.tiles.decor = 0
					p.tiles.snack = 0
					p.tiles.gloves = 0
					p.coins = 50
				end
				local c = S.client({ snap = S.snap(1, rich) })
				local me = c.h.localPlayer.UserId
				S.open(c, "ranch")
				celebrate(c, "splorch", me, c.Clock.now())
				TvAudit.tick(c.h, 0.5)
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				-- rouvert pendant le spectacle (permis : D28 ne ferme qu'une fois par spectacle)
				S.open(c, "ranch")
				expect(c.PC.isOpen("Upgrades")).toBe(true)
				-- éclatement : Prestige.apply (r 12 → 13, Record R 13, boucle remise à zéro)
				S.patch(c, S.snap(2, burst))
				TvAudit.tick(c.h, 0.5)
				local fresh = S.UpgradeMath.price("decor", 0, 13, 0, 13)
				if c.PC.isOpen("Upgrades") then
					-- écran resté ouvert : il doit au moins montrer les prix de la nouvelle boucle
					expect(c.Up._view(c.Up._row("decor")).price).toBe(fresh)
				end
				expect(c.PC.isOpen("Upgrades")).toBe(false)
				-- réouverture : l'état neuf de la nouvelle boucle
				S.open(c, "ranch")
				expect(c.Up._view(c.Up._row("decor")).price).toBe(fresh)
				expect(c.Up._view(c.Up._row("decor")).state).toBe("need")
				S.clean(c, expect)
			end
		)
	end)

	describe("Review_B2 › effet réel des Décorations (N25, D30)", function()
		-- Défaut 3 : D30 veut l'A_bonus du revenu du HUD ; l'écran le calculait avec friends = 0, alors
		-- que le revenu compte les amis présents (+0,10 chacun) : avec un ami sur le serveur, « Revenu
		-- total +x % » montrait plus que l'effet réel du niveau suivant
		it(
			"un ami Roblox sur le serveur : le gain annoncé divise par l'A_bonus du revenu, ami compris",
			function()
				local c = S.client({ snap = S.snap(1, function(p)
					p.coins = 1e30
				end) })
				local friendId = c.h.localPlayer.UserId + 4242
				c.h:makeFriends(c.h.localPlayer, friendId)
				c.h:addPlayer({ userId = friendId, name = "Ami", spawn = false })
				c.h:settle(2)
				TvAudit.tick(c.h, 0.5)
				S.open(c, "ranch")
				local v = c.Up._view(c.Up._row("decor"))
				expect(v.state).toBe("ready")
				local State = TvAudit.mod(c.h, "Controllers.StateController")
				local Format = TvAudit.mod(c.h, "UI.Format")
				local Prefs = TvAudit.mod(c.h, "Util.Prefs")
				local Formulas = c.h:require("ReplicatedStorage.Shared.Logic.Formulas")
				local QuestRules = c.h:require("ReplicatedStorage.Shared.Logic.QuestRules")
				local function shown(friends)
					local A = Formulas.A({
						decor = (State.get("tiles") or {}).decor or 0,
						friends = friends,
						fame = State.get("fame") or 0,
						trophyBonus = Formulas.trophyBonus(State.get("trophies") or {}),
						goldenPages = QuestRules.goldenPages(State.get("dex") or {}),
					})
					return Format.decimal(S.Balance.Income.DecorBonus / A * 100, Prefs.language(), 1)
				end
				-- le cas n'a de sens que si l'ami change le nombre montré
				expect(shown(1) ~= shown(0)).toBe(true)
				expect(v.effect.label.vars.a).toBe(shown(1))
				S.clean(c, expect)
			end
		)
	end)
end
