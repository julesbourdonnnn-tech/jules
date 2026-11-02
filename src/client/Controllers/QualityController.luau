--!strict
-- QualityController (paquet client-world, docs/04 §13.3, GDD §12.9, §9.1).
-- Qualité adaptative : durée moyenne des images > 36 ms pendant 10 s → qualité réduite (détail × 0,6,
-- 40 squishies animés, particules × 0,3, lumières coupées au-delà de 60 studs, Highlight sur la
-- cible et les fuites seulement, pas de BlurEffect) ; remonte après 60 s sous 25 ms ; au plus un
-- changement par minute (pas de va-et-vient visible). Graphismes légers force la qualité réduite.
-- Analytique QualityReduced : intention ClientEvent("qualityReduced") à chaque descente adaptative
-- (débit client de Config/Intents, 20 par session au plus ; contrat v1.2).
-- Budgets PARTAGÉS (remarque A23) : chaque ressource a un quota par module, déjà multiplié par le
-- facteur de qualité ; la spec de chaque module vérifie que son stats() reste dans son quota.
-- Le temps des mesures est la somme des durées d'image (jamais l'horloge du jeu, que les commandes de
-- développement peuvent décaler) : déterministe dans le harnais.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 30) :: Folder
local Signal = require(Shared.Util.Signal)

local Client = script.Parent.Parent
local Prefs = require(Client.Util.Prefs)
local Util = require(Client.World.Util)

export type Budgets = {
	lodScale: number, -- distances de détail × 1 ou × 0,6
	animated: number, -- squishies animés à pleine cadence (80 ou 40)
	particles: number, -- facteur de particules (1 ou 0,3)
	highlights: number, -- Highlight au plus (12, ou 7 : cible + 6 fuites)
	lightRange: number, -- studs au-delà desquels les lumières sont coupées (math.huge ou 60)
	blur: boolean,
	-- quotas par module (déjà multipliés par le facteur de qualité) : particules ≤ 200 au total
	-- (vfx 120, chase 50, lighting 30 dont les flocons d'hiver ; × 0,3 en qualité réduite)
	particleQuota: { vfx: number, chase: number, lighting: number },
	-- Highlight ≤ 12 : target 1 (cible, RanchRenderer), chase 7 (6 fuites du Rush + Golden, ChaseRenderer),
	-- ranch 3 (Mythiques et Secrets les plus proches, RanchRenderer), réserve 1 (qualité réduite : 1 / 6 / 0)
	highlightQuota: { target: number, chase: number, ranch: number },
	-- lumières ≤ 24 : world 16 (lampadaires, LightingController / WorldService), ranch 4 (ranch local),
	-- squishies 4 (Légendaires+ les plus proches, RanchRenderer)
	lightQuota: { world: number, ranch: number, squishies: number },
}

local QualityController = {}

-- (reduced)
QualityController.Changed = Signal.new() :: Signal.Signal<boolean>

-- Réglages de la qualité adaptative (GDD §12.9, §9.1 ; budgets nommés, docs/04 §1 règle 5)
local TUNING = {
	SlowFrame = 0.036, -- s : image moyenne au-delà → lente
	SlowFor = 10, -- s de suite pour descendre
	FastFrame = 0.025, -- s : image moyenne en deçà → rapide
	FastFor = 60, -- s de suite pour remonter
	MinGap = 60, -- s entre deux changements
	Window = 1, -- s : fenêtre de la moyenne
	MaxReports = 20, -- ClientEvent par session (plafond du serveur)
}

local FULL: Budgets = {
	lodScale = 1,
	animated = 80,
	particles = 1,
	highlights = 12,
	lightRange = math.huge,
	blur = true,
	particleQuota = { vfx = 120, chase = 50, lighting = 30 },
	highlightQuota = { target = 1, chase = 7, ranch = 3 },
	lightQuota = { world = 16, ranch = 4, squishies = 4 },
}

local REDUCED_FACTOR = 0.3

local REDUCED: Budgets = {
	lodScale = 0.6,
	animated = 40,
	particles = REDUCED_FACTOR,
	highlights = 7,
	lightRange = 60,
	blur = false,
	particleQuota = {
		vfx = math.floor(120 * REDUCED_FACTOR),
		chase = math.floor(50 * REDUCED_FACTOR),
		lighting = math.floor(30 * REDUCED_FACTOR),
	},
	highlightQuota = { target = 1, chase = 6, ranch = 0 },
	lightQuota = { world = 16, ranch = 4, squishies = 4 },
}

local autoReduced = false
local lastEffective = false
local clockTime = 0 -- somme des durées d'image
local lastChangeAt = -math.huge
local windowSum, windowFrames = 0, 0
local slowFor, fastFor = 0, 0
local reports = 0
local started = false
local connections: { any } = {}

local function lowGraphics(): boolean
	return Util.safe("Prefs.lowGraphics", false, Prefs.lowGraphics)
end

local function copy(b: Budgets): Budgets
	return {
		lodScale = b.lodScale,
		animated = b.animated,
		particles = b.particles,
		highlights = b.highlights,
		lightRange = b.lightRange,
		blur = b.blur,
		particleQuota = table.clone(b.particleQuota),
		highlightQuota = table.clone(b.highlightQuota),
		lightQuota = table.clone(b.lightQuota),
	}
end

local function refresh()
	local now = autoReduced or lowGraphics()
	if now ~= lastEffective then
		lastEffective = now
		QualityController.Changed:Fire(now)
	end
end

local function report()
	if reports >= TUNING.MaxReports then
		return
	end
	if Util.send("ClientEvent", "qualityReduced") then
		reports += 1
	end
end

-- Une image de durée dt (exposé aux specs ; appelé par la connexion Heartbeat)
function QualityController._frame(dt: number)
	local d = Util.num(dt, 0, 0, 1)
	clockTime += d
	windowSum += d
	windowFrames += 1
	if windowSum < TUNING.Window then
		return
	end
	local avg = windowSum / math.max(1, windowFrames)
	local span = windowSum
	windowSum, windowFrames = 0, 0
	if avg > TUNING.SlowFrame then
		slowFor += span
		fastFor = 0
	elseif avg < TUNING.FastFrame then
		fastFor += span
		slowFor = 0
	else
		slowFor, fastFor = 0, 0
	end
	local canChange = clockTime - lastChangeAt >= TUNING.MinGap
	if not autoReduced and slowFor >= TUNING.SlowFor and canChange then
		autoReduced = true
		lastChangeAt = clockTime
		slowFor = 0
		report()
		refresh()
	elseif autoReduced and fastFor >= TUNING.FastFor and canChange then
		autoReduced = false
		lastChangeAt = clockTime
		fastFor = 0
		refresh()
	end
end

-- Création des états ; aucun yield long
function QualityController.Init()
	lastEffective = lowGraphics()
end

-- Connexions et boucles
function QualityController.Start()
	if started then
		return
	end
	started = true
	table.insert(
		connections,
		RunService.Heartbeat:Connect(function(dt: number)
			Util.guard("QualityController.frame", QualityController._frame, dt)
		end)
	)
	local ok, conn = pcall(function()
		return Prefs.Changed:Connect(function(key: string)
			if key == "lowGraphics" then
				refresh()
			end
		end)
	end)
	if ok then
		table.insert(connections, conn)
	end
	refresh()
end

-- Qualité réduite en vigueur
function QualityController.reduced(): boolean
	return autoReduced or lowGraphics()
end

-- Budgets du moment pour les rendus et les effets (copie : l'appelant ne peut rien abîmer)
function QualityController.budgets(): Budgets
	return copy(if QualityController.reduced() then REDUCED else FULL)
end

-- Remet l'état à zéro (specs)
function QualityController._reset()
	autoReduced = false
	clockTime = 0
	lastChangeAt = -math.huge
	windowSum, windowFrames = 0, 0
	slowFor, fastFor = 0, 0
	reports = 0
end

-- Coupe les connexions (fin de session, specs)
function QualityController._stop()
	for _, c in connections do
		c:Disconnect()
	end
	table.clear(connections)
	started = false
end

return QualityController
