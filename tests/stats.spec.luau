-- Stats: combinación de multiplicadores (base x mejora x encantamientos), variantes y suerte
local H = require("./harness")
local M = H.modules()
local Stats, Config = M.Stats, M.Config

H.describe("Stats")

H.test("jugador nuevo: todo en base", function()
	local d = H.data(M, { { Name = "Sprout" } })
	H.eq(Stats.Get(d, "Coins", "Nexus"), 1)
	H.eq(Stats.Get(d, "Diamonds"), 1)
	H.eq(Stats.Get(d, "Essence"), Config.Meditation.BaseMultiplier)
	H.eq(Stats.Get(d, "Luck"), 1)
	H.eq(Stats.Get(d, "WalkSpeed"), Config.BaseWalkSpeed)
	H.eq(Stats.Get(d, "PetSpeed"), 1)
	H.eq(Stats.Get(d, "BreakSpeed"), 1)
	H.eq(Stats.Get(d, "HatchSpeed"), 1)
	H.eq(Stats.Get(d, "MaxEquipped"), Config.MaxEquipped)
end)

H.test("mejoras: el bonus es el total del nivel, no se suman niveles", function()
	local d = H.data(M)
	d.Upgrades.WalkSpeed = 1
	H.near(Stats.Get(d, "WalkSpeed"), 16 * 1.10)
	d.Upgrades.WalkSpeed = 2
	H.near(Stats.Get(d, "WalkSpeed"), 16 * 1.25)
	d.Upgrades.WalkSpeed = 4
	H.near(Stats.Get(d, "WalkSpeed"), 16 * 1.75)
	d.Upgrades.Luck = 3
	H.near(Stats.Get(d, "Luck"), 1.5)
end)

H.test("mejora de Coins es por dimensión", function()
	local d = H.data(M)
	d.Upgrades.Coins = { Nexus = 2 }
	H.near(Stats.Get(d, "Coins", "Nexus"), 1.25)
	H.eq(Stats.Get(d, "Coins", "Eden"), 1)
	H.eq(Stats.Get(d, "Coins"), 1)
	H.eq(Stats.UpgradeLevel(d, "Coins", "Nexus"), 2)
	H.eq(Stats.UpgradeLevel(d, "Coins", "Eden"), 0)
end)

H.test("encantamientos: solo cuentan las mascotas equipadas", function()
	local d = H.data(M, {
		{ Name = "Owl", Enchant = { Id = "Coins", Level = 5 } },
		{ Name = "Fox", Enchant = { Id = "Coins", Level = 5 } },
		{ Name = "Bunny", Equipped = false, Enchant = { Id = "Coins", Level = 5 } },
	})
	H.near(Stats.Get(d, "Coins", "Nexus"), 3) -- 1 x (1 + 1.0 + 1.0)
end)

H.test("encantamiento de otra stat no afecta", function()
	local d = H.data(M, { { Name = "Owl", Enchant = { Id = "Luck", Level = 5 } } })
	H.eq(Stats.Get(d, "Coins", "Nexus"), 1)
	H.near(Stats.Get(d, "Luck"), 2)
end)

H.test("el bonus de encantamiento se multiplica por la variante", function()
	local golden = { Name = "Owl", Variant = "Golden", Level = 0, Enchant = { Id = "Coins", Level = 5 } }
	local void = { Name = "Fox", Variant = "Void", Level = 0, Enchant = { Id = "Coins", Level = 1 } }
	H.near(Stats.PetEnchantBonus(golden, "Coins"), 1.5)
	H.near(Stats.PetEnchantBonus(void, "Coins"), 0.6)
	local d = H.data(M, { { Name = "Owl", Variant = "Rainbow", Enchant = { Id = "EssenceMaster", Level = 3 } } })
	H.near(Stats.Get(d, "Essence"), 5) -- 1 x (1 + 2.0 x 2)
end)

H.test("combinación completa: base x (1 + mejora) x (1 + suma encantamientos)", function()
	local d = H.data(M, {
		{ Name = "Owl", Variant = "Golden", Enchant = { Id = "Coins", Level = 5 } }, -- +1.5
		{ Name = "Fox", Variant = "Void", Enchant = { Id = "Coins", Level = 1 } },   -- +0.6
		{ Name = "Fawn", Enchant = { Id = "Haste", Level = 3 } },                    -- otra stat
	})
	d.Upgrades.Coins = { Nexus = 2 }
	H.near(Stats.Get(d, "Coins", "Nexus"), 1.25 * (1 + 1.5 + 0.6))
	H.near(Stats.Get(d, "BreakSpeed"), 1.6)
end)

H.test("encantamiento inválido o nivel fuera de rango no suma", function()
	local d = H.data(M, {
		{ Name = "Owl", Enchant = { Id = "NoExiste", Level = 1 } },
		{ Name = "Fox", Enchant = { Id = "Haste", Level = 5 } }, -- Haste solo tiene 3 niveles
		{ Name = "Fawn", Enchant = "basura" },
	})
	H.eq(Stats.Get(d, "BreakSpeed"), 1)
end)

H.test("MaxEquipped suma la mejora PetsEquipped", function()
	local d = H.data(M)
	H.eq(Stats.MaxEquipped(d), 3)
	d.Upgrades.PetsEquipped = 1
	H.eq(Stats.MaxEquipped(d), 4)
	H.ok(not Stats.HasUpgrade(d, "AutoEnchant"))
	d.Upgrades.AutoEnchant = 1
	H.ok(Stats.HasUpgrade(d, "AutoEnchant"))
end)

H.test("poder real con variante (los rebirths ya no dan poder)", function()
	H.near(Stats.PetPower({ Name = "Owl", Variant = "Golden", Level = 0 }), 13.5)
	H.near(Stats.PetPower({ Name = "NexusDragon", Variant = "Void", Level = 0 }), 450)
	H.eq(Stats.PetPower({ Name = "Owl", Level = 0 }), 9) -- sin Variant = Normal
	local d = H.data(M, { { Name = "Owl", Variant = "Rainbow" }, { Name = "Fox" }, { Name = "Bunny", Equipped = false } })
	d.RebirthsDone.Greenwood = true
	H.near(Stats.Power(d), 18 + 4)
end)

H.test("suerte: con Luck = 1 las probabilidades son las base", function()
	local c = Stats.EggChances(Config.Eggs.NexusEgg.Pets, 1)
	H.near(c.Sprout, 0.60, 1e-12)
	H.near(c.Bunny, 0.30, 1e-12)
	H.near(c.Fox, 0.09, 1e-12)
	H.near(c.Owl, 0.01, 1e-12)
end)

H.test("suerte: multiplica los pesos Rare+ y renormaliza", function()
	local c = Stats.EggChances(Config.Eggs.NexusEgg.Pets, 2)
	H.near(c.Owl, 2 / 101, 1e-12)      -- Rare: 1 x 2
	H.near(c.Fox, 9 / 101, 1e-12)      -- Uncommon: igual
	H.near(c.Sprout, 60 / 101, 1e-12)
	local c2 = Stats.EggChances(Config.Eggs.CottonEgg.Pets, 3)
	local total = 0
	for _, p in pairs(c2) do total += p end
	H.near(total, 1, 1e-12)
	H.near(c2.NexusDragon, 1.5 / (62 + 90 + 22.5 + 1.5), 1e-12)
end)

H.test("Compute devuelve todas las stats", function()
	local s = Stats.Compute(H.data(M, { { Name = "Owl" } }), "Nexus")
	for stat in pairs(Config.StatDefs) do H.ok(s[stat] ~= nil, "falta " .. stat) end
	H.eq(s.MaxEquipped, 3)
	H.eq(s.Power, 9)
end)

H.test("stat desconocida da error", function()
	H.ok(not pcall(Stats.Get, H.data(M), "NoExiste"))
end)

return H
