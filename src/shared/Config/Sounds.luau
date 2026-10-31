--!strict
-- Sons optionnels. Mettre un ID « rbxassetid://… » (Creator Store, sons publics) ;
-- une chaîne vide = son désactivé, le jeu reste entièrement jouable en silence.

export type SoundDef = { id: string, volume: number, pitch: number? }

local Sounds: { [string]: SoundDef } = {
	Click = { id = "", volume = 0.5 },
	Pop = { id = "", volume = 0.5 },
	Coin = { id = "", volume = 0.4 },
	Reward = { id = "", volume = 0.6 },
	LevelUp = { id = "", volume = 0.7 },
	Error = { id = "", volume = 0.5 },
	Whoosh = { id = "", volume = 0.4 },
	Music = { id = "", volume = 0.25 },
	-- Gameplay (GDD §9.4)
	Catch = { id = "", volume = 0.5 }, -- hauteur 1 + min(0,5 ; 0,01 × n) (client)
	CatchRare = { id = "", volume = 0.6 },
	Snip = { id = "", volume = 0.6 }, -- plus aigu côté coupeur
	Scatter = { id = "", volume = 0.5 },
	Bank = { id = "", volume = 0.6 },
	Dash = { id = "", volume = 0.5 },
	CometWarn = { id = "", volume = 0.7 },
	CometImpact = { id = "", volume = 0.7 },
	CometSwipe = { id = "", volume = 0.6 },
	BeaconStart = { id = "", volume = 0.6 },
	BeaconWin = { id = "", volume = 0.7 },
	WispPop = { id = "", volume = 0.5 },
	Supernova = { id = "", volume = 0.8 },
	Ping = { id = "", volume = 0.5 },
	Cheer = { id = "", volume = 0.6 },
}

return Sounds
