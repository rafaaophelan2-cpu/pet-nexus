-- Migración de partidas (DataService.Reconcile): no romper datos existentes
local H = require("./harness")
local M = H.modules()
local DataService, Stats, Economy = M.DataService, M.Stats, M.Economy

H.describe("Migración de datos")

-- Forma de una partida guardada antes de este cambio (mascotas { Id, Name, Equipped })
local function oldSave()
	return {
		Currency = { Nexus = 500 },
		Pets = { { Id = "a", Name = "Owl", Equipped = true }, { Id = "b", Name = "Sprout", Equipped = false } },
		Unlocked = { Nexus = 2 },
		Essence = 10,
		Meditation = { Progress = 5, Cooldown = 12 },
		WorldsPaid = {},
		Pity = { NexusEgg = 3 },
		Rebirths = 1,
		TotalHatched = 7,
	}
end

H.test("partida vieja: conserva todo y agrega lo nuevo", function()
	local d = DataService.Reconcile(oldSave())
	H.eq(d.Currency.Nexus, 500)
	H.eq(d.Unlocked.Nexus, 2)
	H.eq(d.Essence, 10)
	H.eq(d.Meditation.Progress, 5)
	H.eq(d.Meditation.Cooldown, 12)
	H.eq(d.Meditation.Carry, 0)
	H.eq(d.Pity.NexusEgg, 3)
	H.eq(d.Rebirths, 1)
	H.eq(d.TotalHatched, 7)
	H.eq(d.Diamonds, 0)
	H.eq(type(d.Upgrades), "table")
	H.eq(#d.Pets, 2)
	for _, pet in ipairs(d.Pets) do
		H.eq(pet.Variant, "Normal")
		H.eq(pet.Enchant, nil)
	end
	H.eq(d.Pets[1].Id, "a")
	H.eq(d.Pets[1].Equipped, true)
end)

H.test("partida muy vieja (sin Esencia ni Meditación)", function()
	local d = DataService.Reconcile({ Currency = { Nexus = 1 }, Pets = {}, Unlocked = { Nexus = 1 } })
	H.eq(d.Essence, 0)
	H.eq(d.Meditation.Progress, 0)
	H.eq(d.Meditation.Cooldown, 0)
	H.eq(d.Diamonds, 0)
end)

H.test("idempotente y no pisa variantes, encantamientos ni mejoras", function()
	local save = oldSave()
	save.Pets[1].Variant = "Golden"
	save.Pets[1].Enchant = { Id = "Coins", Level = 2 }
	save.Pets[2].Enchant = "basura"
	save.Upgrades = { WalkSpeed = 2, Coins = { Nexus = 1 } }
	save.Diamonds = 40
	local d = DataService.Reconcile(DataService.Reconcile(save))
	H.eq(d.Pets[1].Variant, "Golden")
	H.eq(d.Pets[1].Enchant.Id, "Coins")
	H.eq(d.Pets[1].Enchant.Level, 2)
	H.eq(d.Pets[2].Enchant, nil)
	H.eq(d.Upgrades.WalkSpeed, 2)
	H.eq(d.Upgrades.Coins.Nexus, 1)
	H.eq(d.Diamonds, 40)
end)

H.test("las stats funcionan sobre una partida migrada", function()
	local d = DataService.Reconcile(oldSave())
	Economy.EquipBest(d)
	local s = Stats.Compute(d, "Nexus")
	H.eq(s.Coins, 1.5) -- 1 rebirth
	H.eq(s.MaxEquipped, 4)
	H.near(s.Power, (9 + 1) * 1.5)
end)

H.test("Default devuelve tablas nuevas cada vez", function()
	local a, b = DataService.Default(), DataService.Default()
	a.Pets[1] = {}
	a.Upgrades.WalkSpeed = 3
	H.eq(#b.Pets, 0)
	H.eq(b.Upgrades.WalkSpeed, nil)
end)

return H
