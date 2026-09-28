-- Tirada de encantamientos con seed: determinismo, rangos, probabilidades y extensibilidad
local H = require("./harness")
local M = H.modules()
local Economy, Config = M.Economy, M.Config

H.describe("Encantamientos")

local function sequence(seed, n)
	local rng, out = H.rng(seed), {}
	for i = 1, n do
		local id, level, tier = Economy.RollEnchant(rng)
		out[i] = id .. ":" .. level .. ":" .. tier
	end
	return table.concat(out, ",")
end

H.test("misma seed = misma secuencia", function()
	H.eq(sequence(42, 200), sequence(42, 200))
	H.ok(sequence(42, 200) ~= sequence(43, 200), "seeds distintas deberían dar secuencias distintas")
end)

H.test("toda tirada es válida (id, nivel en rango, tier correcto)", function()
	local rng = H.rng(2024)
	for _ = 1, 20000 do
		local id, level, tier = Economy.RollEnchant(rng)
		local def = Config.Enchants[id]
		H.ok(def, "id inválido " .. tostring(id))
		H.ok(level >= 1 and level <= #def.Levels and level == math.floor(level), "nivel fuera de rango")
		H.eq(def.Tier, tier)
	end
end)

H.test("probabilidades exactas: suman 1, tier raro = 3%, niveles altos menos probables", function()
	local ch = Economy.EnchantChances()
	local total = 0
	for _, levels in pairs(ch.Enchants) do
		for _, p in pairs(levels) do total += p end
	end
	H.near(total, 1, 1e-12)
	H.near(ch.Tiers.Rare, 0.03, 1e-12)
	H.near(ch.Tiers.Normal, 0.97, 1e-12)
	for id, levels in pairs(ch.Enchants) do
		for lvl = 2, #Config.Enchants[id].Levels do
			H.ok(levels[lvl] < levels[lvl - 1], id .. ": nivel " .. lvl .. " debería ser menos probable")
		end
	end
	-- Coins V = 97% / 6 encantamientos normales x 4 / 100
	H.near(ch.Enchants.Coins[5], 0.97 / 6 * 4 / 100, 1e-12)
	-- Essence Master III = 3% x 15 / (45 + 27 + 15)
	H.near(ch.Enchants.EssenceMaster[3], 0.03 * 15 / 87, 1e-12)
end)

H.test("la frecuencia empírica con seed coincide con las probabilidades", function()
	local rng, n = H.rng(99), 200000
	local rare, coins1, haste3 = 0, 0, 0
	for _ = 1, n do
		local id, level, tier = Economy.RollEnchant(rng)
		if tier == "Rare" then rare += 1 end
		if id == "Coins" and level == 1 then coins1 += 1 end
		if id == "Haste" and level == 3 then haste3 += 1 end
	end
	local ch = Economy.EnchantChances()
	H.near(rare / n, 0.03, 0.002, "tier raro")
	H.near(coins1 / n, ch.Enchants.Coins[1], 0.003, "Coins I")
	H.near(haste3 / n, ch.Enchants.Haste[3], 0.002, "Haste III")
end)

H.test("extensible: tier y encantamiento nuevos entran solos en la tirada", function()
	local M2 = H.modules()
	M2.Config.EnchantTiers.Mythic = { Order = 3, Weight = 1 }
	M2.Config.EnchantTiers.Vacio = { Order = 4, Weight = 50 } -- sin encantamientos: se ignora
	M2.Config.Enchants.Midas = { Order = 8, Tier = "Mythic", Stat = "Coins", Name = "Midas", Levels = { 3, 5, 7, 9, 11, 13, 15 } }
	local ch = M2.Economy.EnchantChances()
	H.near(ch.Tiers.Mythic, 1 / 101, 1e-12)
	H.eq(ch.Tiers.Vacio, nil)
	-- 7 niveles con 5 pesos: los niveles 6 y 7 repiten el último peso
	H.near(ch.Enchants.Midas[7], ch.Enchants.Midas[5], 1e-12)
	local d = H.data(M2, { { Name = "Owl", Enchant = { Id = "Midas", Level = 7 } } })
	H.near(M2.Stats.Get(d, "Coins", "Nexus"), 16)
end)

H.test("etiqueta con números romanos", function()
	H.eq(Config.EnchantLabel("Coins", 3), "Coins III")
	H.eq(Config.EnchantLabel("EssenceMaster", 1), "Essence Master I")
end)

return H
