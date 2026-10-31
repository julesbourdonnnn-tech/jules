--!strict
-- Hud/Counter — compteur de monnaie qui défile (GDD §9.2) :
--   * gain discret (parade, quête…) : défilement 0,5 s Quint Out de la valeur affichée vers la cible
--     (qui peut continuer d'avancer pendant le défilement) + pop UIScale 1,15 → 1 (Back Out 0,2 s) ;
--   * revenu passif : la valeur suit la cible image par image, SANS pop ;
--   * baisse (achat) : défilement court vers le bas, sans pop.
-- Le temps est fourni par l'appelant (somme des dt des images : mesure purement graphique), ce qui
-- rend le module déterministe en test. Le texte n'est réécrit que s'il change.

local Counter = {}
Counter.__index = Counter

export type Counter = {
	label: TextLabel,
	format: (number) -> string,
	shown: number,
	target: number,
	from: number,
	rollStart: number?,
	rollTime: number,
	lastText: string,
	onPop: ((Counter) -> ())?,
}

Counter.ROLL_TIME = 0.5
Counter.DROP_TIME = 0.25

local function quintOut(a: number): number
	return 1 - (1 - a) ^ 5
end

function Counter.new(label: TextLabel, format: (number) -> string, initial: number?): Counter
	local value = initial or 0
	local self = setmetatable({
		label = label,
		format = format,
		shown = value,
		target = value,
		from = value,
		rollStart = nil,
		rollTime = Counter.ROLL_TIME,
		lastText = "",
		onPop = nil,
	}, Counter)
	local c = (self :: any) :: Counter
	Counter.render(c)
	return c
end

-- Nouvelle cible. `roll` = gain/baisse discret (défilement) ; sinon dérive continue (revenu passif)
function Counter.set(self: Counter, value: number, now: number, roll: boolean?)
	if value ~= value or value == math.huge or value == -math.huge then
		return
	end
	if roll and value ~= self.target then
		self.from = self.shown
		self.rollStart = now
		self.rollTime = if value > self.target then Counter.ROLL_TIME else Counter.DROP_TIME
		local rising = value > self.target
		self.target = value
		if rising and self.onPop then
			self.onPop(self)
		end
		return
	end
	self.target = value
end

-- Fixe immédiatement la valeur (langue changée, premier instantané)
function Counter.snap(self: Counter, value: number)
	self.target = value
	self.shown = value
	self.from = value
	self.rollStart = nil
	self.lastText = ""
	Counter.render(self)
end

function Counter.isRolling(self: Counter): boolean
	return self.rollStart ~= nil
end

function Counter.step(self: Counter, now: number)
	local start = self.rollStart
	if start ~= nil then
		local alpha = math.clamp((now - start) / math.max(self.rollTime, 1e-3), 0, 1)
		self.shown = self.from + (self.target - self.from) * quintOut(alpha)
		if alpha >= 1 then
			self.rollStart = nil
			self.shown = self.target
		end
	else
		self.shown = self.target
	end
	Counter.render(self)
end

function Counter.render(self: Counter)
	local text = self.format(math.floor(self.shown + 1e-6))
	if text ~= self.lastText then
		self.lastText = text
		self.label.Text = text
	end
end

-- Force la réécriture du texte (changement de langue : format différent)
function Counter.refresh(self: Counter)
	self.lastText = ""
	Counter.render(self)
end

return Counter
