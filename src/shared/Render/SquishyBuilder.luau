--!strict
-- SquishyBuilder (paquet world) — STUB du contrat (docs/04). Implémenter = remplacer chaque
-- error("TODO(…)") par le comportement décrit dans docs/04, SANS changer les signatures.
-- Modèles de squishies en formes simples, construits côté client à partir d'une ligne de données
-- (GDD §5.2) : corps écrasable (Ball X/Y/Z), haut de tête, yeux, joues, bouche, motif, 9 aspects de
-- mutation, étoiles, aura de rareté (couleur + forme), points d'attache (selle, tenue, tête), 3
-- niveaux de détail (12 pièces au plus en complet, 3, puis 1). Toutes les pièces : ancrées,
-- CanCollide = CanQuery = CanTouch = false, CastShadow = false. Réserve d'instances (pooling).

export type BuildSpec = {
	species: number,
	mutation: number,
	stars: number,
	displayScale: number,
	lod: number,
	outfit: string?,
	saddle: string?, -- couleur de selle (monture)
	rarityAura: boolean?, -- aura de rareté visible
}

export type Handle = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	offsets: { CFrame },
	spec: BuildSpec,
	lod: number,
}

export type Attachments = { saddle: CFrame, outfit: CFrame, head: CFrame }

local SquishyBuilder = {}

-- Construit (ou reprend dans la réserve) un modèle
function SquishyBuilder.build(spec: BuildSpec, parent: Instance?): Handle
	local _ = { spec, parent }
	error("TODO(world): SquishyBuilder.build")
end

-- Niveau de détail 1 (complet), 2 (corps + yeux), 3 (corps seul)
function SquishyBuilder.setLod(handle: Handle, lod: number)
	local _ = { handle, lod }
	error("TODO(world): SquishyBuilder.setLod")
end

-- Échelle affichée (SizeScale.display)
function SquishyBuilder.setScale(handle: Handle, displayScale: number)
	local _ = { handle, displayScale }
	error("TODO(world): SquishyBuilder.setScale")
end

-- Écrasement du corps (une écriture de Size), volume à peu près gardé
function SquishyBuilder.setSquash(handle: Handle, sx: number, sy: number, sz: number)
	local _ = { handle, sx, sy, sz }
	error("TODO(world): SquishyBuilder.setSquash")
end

-- Pièces et CFrames à passer à workspace:BulkMoveTo pour ce modèle
function SquishyBuilder.pose(handle: Handle, cframe: CFrame): ({ BasePart }, { CFrame })
	local _ = { handle, cframe }
	error("TODO(world): SquishyBuilder.pose")
end

-- Aspect de mutation (rendu fixe en Mouvement réduit)
function SquishyBuilder.setMutation(handle: Handle, mutation: number, reducedMotion: boolean)
	local _ = { handle, mutation, reducedMotion }
	error("TODO(world): SquishyBuilder.setMutation")
end

-- Arc d'étoiles (BillboardGui sous 60 studs)
function SquishyBuilder.setStars(handle: Handle, stars: number)
	local _ = { handle, stars }
	error("TODO(world): SquishyBuilder.setStars")
end

-- Points d'attache (selle, tenue, tête) en repère du modèle
function SquishyBuilder.attachments(handle: Handle): Attachments
	local _ = { handle }
	error("TODO(world): SquishyBuilder.attachments")
end

-- Rend le modèle à la réserve
function SquishyBuilder.release(handle: Handle)
	local _ = { handle }
	error("TODO(world): SquishyBuilder.release")
end

-- Nombre de pièces du modèle (≤ 12 en complet ; specs de budget)
function SquishyBuilder.partCount(spec: BuildSpec): number
	local _ = { spec }
	error("TODO(world): SquishyBuilder.partCount")
end

-- Recette pure (pièces, couleurs, tailles) d'une espèce, sans instance (tests)
function SquishyBuilder.recipe(species: number): { [string]: any }
	local _ = { species }
	error("TODO(world): SquishyBuilder.recipe")
end

return SquishyBuilder
