-- Inventario de mascotas, teams e items (Inventory.luau)
local H = require("./harness")
local M = H.modules()
local Config, Stats, Economy, Inventory = M.Config, M.Stats, M.Economy, M.Inventory

-- suma n mascotas sin equipar
local function fill(d, n, name)
	for _ = 1, n do
		table.insert(d.Pets, { Id = "f" .. (#d.Pets + 1), Name = name or "Sprout", Equipped = false, Variant = "Normal", Level = 0, XP = 0 })
	end
end

-- 4 mascotas: a (Owl) y b (Fox) equipadas; c (Bunny) y e (Sprout) sin equipar
local function four()
	return H.data(M, {
		{ Name = "Owl", Id = "a" }, { Name = "Fox", Id = "b" },
		{ Name = "Bunny", Id = "c", Equipped = false }, { Name = "Sprout", Id = "e", Equipped = false },
	})
end

H.describe("Inventario: límite")

H.test("base 100, mejora 120/150/200/250 y gamepasses +250/+500: máximo 1000", function()
	local d = H.data(M)
	H.eq(Stats.MaxInventory(d), 100)
	H.eq(Stats.Get(d, "MaxInventory"), 100)
	local expected = { 120, 150, 200, 250 }
	for lvl = 1, 4 do
		d.Upgrades.InventorySlots = lvl
		H.eq(Stats.MaxInventory(d), expected[lvl], "nivel " .. lvl)
	end
	d.Passes.InventoryPlus250 = true
	H.eq(Stats.MaxInventory(d), 500)
	d.Passes.InventoryPlus500 = true
	H.eq(Stats.MaxInventory(d), 1000)
	d.Upgrades.InventorySlots = 0
	H.eq(Stats.MaxInventory(d), 850)
	H.eq(Stats.Compute(d, "Nexus").MaxInventory, 850)
	H.eq(Stats.MaxEquipped(d), 3, "no cambia las mascotas equipadas")
	H.eq(Config.GamePasses.InventoryPlus250.Price, 199)
	H.eq(Config.GamePasses.InventoryPlus500.Price, 249)
end)

H.test("la mejora InventorySlots es global y se compra en orden como las demás", function()
	local d = H.data(M)
	d.Currency.Nexus = 1e9
	H.eq(#Config.Upgrades.InventorySlots.Levels, 4)
	H.eq(select(2, Economy.BuyUpgrade(d, "InventorySlots", 2)), "order")
	H.eq(Economy.BuyUpgrade(d, "InventorySlots", 1), true)
	H.eq(d.Currency.Nexus, 1e9 - Config.Upgrades.InventorySlots.Levels[1].Price)
	H.eq(Inventory.MaxPets(d), 120)
	H.eq(d.Upgrades.InventorySlots, 1, "global: no es por mundo")
end)

H.test("inventario lleno: no se reciben mascotas", function()
	local d = H.data(M, { { Name = "Owl" } })
	fill(d, 99)
	H.eq(Inventory.IsFull(d), true)
	H.eq(Inventory.Space(d), 0)
	local ok, err, max = Inventory.AddPet(d, "x", "Sprout")
	H.eq(ok, false); H.eq(err, "full"); H.eq(max, 100)
	H.eq(#d.Pets, 100)
	d.Passes.InventoryPlus250 = true
	H.eq(Inventory.AddPet(d, "x", "Sprout"), true)
	H.eq(Inventory.Space(d), 249)
	H.eq(select(2, Inventory.AddPet(d, "y", "NoExiste")), "name")
end)

H.test("una mascota nueva se equipa sola solo si queda un espacio libre", function()
	local d = H.data(M, { { Name = "Owl" }, { Name = "Fox" } })
	local _, pet = Inventory.AddPet(d, "n1", "Sprout")
	H.eq(pet.Equipped, true)
	local _, pet2 = Inventory.AddPet(d, "n2", "NexusDragon")
	H.eq(pet2.Equipped, false, "equipo lleno: aunque sea mejor no reemplaza a nadie")
	H.eq(Inventory.EquippedCount(d), 3)
end)

H.describe("Inventario: equipo")

H.test("equipar y desequipar respetan MaxEquipped", function()
	local d = H.data(M, { { Name = "Owl" }, { Name = "Fox" }, { Name = "Bunny" }, { Name = "Sprout", Equipped = false, Id = "s" } })
	local ok, err, max = Inventory.Equip(d, "s")
	H.eq(ok, false); H.eq(err, "slots"); H.eq(max, 3)
	H.eq(select(2, Inventory.Equip(d, "pet1")), "equipped")
	H.eq(select(2, Inventory.Equip(d, "nada")), "pet")
	H.eq(Inventory.Unequip(d, "pet1"), true)
	H.eq(select(2, Inventory.Unequip(d, "pet1")), "unequipped")
	H.eq(Inventory.Equip(d, "s"), true)
	H.eq(Inventory.EquippedCount(d), 3)
end)

H.test("EquipBest y ClampEquipped (al perder espacios salen las más débiles)", function()
	local d = H.data(M, { { Name = "Sprout" }, { Name = "Bunny", Equipped = false }, { Name = "NexusDragon", Equipped = false },
		{ Name = "Owl", Equipped = false } })
	H.eq(Inventory.EquipBest(d), 3)
	d.Passes.PremiumPetEquip = true
	H.eq(Inventory.EquipBest(d), 4)
	d.Passes.PremiumPetEquip = nil
	H.eq(Inventory.ClampEquipped(d), 1)
	H.eq(Inventory.EquippedCount(d), 3)
	H.eq(Economy.FindPet(d, "pet1").Equipped, false, "salió el Sprout (la más débil)")
	H.eq(Inventory.ClampEquipped(d), 0)
end)

H.describe("Inventario: bloqueo y borrado")

H.test("borrado en bulk: salta bloqueadas y las que no existen, desequipa y limpia teams", function()
	local d = four()
	H.eq(Inventory.SetLocked(d, "b", true), true)
	H.eq(Inventory.SaveTeam(d, 1, "Mi team", { "a", "b" }), true)
	local ok, info = Inventory.DeletePets(d, { "a", "b", "c", "zzz", "a" })
	H.eq(ok, true)
	H.eq(#info.Deleted, 2); H.eq(info.Locked, 1); H.eq(info.Missing, 1)
	H.eq(#d.Pets, 2)
	H.eq(Economy.FindPet(d, "a"), nil)
	H.ok(Economy.FindPet(d, "b"), "la bloqueada sigue")
	H.eq(Inventory.EquippedCount(d), 1, "la equipada borrada ya no cuenta")
	local team = Inventory.GetTeam(d, 1)
	H.eq(#team.PetIds, 1)
	H.eq(team.PetIds[1], "b")
end)

H.test("una bloqueada nunca se borra; siempre queda el mínimo; listas inválidas", function()
	local d = H.data(M, { { Name = "Owl", Id = "a" }, { Name = "Fox", Id = "b" } })
	Inventory.SetLocked(d, "a", true)
	local ok, err, info = Inventory.DeletePets(d, { "a" })
	H.eq(ok, false); H.eq(err, "none"); H.eq(info.Locked, 1)
	Inventory.SetLocked(d, "a", false)
	H.eq(Economy.FindPet(d, "a").Locked, nil)
	local ok2, err2, min = Inventory.DeletePets(d, { "a", "b" })
	H.eq(ok2, false); H.eq(err2, "min"); H.eq(min, Config.Inventory.MinPets)
	H.eq(#d.Pets, 2, "no borró nada")
	H.eq(select(2, Inventory.DeletePets(d, {})), "list")
	H.eq(select(2, Inventory.DeletePets(d, "a")), "list")
	H.eq(select(2, Inventory.DeletePets(d, { 5 })), "list")
	local big = {}
	for i = 1, 101 do big[i] = "x" .. i end
	H.eq(select(2, Inventory.DeletePets(d, big)), "list", "más ids que el máximo del inventario")
	H.eq(select(2, Inventory.SetLocked(d, "a", "si")), "value")
	H.eq(select(2, Inventory.SetLocked(d, "zz", true)), "pet")
end)

H.test("borrar 999 de 1000 mascotas de una vez", function()
	local d = H.data(M, { { Name = "Owl", Id = "keep" } })
	d.Passes.InventoryPlus250 = true
	d.Passes.InventoryPlus500 = true
	d.Upgrades.InventorySlots = 4
	fill(d, 999)
	H.eq(#d.Pets, 1000)
	H.eq(Inventory.IsFull(d), true)
	local ids = {}
	for i = 2, 1000 do ids[#ids + 1] = d.Pets[i].Id end
	local ok, info = Inventory.DeletePets(d, ids)
	H.eq(ok, true)
	H.eq(#info.Deleted, 999)
	H.eq(#d.Pets, 1)
	H.eq(d.Pets[1].Id, "keep")
end)

H.describe("Teams")

H.test("guardar el equipo actual o una lista, hasta MaxEquipped", function()
	local d = four()
	local ok, team = Inventory.SaveTeam(d, 1, nil, nil)
	H.eq(ok, true); H.eq(team.Name, "Equipo 1"); H.eq(#team.PetIds, 2)
	H.eq(d.Teams["1"], team, "clave texto (el DataStore no admite listas con huecos)")
	ok, team = Inventory.SaveTeam(d, 2, "  Farm \n  rápido ", { "c", "e", "a" })
	H.eq(ok, true); H.eq(team.Name, "Farm rápido")
	local okS, err, max = Inventory.SaveTeam(d, 3, "X", { "a", "b", "c", "e" })
	H.eq(okS, false); H.eq(err, "size"); H.eq(max, 3)
	H.eq(select(2, Inventory.SaveTeam(d, 3, "X", { "a", "a" })), "pets")
	H.eq(select(2, Inventory.SaveTeam(d, 3, "X", { "zzz" })), "pet")
	H.eq(select(2, Inventory.SaveTeam(d, 3, "X", {})), "empty")
	H.eq(select(2, Inventory.SaveTeam(d, 3, "X", "a")), "pets")
	H.eq(select(2, Inventory.SaveTeam(d, 0, "X")), "slot")
	H.eq(select(2, Inventory.SaveTeam(d, Config.Teams.Max + 1, "X")), "slot")
	H.eq(select(2, Inventory.SaveTeam(d, 1.5, "X")), "slot")
	H.eq(select(2, Inventory.SaveTeam(d, 3, string.rep("a", Config.Teams.NameMax + 1))), "name")
	H.eq(Inventory.SaveTeam(d, 3, string.rep("ñ", Config.Teams.NameMax)), true, "cuenta caracteres, no bytes")
	H.eq(select(2, Inventory.SaveTeam(d, 4, "   ")), "name")
	H.eq(select(2, Inventory.SaveTeam(d, 4, 42)), "name")
	-- sobrescribir sin nombre conserva el nombre
	Inventory.SaveTeam(d, 2, nil, { "a" })
	H.eq(d.Teams["2"].Name, "Farm rápido")
	H.eq(#d.Teams["2"].PetIds, 1)
end)

H.test("aplicar un team: equipa sus mascotas con un clic y omite las que ya no existen", function()
	local d = four()
	Inventory.SaveTeam(d, 1, "Team", { "c", "e", "a" })
	table.remove(d.Pets, 1) -- "a" desaparece sin pasar por DeletePets
	local ok, res = Inventory.ApplyTeam(d, 1)
	H.eq(ok, true)
	H.eq(res.Equipped, 2); H.eq(res.Missing, 1); H.eq(res.Skipped, 0)
	H.eq(Economy.FindPet(d, "b").Equipped, false)
	H.eq(Economy.FindPet(d, "c").Equipped, true)
	H.eq(Economy.FindPet(d, "e").Equipped, true)
	H.eq(#d.Teams["1"].PetIds, 2, "la que no existe salió del team")
	H.eq(select(2, Inventory.ApplyTeam(d, 2)), "empty")
	H.eq(select(2, Inventory.ApplyTeam(d, 9)), "slot")
end)

H.test("un team con más mascotas que el máximo actual equipa solo las que entran", function()
	local d = four()
	d.Passes.PremiumPetEquip = true
	H.eq(Inventory.SaveTeam(d, 1, "Grande", { "a", "b", "c", "e" }), true)
	d.Passes.PremiumPetEquip = nil
	local _, res = Inventory.ApplyTeam(d, 1)
	H.eq(res.Equipped, 3); H.eq(res.Skipped, 1)
	H.eq(Inventory.EquippedCount(d), 3)
end)

H.test("un team sin mascotas no toca el equipo actual", function()
	local d = H.data(M, { { Name = "Owl", Id = "a" }, { Name = "Fox", Id = "b" } })
	Inventory.SaveTeam(d, 1, "Viejo", { "b" })
	d.Pets[2] = nil
	local ok, err, missing = Inventory.ApplyTeam(d, 1)
	H.eq(ok, false); H.eq(err, "missing"); H.eq(missing, 1)
	H.eq(Economy.FindPet(d, "a").Equipped, true)
end)

H.test("renombrar y borrar teams", function()
	local d = H.data(M, { { Name = "Owl", Id = "a" } })
	Inventory.SaveTeam(d, 2)
	H.eq(Inventory.RenameTeam(d, 2, "Jefes"), true)
	H.eq(d.Teams["2"].Name, "Jefes")
	H.eq(select(2, Inventory.RenameTeam(d, 3, "X")), "empty")
	H.eq(select(2, Inventory.RenameTeam(d, 2, "")), "name")
	H.eq(select(2, Inventory.RenameTeam(d, 2, nil)), "name")
	H.eq(select(2, Inventory.RenameTeam(d, 99, "X")), "slot")
	H.eq(Inventory.DeleteTeam(d, 2), true)
	H.eq(d.Teams["2"], nil)
	H.eq(select(2, Inventory.DeleteTeam(d, 2)), "empty")
end)

H.test("las mascotas consumidas por una máquina de variantes salen de los teams", function()
	local d = H.data(M)
	for i = 1, 5 do
		table.insert(d.Pets, { Id = "g" .. i, Name = "Sprout", Equipped = i == 1, Variant = "Normal", Level = 0, XP = 0 })
	end
	Inventory.SaveTeam(d, 1, "Golden", { "g1", "g2", "g3" })
	d.Currency.Nexus = 1e6
	d.Unlocked.Nexus = 10
	H.eq(Economy.ConvertVariant(d, { "g1", "g2", "g3", "g4", "g5" }, "Golden", "Nexus"), true)
	H.eq(Inventory.PruneTeams(d), 2)
	H.eq(#d.Teams["1"].PetIds, 1)
	H.eq(d.Teams["1"].PetIds[1], "g1")
end)

H.describe("Items y vista para la UI")

H.test("items: sumar, quitar y solo ids de Config.Items", function()
	local d = H.data(M)
	H.eq(Inventory.AddItem(d, "GiftSmall", 2), true)
	H.eq(Inventory.ItemCount(d, "GiftSmall"), 2)
	H.eq(Inventory.AddItem(d, "NoExiste", 1), false)
	H.eq(Inventory.AddItem(d, "GiftSmall", 0), false)
	H.eq(Inventory.RemoveItem(d, "GiftSmall", 3), false)
	H.eq(Inventory.RemoveItem(d, "GiftSmall"), true)
	H.eq(Inventory.RemoveItem(d, "GiftSmall"), true)
	H.eq(d.Items.GiftSmall, nil, "en 0 desaparece")
	for id, def in pairs(Config.Items) do
		H.ok(Config.Rarities[def.Rarity], id .. ": rareza")
		H.ok(type(def.Name) == "string" and type(def.Icon) == "string" and type(def.Type) == "string", id)
	end
end)

H.test("vista: pestañas Pets / Items / Potions / Teams", function()
	local d = H.data(M, { { Name = "Sprout", Id = "s" }, { Name = "NexusDragon", Id = "n", Equipped = false } })
	Inventory.SetLocked(d, "n", true)
	Inventory.AddItem(d, "GiftGiant", 1)
	Inventory.AddItem(d, "GiftSmall", 3)
	M.Purchases.AddPotions(d, { Luck = 2 })
	Inventory.SaveTeam(d, 2, "Farm", { "s" })
	local v = Inventory.View(d)
	H.eq(#Inventory.Tabs, 4)
	H.eq(Inventory.Tabs[1], "Pets")
	H.eq(v.Pets.Count, 2); H.eq(v.Pets.Max, 100); H.eq(v.Pets.Equipped, 1); H.eq(v.Pets.MaxEquipped, 3)
	H.eq(v.Pets.List[1].Id, "s", "equipadas primero")
	H.eq(v.Pets.List[2].Locked, true)
	H.eq(v.Pets.List[2].Display, "Nexus Dragon")
	H.eq(v.Items[1].Id, "GiftSmall"); H.eq(v.Items[1].Count, 3)
	H.eq(v.Items[2].Id, "GiftGiant")
	H.eq(#v.Potions, 4)
	H.eq(v.Potions[1].Id, "Luck"); H.eq(v.Potions[1].Count, 2)
	H.eq(#v.Teams.List, Config.Teams.Max)
	H.eq(v.Teams.List[1].Empty, true)
	H.eq(v.Teams.List[2].Name, "Farm")
	H.eq(v.Teams.List[2].Missing, 0)
end)

return H
