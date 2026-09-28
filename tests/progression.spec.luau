-- Rebirth, rango, niveles de mascota y stats combinados con gamepasses y pociones
local H = require("./harness")
local M = H.modules()
local Config, Stats, Progression, Economy = M.Config, M.Stats, M.Progression, M.Economy

H.describe("Rebirth")

local function withGreenwood(areas)
	local d = H.data(M, { { Name = "Owl" } })
	d.Unlocked.Greenwood = areas
	d.Currency.Greenwood = 12345
	d.Currency.Nexus = 999
	return d
end

H.test("requisitos: área 10 del mundo, orden y una sola vez", function()
	local d = withGreenwood(9)
	H.eq(select(2, Progression.Rebirth(d, "Greenwood")), "area")
	H.eq(select(2, Progression.Rebirth(d, "Eden")), "dim")
	H.eq(select(2, Progression.Rebirth(d, 5)), "dim")
	d.Unlocked.Nexus = 10
	H.eq(select(2, Progression.Rebirth(d, "Nexus")), "order", "el rebirth 2 pide el 1")
	d.Unlocked.Greenwood = 10
	H.eq(Progression.Rebirth(d, "Greenwood"), true)
	H.eq(select(2, Progression.Rebirth(d, "Greenwood")), "done")
end)

H.test("reinicia solo la moneda y las áreas de ese mundo", function()
	local d = withGreenwood(14)
	d.Unlocked.Nexus = 3
	d.Diamonds = 50
	d.Upgrades.Coins = { Greenwood = 2 }
	local ok, info = Progression.Rebirth(d, "Greenwood")
	H.eq(ok, true)
	H.eq(info.Number, 1)
	H.eq(info.Kept, false)
	H.eq(d.Currency.Greenwood, 0)
	H.eq(d.Unlocked.Greenwood, 1)
	H.eq(d.Currency.Nexus, 999, "otro mundo intacto")
	H.eq(d.Unlocked.Nexus, 3, "otro mundo intacto")
	H.eq(d.Diamonds, 50)
	H.eq(d.Upgrades.Coins.Greenwood, 2, "las mejoras se conservan")
	H.eq(#d.Pets, 1)
end)

H.test("con Rebirth+ no reinicia nada pero da los beneficios", function()
	local d = withGreenwood(12)
	d.Passes.RebirthPlus = true
	local ok, info = Progression.Rebirth(d, "Greenwood")
	H.eq(ok, true)
	H.eq(info.Kept, true)
	H.eq(d.Currency.Greenwood, 12345)
	H.eq(d.Unlocked.Greenwood, 12)
	H.eq(Stats.Get(d, "Coins", "Greenwood"), 2)
end)

H.test("beneficios del Rebirth 1: +100% monedas (todas), +50% diamantes y suerte, +1 mascota, rango", function()
	local d = withGreenwood(10)
	H.eq(Stats.RankUnlocked(d), false)
	Progression.Rebirth(d, "Greenwood")
	H.eq(Stats.Get(d, "Coins", "Nexus"), 2)
	H.eq(Stats.Get(d, "Coins", "Greenwood"), 2)
	H.near(Stats.Get(d, "Diamonds"), 1.5)
	H.near(Stats.Get(d, "Luck"), 1.5)
	H.eq(Stats.MaxEquipped(d), 4)
	H.eq(Stats.RankUnlocked(d), true)
	H.eq(Stats.RebirthCount(d), 1)
end)

H.describe("Rango")

H.test("se desbloquea con el Rebirth 1 y se compra en orden con diamantes", function()
	local d = H.data(M)
	d.Diamonds = 1e6
	H.eq(select(2, Progression.BuyRank(d, 1)), "locked")
	d.RebirthsDone.Greenwood = true
	H.eq(select(2, Progression.BuyRank(d, 2)), "order")
	H.eq(select(2, Progression.BuyRank(d, 1.5)), "rank")
	H.eq(Progression.BuyRank(d, 1), true)
	H.eq(d.Diamonds, 1e6 - Config.Ranks.Levels[1].Cost)
	H.eq(select(2, Progression.BuyRank(d, 1)), "owned")
	d.Rank = 10
	H.eq(select(2, Progression.BuyRank(d, 11)), "max")
	d.Rank = 3
	d.Diamonds = 10
	local ok, err, faltan = Progression.BuyRank(d, 4)
	H.eq(err, "funds"); H.eq(faltan, Config.Ranks.Levels[4].Cost - 10)
end)

H.test("bonus del rango: total del nivel sobre Coins y Diamonds", function()
	local expected = { 0.05, 0.10, 0.15, 0.20, 0.30, 0.40, 0.55, 0.70, 0.85, 1.00 }
	local d = H.data(M)
	for r, b in ipairs(expected) do
		d.Rank = r
		H.near(Stats.Get(d, "Coins", "Nexus"), 1 + b, 1e-12, "rango " .. r)
		H.near(Stats.Get(d, "Diamonds"), 1 + b, 1e-12, "rango " .. r)
		H.eq(Stats.Get(d, "Luck"), 1)
	end
end)

H.test("salto de rango con Robux: siguiente rango o compensación en diamantes", function()
	local d = H.data(M)
	H.eq((Progression.GrantRankSkip(d, 1)), "compensated", "sin rebirth: no hay rango")
	H.eq(d.Diamonds, Config.Ranks.Levels[1].Cost)
	d.RebirthsDone.Greenwood = true
	H.eq((Progression.GrantRankSkip(d, 1)), "rank")
	H.eq(d.Rank, 1)
	local r, amount = Progression.GrantRankSkip(d, 5)
	H.eq(r, "compensated", "no se puede saltar de 1 a 5")
	H.eq(amount, Config.Ranks.Levels[5].Cost)
	H.eq(d.Rank, 1)
end)

H.describe("Niveles de mascota")

H.test("curva de XP y subida de nivel", function()
	H.eq(Progression.XPToNext(1), 50)
	H.eq(Progression.XPToNext(2), math.floor(50 * 1.12))
	H.eq(Progression.XPToNext(50), 0)
	local pet = { Name = "Owl", Level = 1, XP = 0 }
	H.eq(Progression.AddPetXP(pet, 49), 0)
	H.eq(Progression.AddPetXP(pet, 1), 1)
	H.eq(pet.Level, 2); H.eq(pet.XP, 0)
	H.eq(Progression.AddPetXP(pet, 56 + 62 + 10), 2) -- 56 (2->3) + 62 (3->4) + 10 sobra
	H.eq(pet.Level, 4); H.eq(pet.XP, 10)
end)

H.test("nivel máximo 50 = +50% a poder y encantamiento", function()
	local pet = { Name = "Owl", Level = 1, XP = 0, Enchant = { Id = "Coins", Level = 5 } }
	Progression.AddPetXP(pet, 1e9)
	H.eq(pet.Level, 50)
	H.eq(pet.XP, 0)
	H.near(Stats.PetPower(pet), 9 * 1.5)
	H.near(Stats.PetEnchantBonus(pet, "Coins"), 1.0 * 1.5)
	pet.Variant = "Golden"
	H.near(Stats.PetPower(pet), 9 * 1.5 * 1.5)
end)

H.test("romper da XP fija a CADA mascota equipada, doble con Double XP", function()
	local d = H.data(M, { { Name = "Owl", Level = 1 }, { Name = "Fox", Level = 1 }, { Name = "Bunny", Level = 1, Equipped = false } })
	local xp = Progression.GrantBreakXP(d, "Chest")
	H.eq(xp, Config.Breakables.Chest.XP)
	H.eq(d.Pets[1].XP, Config.Breakables.Chest.XP)
	H.eq(d.Pets[2].XP, Config.Breakables.Chest.XP, "no se divide")
	H.eq(d.Pets[3].XP, 0, "la no equipada no gana")
	d.Passes.DoubleXP = true
	H.eq(Progression.GrantBreakXP(d, "Coins"), 2 * Config.Breakables.Coins.XP)
	H.ok(Config.Breakables.GiantChest.XP > Config.Breakables.Coins.XP, "cofres dan más que monedas")
	local _, leveled = Progression.GrantBreakXP(d, "GiantChest")
	H.eq(leveled, true)
end)

H.describe("Stats con gamepasses y pociones")

H.test("gamepasses de la misma fuente se suman; fuentes distintas se multiplican", function()
	local d = H.data(M)
	d.Passes.DoubleCoins = true
	H.eq(Stats.Get(d, "Coins", "Nexus"), 2)
	d.Passes.VIP = true
	H.eq(Stats.Get(d, "Coins", "Nexus"), 3) -- +100% +100%
	H.eq(Stats.Get(d, "Diamonds"), 2) -- VIP
	d.RebirthsDone.Greenwood = true
	H.eq(Stats.Get(d, "Coins", "Nexus"), 6) -- x2 del rebirth
	d.Rank = 10
	H.eq(Stats.Get(d, "Coins", "Nexus"), 12) -- x2 del rango 10
	d.PotionTime.Coins = 60
	H.eq(Stats.Get(d, "Coins", "Nexus"), 24) -- x2 de la poción
	d.Upgrades.Coins = { Nexus = 4 }
	H.near(Stats.Get(d, "Coins", "Nexus"), 24 * 1.75)
	local b = Stats.Breakdown(d, "Coins", "Nexus")
	H.eq(b.GamePass, 3); H.eq(b.Rebirth, 2); H.eq(b.Rank, 2); H.eq(b.Potion, 2); H.eq(b.Upgrade, 1.75)
end)

H.test("suerte: Good Luck e Insane Luck se acumulan", function()
	local d = H.data(M)
	d.Passes.GoodLuck = true
	H.eq(Stats.Get(d, "Luck"), 2)
	d.Passes.InsaneLuck = true
	H.eq(Stats.Get(d, "Luck"), 3.5)
	d.PotionTime.Luck = 1
	H.eq(Stats.Get(d, "Luck"), 7)
	d.PotionTime.Luck = 0
	H.eq(Stats.Get(d, "Luck"), 3.5, "poción vencida no cuenta")
end)

H.test("mascotas equipadas: base 3 + mejora + rebirth + Premium + Deluxe", function()
	local d = H.data(M)
	H.eq(Stats.MaxEquipped(d), 3)
	d.Upgrades.PetsEquipped = 1
	d.RebirthsDone.Greenwood = true
	d.Passes.PremiumPetEquip = true
	H.eq(Stats.MaxEquipped(d), 3 + 1 + 1 + 2)
	d.Passes.DeluxePetEquip = true
	H.eq(Stats.MaxEquipped(d), 3 + 1 + 1 + 2 + 4)
end)

H.test("Double Essence, Double XP y poción de Hatch Speed", function()
	local d = H.data(M)
	d.Passes.DoubleEssence = true
	d.Passes.DoubleXP = true
	d.PotionTime.HatchSpeed = 10
	H.eq(Stats.Get(d, "Essence"), 2)
	H.eq(Stats.Get(d, "XP"), 2)
	H.eq(Stats.Get(d, "HatchSpeed"), 2)
end)

H.test("un gamepass que no existe en Config no da nada", function()
	local d = H.data(M)
	d.Passes.Inventado = true
	H.eq(Stats.Get(d, "Coins", "Nexus"), 1)
end)

H.describe("Mundo actual")

H.test("por posición, y si no, el mundo más avanzado desbloqueado", function()
	local roblox = require("@lune/roblox")
	local d = H.data(M)
	H.eq(Progression.CurrentWorld(d, Config.ZoneCenter("Nexus", 2)), "Nexus")
	H.eq(Progression.CurrentWorld(d, Config.Dimensions.Greenwood.LobbyCenter + roblox.Vector3.new(10, 3, 0)), "Greenwood")
	H.eq(Progression.CurrentWorld(d, roblox.Vector3.new(9999, 0, 9999)), "Nexus")
	d.Unlocked.Greenwood = 1
	H.eq(Progression.CurrentWorld(d, nil), "Nexus", "Nexus (Order 2) va después de Greenwood")
	d.Unlocked.Nexus = nil
	H.eq(Progression.CurrentWorld(d, nil), "Greenwood")
	H.ok(Economy ~= nil)
end)

return H
