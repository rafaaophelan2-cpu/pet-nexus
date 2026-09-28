-- Economy: huevos (pity + suerte), diamantes, Esencia, mejoras, variantes y encantar una mascota
local H = require("./harness")
local M = H.modules()
local Economy, Stats, Config = M.Economy, M.Stats, M.Config

H.describe("Economy")

H.test("PickWeighted respeta pesos y nunca elige peso 0", function()
	local list = { { "a", 0 }, { "b", 1 }, { "c", 3 } }
	H.eq(Economy.PickWeighted(H.seq({ 0 }), list), "b")
	H.eq(Economy.PickWeighted(H.seq({ 0.24 }), list), "b")
	H.eq(Economy.PickWeighted(H.seq({ 0.26 }), list), "c")
	H.eq(Economy.PickWeighted(H.seq({ 0.999999 }), list), "c")
	H.eq(Economy.PickWeighted(H.seq({ 0.5 }), { { "x", 0 } }), nil)
end)

H.test("huevo con Luck = 1 sigue las probabilidades base (seed)", function()
	local rng, d = H.rng(12345), H.data(M)
	local counts, n = {}, 200000
	for _ = 1, n do
		d.Pity = {} -- sin pity para medir la distribución pura
		local pet = Economy.RollEgg(rng, "NexusEgg", d, 1)
		counts[pet] = (counts[pet] or 0) + 1
	end
	H.near(counts.Sprout / n, 0.60, 0.005, "Sprout")
	H.near(counts.Bunny / n, 0.30, 0.005, "Bunny")
	H.near(counts.Fox / n, 0.09, 0.003, "Fox")
	H.near(counts.Owl / n, 0.01, 0.001, "Owl")
end)

H.test("huevo con suerte sube Rare+ según la fórmula", function()
	local rng, d = H.rng(777), H.data(M)
	local owl, n = 0, 200000
	for _ = 1, n do
		d.Pity = {}
		if Economy.RollEgg(rng, "NexusEgg", d, 5) == "Owl" then owl += 1 end
	end
	H.near(owl / n, 5 / 104, 0.003)
end)

H.test("pity: a la apertura PityThreshold sale Rare+ garantizado y se reinicia", function()
	local d = H.data(M)
	local rng = H.seq({ 0 }) -- siempre la primera mascota con peso (Sprout)
	for i = 1, Config.PityThreshold - 1 do
		local pet, forced = Economy.RollEgg(rng, "NexusEgg", d, 1)
		H.eq(pet, "Sprout")
		H.eq(forced, false)
	end
	local pet, forced = Economy.RollEgg(rng, "NexusEgg", d, 1)
	H.eq(pet, "Owl")
	H.eq(forced, true)
	H.eq(d.Pity.NexusEgg, 0)
end)

H.test("EquipBest ordena por poder real (con variante) y respeta MaxEquipped", function()
	local d = H.data(M, {
		{ Id = "s", Name = "Sprout" }, { Id = "b", Name = "Bunny" }, { Id = "f", Name = "Fox", Variant = "Golden" },
		{ Id = "o", Name = "Owl" }, { Id = "fa", Name = "Fawn" }, { Id = "s2", Name = "Sprout", Variant = "Void" },
	})
	Economy.EquipBest(d)
	local equipped = {}
	for _, p in ipairs(d.Pets) do if p.Equipped then equipped[p.Id] = true end end
	H.ok(equipped.o and equipped.fa and equipped.f, "equipa Owl(9), Fawn(7), Fox dorado(6)")
	H.ok(not equipped.s2 and not equipped.b and not equipped.s)
	d.Upgrades.PetsEquipped = 1
	Economy.EquipBest(d)
	local n = 0
	for _, p in ipairs(d.Pets) do if p.Equipped then n += 1 end end
	H.eq(n, 4)
end)

H.test("AddDiamonds aplica el multiplicador de Diamonds", function()
	local d = H.data(M, { { Name = "Owl", Enchant = { Id = "Diamonds", Level = 5 } } })
	d.Upgrades.Diamonds = 4
	H.eq(Economy.AddDiamonds(d, 10), 35) -- 10 x 1.75 x 2
	H.eq(d.Diamonds, 35)
end)

H.test("RollDiamondDrop usa la probabilidad de cada rompible", function()
	H.eq(Economy.RollDiamondDrop(H.seq({ 0.999 }), "GiantChest"), Config.Breakables.GiantChest.Diamonds)
	H.eq(Economy.RollDiamondDrop(H.seq({ 0.5 }), "Coins"), 0)
	H.eq(Economy.RollDiamondDrop(H.seq({ 0.001 }), "Coins"), Config.Breakables.Coins.Diamonds)
	H.eq(Economy.RollDiamondDrop(H.seq({ 0 }), "NoExiste"), 0)
end)

H.test("GrantEssence guarda la fracción y la Esencia queda entera", function()
	local d = H.data(M)
	H.eq(Economy.GrantEssence(d, 1, 1.5), 1)
	H.eq(Economy.GrantEssence(d, 1, 1.5), 2)
	H.eq(Economy.GrantEssence(d, 1, 1.5), 1)
	H.eq(d.Essence, 4)
	H.near(d.Meditation.Carry, 0.5)
	H.eq(Economy.GrantEssence(d, 3, 1), 3)
	H.eq(d.Essence, 7)
end)

H.test("BuyUpgrade: orden, máximo, fondos y cobro", function()
	local d = H.data(M)
	H.eq(select(2, Economy.BuyUpgrade(d, "NoExiste", 1)), "upgrade")
	H.eq(select(2, Economy.BuyUpgrade(d, "WalkSpeed", 2)), "order")
	H.eq(select(2, Economy.BuyUpgrade(d, "WalkSpeed", 1.5)), "level")
	H.eq(select(2, Economy.BuyUpgrade(d, "WalkSpeed", 0 / 0)), "level")
	local ok, err, faltan = Economy.BuyUpgrade(d, "WalkSpeed", 1)
	H.eq(ok, false); H.eq(err, "funds"); H.eq(faltan, 500)
	d.Currency.Nexus = 600
	H.eq(Economy.BuyUpgrade(d, "WalkSpeed", 1), true)
	H.eq(d.Currency.Nexus, 100)
	H.eq(d.Upgrades.WalkSpeed, 1)
	H.eq(select(2, Economy.BuyUpgrade(d, "WalkSpeed", 1)), "owned")
	d.Upgrades.WalkSpeed = 4
	H.eq(select(2, Economy.BuyUpgrade(d, "WalkSpeed", 5)), "max")
end)

H.test("BuyUpgrade: Coins por dimensión y mejoras en diamantes", function()
	local d = H.data(M)
	d.Currency.Nexus = 1000
	H.eq(select(2, Economy.BuyUpgrade(d, "Coins", 1)), "dim")
	H.eq(select(2, Economy.BuyUpgrade(d, "Coins", 1, "Eden")), "dim") -- Eden aún no es jugable
	H.eq(Economy.BuyUpgrade(d, "Coins", 1, "Nexus"), true)
	H.eq(d.Upgrades.Coins.Nexus, 1)
	H.eq(d.Currency.Nexus, 0)
	d.Diamonds = 1000
	H.eq(Economy.BuyUpgrade(d, "AutoEnchant", 1), true)
	H.eq(d.Diamonds, 0)
	H.ok(Stats.HasUpgrade(d, "AutoEnchant"))
	local price, currency, curDim = Economy.UpgradeCost("Luck", 2)
	H.eq(price, 20000); H.eq(currency, "Dimension"); H.eq(curDim, "Nexus")
end)

H.test("EnchantPet cobra diamantes y reemplaza el encantamiento", function()
	local d = H.data(M, { { Id = "a", Name = "Owl", Enchant = { Id = "Haste", Level = 1 } } })
	H.eq(select(2, Economy.EnchantPet(d, "zzz", H.rng(1))), "pet")
	local ok, err, faltan = Economy.EnchantPet(d, "a", H.rng(1))
	H.eq(ok, false); H.eq(err, "funds"); H.eq(faltan, Config.EnchantCost)
	d.Diamonds = Config.EnchantCost * 2
	local ok2, ench, tier = Economy.EnchantPet(d, "a", H.rng(1))
	H.eq(ok2, true)
	H.eq(d.Diamonds, Config.EnchantCost)
	H.eq(d.Pets[1].Enchant, ench)
	H.ok(Config.Enchants[ench.Id] and Config.Enchants[ench.Id].Levels[ench.Level], "encantamiento válido")
	H.eq(Config.Enchants[ench.Id].Tier, tier)
end)

H.test("MatchesTarget", function()
	H.ok(Economy.MatchesTarget({ Id = "Coins", Level = 3 }, "Coins", 3))
	H.ok(Economy.MatchesTarget({ Id = "Coins", Level = 5 }, "Coins", 3))
	H.ok(not Economy.MatchesTarget({ Id = "Coins", Level = 2 }, "Coins", 3))
	H.ok(not Economy.MatchesTarget({ Id = "Luck", Level = 5 }, "Coins", 1))
	H.ok(not Economy.MatchesTarget(nil, "Coins", 1))
end)

local function foxes(n, variant)
	local list = {}
	for i = 1, n do list[i] = { Id = "f" .. i, Name = "Fox", Variant = variant } end
	return list
end

H.test("ConvertVariant: requisitos de la receta", function()
	local d = H.data(M, foxes(6))
	d.Currency.Nexus = 1e6
	local ids = { "f1", "f2", "f3", "f4", "f5" }
	H.eq(select(2, Economy.ConvertVariant(d, ids, "NoExiste", "Nexus")), "variant")
	H.eq(select(2, Economy.ConvertVariant(d, { "f1", "f2" }, "Golden", "Nexus")), "count")
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Golden", "Eden")), "machine")
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Golden", "Nexus")), "locked") -- la máquina está en el área 8
	d.Unlocked.Nexus = Config.MachineArea("Nexus", "Golden")
	H.eq(select(2, Economy.ConvertVariant(d, { "f1", "f1", "f2", "f3", "f4" }, "Golden", "Nexus")), "count") -- repetidas
	H.eq(select(2, Economy.ConvertVariant(d, { "f1", "f2", "f3", "f4", "zz" }, "Golden", "Nexus")), "pet")
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Rainbow", "Nexus")), "locked") -- Rainbow en el área 16
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Void", "Nexus")), "machine")  -- Void aún sin área
	d.Pets[2].Name = "Owl"
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Golden", "Nexus")), "mismatch")
	d.Pets[2].Name = "Fox"
	d.Pets[3].Variant = "Golden"
	H.eq(select(2, Economy.ConvertVariant(d, ids, "Golden", "Nexus")), "from")
	d.Pets[3].Variant = "Normal"
	d.Currency.Nexus = 10
	local ok, err, faltan = Economy.ConvertVariant(d, ids, "Golden", "Nexus")
	H.eq(err, "funds"); H.eq(faltan, Config.VariantRecipes.Golden.Price - 10)
	H.eq(#d.Pets, 6, "un intento fallido no toca las mascotas")
end)

H.test("ConvertVariant: conserva la primera (con encantamiento) y consume el resto", function()
	local d = H.data(M, foxes(6))
	d.Unlocked.Nexus = 8
	d.Currency.Nexus = 6000
	d.Pets[3].Enchant = { Id = "Coins", Level = 4 }
	local ok, kept = Economy.ConvertVariant(d, { "f3", "f1", "f2", "f4", "f5" }, "Golden", "Nexus")
	H.eq(ok, true)
	H.eq(kept.Id, "f3")
	H.eq(kept.Variant, "Golden")
	H.eq(kept.Enchant.Id, "Coins")
	H.eq(#d.Pets, 2)
	H.ok(Economy.FindPet(d, "f6") and Economy.FindPet(d, "f3"))
	H.eq(d.Currency.Nexus, 1000)
end)

return H
