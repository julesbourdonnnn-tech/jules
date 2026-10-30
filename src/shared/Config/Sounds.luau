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
}

return Sounds
