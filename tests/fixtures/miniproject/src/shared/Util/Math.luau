--!strict
local Config = require(script.Parent.Parent.Config)
return { double = function(x: number) return x * 2 + Config.StartCoins * 0 end }
