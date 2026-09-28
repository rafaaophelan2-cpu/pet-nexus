-- Migración de partidas (DataService.Reconcile): no romper datos existentes
local H = require("./harness")
local M = H.modules()
local DataService, Stats, Economy, Config = M.DataService, M.Stats, M.Economy, M.Config

H.describe("Migración de datos")

local OPTS = { StartWorld = "Nexus", RebirthOrder = { "Greenwood", "Nexus" }, StartLevel = 1 }

-- Partida de antes de las variantes (mascotas { Id, Name, Equipped }, rebirths como número)
local function saveV1()
	return {
		Currency = { Nexus = 500 },
		Pets = { { Id = "a", Name = "Owl", Equipped = true }, { Id = "b", Name = "Sprout", Equipped = false } },
		Unlocked = { Nexus = 2 },
		Essence = 10,
		Meditation = { Progress = 5, Cooldown = 12 },
		WorldsPaid = { Eden = true },
		Pity = { NexusEgg = 3 },
		Rebirths = 0,
		TotalHatched = 7,
	}
end

-- Partida de la rama cerebro-stats (variantes, encantamientos, mejoras, diamantes)
local function saveV2()
	local s = saveV1()
	s.Pets[1].Variant = "Golden"
	s.Pets[1].Enchant = { Id = "Coins", Level = 2 }
	s.Pets[2].Variant = "Normal"
	s.Upgrades = { WalkSpeed = 2, Coins = { Nexus = 1 } }
	s.Diamonds = 40
	s.Meditation.Carry = 0.5
	return s
end

H.test("partida v1: conserva todo y agrega lo nuevo", function()
	local d = DataService.Reconcile(saveV1(), OPTS)
	H.eq(d.Currency.Nexus, 500)
	H.eq(d.Unlocked.Nexus, 2)
	H.eq(d.WorldsPaid.Eden, true)
	H.eq(d.Essence, 10)
	H.eq(d.Meditation.Progress, 5)
	H.eq(d.Meditation.Cooldown, 12)
	H.eq(d.Meditation.Carry, 0)
	H.eq(d.Pity.NexusEgg, 3)
	H.eq(d.TotalHatched, 7)
	H.eq(d.Diamonds, 0)
	H.eq(d.Rank, 0)
	H.eq(d.Rebirths, nil, "el contador viejo desaparece")
	H.eq(next(d.RebirthsDone), nil, "0 rebirths viejos = ninguno hecho")
	H.eq(d.FreePotions.NextClaim, 0)
	H.eq(#d.Receipts, 0)
	H.eq(#d.Pets, 2)
	for _, pet in ipairs(d.Pets) do
		H.eq(pet.Variant, "Normal")
		H.eq(pet.Enchant, nil)
		H.eq(pet.Level, 1)
		H.eq(pet.XP, 0)
	end
	H.eq(d.Pets[1].Id, "a")
	H.eq(d.Pets[1].Equipped, true)
end)

H.test("partida v2: conserva variantes, encantamientos, mejoras y diamantes", function()
	local d = DataService.Reconcile(saveV2(), OPTS)
	H.eq(d.Pets[1].Variant, "Golden")
	H.eq(d.Pets[1].Enchant.Id, "Coins")
	H.eq(d.Pets[1].Enchant.Level, 2)
	H.eq(d.Upgrades.WalkSpeed, 2)
	H.eq(d.Upgrades.Coins.Nexus, 1)
	H.eq(d.Diamonds, 40)
	H.eq(d.Meditation.Carry, 0.5)
end)

H.test("el contador viejo de rebirths pasa a los primeros rebirths nuevos, sin reiniciar nada", function()
	local s = saveV1()
	s.Rebirths = 1
	local d = DataService.Reconcile(s, OPTS)
	H.eq(d.RebirthsDone.Greenwood, true)
	H.eq(d.RebirthsDone.Nexus, nil)
	H.eq(d.Currency.Nexus, 500)
	H.eq(d.Unlocked.Nexus, 2)
	s = saveV1()
	s.Rebirths = 5
	d = DataService.Reconcile(s, OPTS)
	H.ok(d.RebirthsDone.Greenwood and d.RebirthsDone.Nexus)
end)

H.test("el mundo inicial queda desbloqueado sin tocar el progreso", function()
	local d = DataService.Reconcile(saveV1(), { StartWorld = "Greenwood" })
	H.eq(d.Unlocked.Greenwood, 1)
	H.eq(d.Unlocked.Nexus, 2)
	local nuevo = DataService.Reconcile(DataService.Default(), { StartWorld = "Nexus" })
	H.eq(nuevo.Unlocked.Nexus, 1)
	H.eq(nuevo.Unlocked.Greenwood, nil, "un jugador nuevo no recibe mundos que no son el inicial")
end)

H.test("idempotente y limpia basura", function()
	local s = saveV2()
	s.Pets[2].Enchant = "basura"
	s.Pets[2].Level = "x"
	local once = DataService.Reconcile(s, OPTS)
	local twice = DataService.Reconcile(once, OPTS)
	H.eq(twice.Pets[1].Variant, "Golden")
	H.eq(twice.Pets[2].Enchant, nil)
	H.eq(twice.Pets[2].Level, 1)
	H.eq(twice.Upgrades.WalkSpeed, 2)
	H.eq(twice.Currency.Nexus, 500)
end)

H.test("las stats funcionan sobre una partida migrada", function()
	local s = saveV1()
	s.Rebirths = 1
	local d = DataService.Reconcile(s, OPTS)
	Economy.EquipBest(d)
	local st = Stats.Compute(d, "Nexus")
	H.eq(st.Coins, 2) -- Rebirth 1: +100%
	H.eq(st.MaxEquipped, 4) -- 3 + 1 del Rebirth 1
	H.near(st.Power, (9 + 1) * 1.01) -- nivel 1: +1%
	H.eq(Stats.RankUnlocked(d), true)
end)

H.test("Default devuelve tablas nuevas cada vez", function()
	local a, b = DataService.Default(), DataService.Default()
	a.Pets[1] = {}
	a.Upgrades.WalkSpeed = 3
	a.FreePotions.NextClaim = 99
	H.eq(#b.Pets, 0)
	H.eq(b.Upgrades.WalkSpeed, nil)
	H.eq(b.FreePotions.NextClaim, 0)
end)

return H
