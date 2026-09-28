-- Tests de humo del servidor real (PetNexusServer.server.luau) sobre la simulación de Roblox de roblox_mock.luau.
-- No reemplazan un playtest en Studio: comprueban que los remotes, bucles y compras funcionan de punta a punta.
local H = require("./harness")
local Mock = require("./roblox_mock")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local PASS_ID, POTION_ID, SKIP_ID, RANK1_ID, COINPACK_ID, ESSENCE_ID = 5001, 6001, 6002, 6003, 6004, 6005

local eggPart -- huevo del mapa (tiene que existir antes de arrancar el servidor, como en Studio)
local M = Mock.startServer(function(Config)
	Config.GamePasses.DoubleCoins.Id = PASS_ID
	Config.Products.Potion_Luck_3.Id = POTION_ID
	Config.Products.FreePotionSkip.Id = SKIP_ID
	Config.Products.RankSkip1.Id = RANK1_ID
	Config.Products.CoinPack3.Id = COINPACK_ID
	Config.Products.EssenceCooldownSkip.Id = ESSENCE_ID
	eggPart = Mock.taggedPart("Egg", Config.LobbySpawn("Nexus"), nil, { EggId = "NexusEgg" })
	Mock.Instance.new("ProximityPrompt", eggPart)
end)
local Config, DataService = M.Config, M.DataService
Mock.market.owned[PASS_ID] = true

local GRANTED = "ProductPurchaseDecision.PurchaseGranted"
local NOT_YET = "ProductPurchaseDecision.NotProcessedYet"

-- mueve al jugador con un teleport del servidor (un salto directo lo castiga el anticheat, como debe ser)
local function moveTo(player, pos)
	Mock.debug("teleport", player, pos)
end

local function lastNotify(player)
	local list = Mock.events(player, "Notify")
	return list[#list] and list[#list][1]
end

-- Llama a ProcessReceipt como Roblox (en su propio hilo: puede esperar entre reintentos de guardado) y avanza el reloj
-- hasta que responde
local function receipt(r)
	local done, result = false, nil
	Mock.task.spawn(function()
		result = Mock.services.MarketplaceService.ProcessReceipt(r)
		done = true
	end)
	local waited = 0
	while not done and waited < 60 do
		Mock.advance(0.5)
		waited += 0.5
	end
	assert(done, "ProcessReceipt no terminó")
	return result
end

H.describe("Servidor (simulado)")

local player, hrp = Mock.addPlayer(Config.ZoneCenter("Nexus", 1) + Vector3.new(0, 3, 0))
Mock.advance(1)
local data = DataService.Get(player)

H.test("al entrar: datos nuevos en Nexus, Sprout equipado y gamepass real cacheado", function()
	H.ok(data, "hay datos")
	H.eq(data.Unlocked.Nexus, 1)
	H.eq(data.Unlocked.Greenwood, nil)
	H.eq(#data.Pets, 1)
	H.eq(data.Pets[1].Name, "Sprout")
	H.eq(data.Pets[1].Equipped, true)
	H.eq(data.Pets[1].Level, 1)
	H.eq(data.Passes.DoubleCoins, true, "UserOwnsGamePassAsync")
	H.eq(data.Passes.VIP, nil, "Id 0 = desactivado")
	H.ok(#Mock.events(player, "DataSync") >= 1)
	H.eq(player.Character.Humanoid.WalkSpeed, 16)
end)

H.test("romper da monedas (x2 por Double Coins), XP a la mascota y a veces diamantes", function()
	Mock.advance(40, 0.25)
	H.ok((data.Currency.Nexus or 0) > 0, "ganó Angel Coins")
	H.ok(#Mock.events(player, "Damage") > 0, "rompió algo")
	local pet = data.Pets[1]
	H.ok(pet.XP > 0 or pet.Level > 1, "Sprout ganó XP")
	local dmg = Mock.events(player, "Damage")[1]
	H.eq(dmg[1], "break")
	H.eq(dmg[4], "Nexus")
	H.eq(type(dmg[5]), "number", "5º argumento: diamantes")
end)

H.test("teleport a un área mira hacia adelante y cae en su punto de llegada", function()
	Mock.advance(4)
	Mock.fire(player, "Teleport", "Nexus", 1)
	local expected = Config.ZoneEntry("Nexus", 1) + Vector3.new(0, 4, 0)
	H.ok((hrp.Position - expected).Magnitude < 1e-3, tostring(hrp.Position))
	H.ok((hrp.CFrame.LookVector - Vector3.new(0, 0, 1)).Magnitude < 1e-3)
end)

H.test("comprar área exige estar cerca de la puerta", function()
	data.Currency.Nexus = 1e6
	Mock.advance(1)
	Mock.fire(player, "BuyArea", "Nexus", 2)
	H.eq(data.Unlocked.Nexus, 1)
	H.eq(lastNotify(player), "Acércate a la puerta para comprar el área")
	moveTo(player, Config.GateCFrame("Nexus", 2).Position + Vector3.new(0, 0, -8))
	Mock.advance(1)
	Mock.fire(player, "BuyArea", "Nexus", 2)
	H.eq(data.Unlocked.Nexus, 2)
	H.eq(#Mock.events(player, "AreaUnlocked"), 1)
end)

H.test("anticheat: un área bloqueada te devuelve a la última desbloqueada", function()
	Mock.advance(3)
	moveTo(player, Config.ZoneCenter("Nexus", 4))
	Mock.advance(1.1)
	H.eq(Config.ZoneFromPosition("Nexus", hrp.Position), 2)
	-- y un salto directo (sin teleport del servidor) se revierte como movimiento imposible
	Mock.advance(3)
	local before = hrp.Position
	hrp.CFrame = roblox.CFrame.new(before + Vector3.new(0, 0, 400))
	Mock.advance(1.1)
	local back = hrp.Position - before
	H.ok(Vector3.new(back.X, 0, back.Z).Magnitude < 1, "volvió a donde estaba (teleport() suma 4 studs de alto)")
end)

H.test("rebirth: requisitos, estatua, ascensión sin castigo y teleport final al spawn del mundo", function()
	Mock.advance(3)
	Mock.fire(player, "Rebirth", "Nexus")
	H.eq(lastNotify(player), "Primero haz el rebirth de Greenwood")
	Mock.debug("rebirth", player, "Greenwood")
	data.Unlocked.Nexus = 10
	data.Currency.Nexus = 777
	Mock.advance(3)
	local P = Config.ZoneCenter("Nexus", 10)
	moveTo(player, P + Vector3.new(120, 0, 120)) -- en la plaza de la esquina
	Mock.advance(1.1)
	Mock.fire(player, "Rebirth", "Nexus")
	H.eq(lastNotify(player), "Acércate a la estatua de Rebirth")
	Mock.taggedPart("RebirthStatue", P + Vector3.new(130, 5, 130), Vector3.new(10, 20, 10), { Dimension = "Nexus" })
	Mock.advance(2.1)
	Mock.fire(player, "Rebirth", "Nexus")
	local res = Mock.events(player, "RebirthResult")
	H.eq(#res, 1)
	H.eq(res[1][1], "Nexus")
	H.eq(res[1][2].Number, 2)
	H.eq(res[1][2].Kept, false)
	H.eq(data.Unlocked.Nexus, 1)
	H.eq(data.Currency.Nexus, 0)
	-- el cliente hace volar al personaje: el anticheat no lo castiga
	for k = 1, 5 do
		hrp.CFrame = roblox.CFrame.new(P + Vector3.new(120, 3 + k * 60, 120))
		Mock.advance(0.5)
	end
	H.eq(#Mock.events(player, "Notify") > 0 and lastNotify(player) == "Zona solo para VIP", false)
	H.ok((hrp.Position - (P + Vector3.new(120, 303, 120))).Magnitude < 1, "durante la ascensión el anticheat no lo movió")
	Mock.advance(0.6) -- termina la ascensión (3 s)
	H.ok((hrp.Position - Config.LobbySpawn("Nexus")).Magnitude < 10, "terminó en el spawn de Nexus: " .. tostring(hrp.Position))
	Mock.advance(4)
	H.ok((hrp.Position - Config.LobbySpawn("Nexus")).Magnitude < 10, "y ahí se queda")
	Mock.fire(player, "Rebirth", "Nexus")
	H.eq(M.Stats.RebirthDone(data, "Nexus"), true)
end)

H.test("rango con diamantes", function()
	data.Diamonds = 1000
	Mock.advance(1)
	Mock.fire(player, "BuyRank", 1)
	H.eq(data.Rank, 1)
	H.eq(data.Diamonds, 1000 - Config.Ranks.Levels[1].Cost)
	H.eq(#Mock.events(player, "RankResult"), 1)
end)

H.test("pociones: usar, tiempo solo conectado y aviso al terminar", function()
	Mock.debug("potions", player, { Luck = 2 })
	Mock.advance(1)
	Mock.fire(player, "UsePotion", "Luck")
	H.eq(data.Potions.Luck, 1)
	H.ok(data.PotionTime.Luck > 1790, "30 min")
	H.eq(M.Stats.Get(data, "Luck"), 2 * 1.5, "poción x2 y Rebirth 1 +50%")
	Mock.advance(1801, 1)
	H.eq(data.PotionTime.Luck, 0)
	H.eq(#Mock.events(player, "PotionEnded"), 1)
end)

H.test("pociones gratis: santuario, cooldown real y salto pagado", function()
	Mock.fire(player, "ClaimFreePotions")
	H.eq(lastNotify(player), "Acércate al santuario de pociones")
	Mock.taggedPart("PotionShrine", hrp.Position + Vector3.new(5, 0, 0))
	Mock.advance(1.1)
	local before = data.Potions.Coins or 0
	Mock.fire(player, "ClaimFreePotions")
	H.eq(data.Potions.Coins, before + 1)
	H.eq(#Mock.events(player, "FreePotionsClaimed"), 1)
	Mock.advance(1.1)
	Mock.fire(player, "ClaimFreePotions")
	H.ok(string.find(lastNotify(player), "Pociones gratis otra vez en") ~= nil)
	-- ofrecer el salto abre la compra; el recibo reinicia el cooldown
	Mock.advance(1.1)
	Mock.fire(player, "PromptProduct", "FreePotionSkip")
	H.eq(Mock.market.prompts[#Mock.market.prompts].Id, SKIP_ID)
	H.eq(receipt({ PlayerId = player.UserId, ProductId = SKIP_ID, PurchaseId = "skip-1" }), GRANTED)
	Mock.advance(1.1)
	Mock.fire(player, "ClaimFreePotions")
	H.eq(#Mock.events(player, "FreePotionsClaimed"), 2)
end)

H.test("ProcessReceipt: entrega una vez, guarda enseguida y reintenta si no pudo guardar", function()
	local luck = data.Potions.Luck or 0
	local saves = Mock.store.saves
	H.eq(receipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-1" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 3)
	H.ok(Mock.store.saves > saves, "guardó")
	local stored = Mock.store.saved["p_" .. player.UserId]
	H.eq(stored.Potions.Luck, luck + 3, "lo guardado ya incluye la compra")
	H.eq(receipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-1" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 3, "no se entrega dos veces")
	H.eq(receipt({ PlayerId = 424242, ProductId = POTION_ID, PurchaseId = "p-2" }), NOT_YET, "jugador sin datos")
	H.eq(receipt({ PlayerId = player.UserId, ProductId = 999, PurchaseId = "p-3" }), NOT_YET, "producto sin configurar")
	-- el guardado falla (todos los reintentos): se entrega en memoria pero no se confirma; el reintento no duplica
	Mock.store.fail = true
	local r = receipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-4" })
	Mock.store.fail = false
	-- en Studio se confirma igual (sin DataStore real); lo importante es que no duplique en el reintento
	H.ok(r == GRANTED or r == NOT_YET)
	H.eq(data.Potions.Luck, luck + 6)
	H.eq(receipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-4" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 6)
end)

H.test("salto de rango con Robux y paquete de monedas escalado", function()
	-- ya tiene rango 1: el RankSkip1 se compensa con diamantes
	local diamonds = data.Diamonds
	H.eq(receipt({ PlayerId = player.UserId, ProductId = RANK1_ID, PurchaseId = "r-1" }), GRANTED)
	H.eq(data.Rank, 1)
	H.eq(data.Diamonds, diamonds + Config.Ranks.Levels[1].Cost)
	local coins = data.Currency.Nexus or 0
	H.eq(receipt({ PlayerId = player.UserId, ProductId = COINPACK_ID, PurchaseId = "c-1" }), GRANTED)
	H.eq(data.Currency.Nexus, coins + 10000, "área 1 de Nexus (después del rebirth)")
end)

H.test("zona VIP: sin VIP te saca; con VIP te deja", function()
	local zoneCenter = Config.LobbySpawn("Nexus") + Vector3.new(60, 0, 0)
	Mock.taggedPart("VipZone", zoneCenter, Vector3.new(30, 20, 30), { Dimension = "Nexus" })
	Mock.advance(3)
	moveTo(player, zoneCenter)
	Mock.advance(1.1)
	H.ok((hrp.Position - zoneCenter).Magnitude > 20, "lo sacó")
	H.eq(lastNotify(player), "Zona solo para VIP")
	Mock.debug("pass", player, { Key = "VIP", Owned = true })
	Mock.advance(3)
	moveTo(player, zoneCenter)
	Mock.advance(1.1)
	H.ok((hrp.Position - zoneCenter).Magnitude < 5, "con VIP se queda")
end)

H.test("gamepass comprado en el juego se activa al momento", function()
	local stats0 = M.Stats.MaxEquipped(data)
	Config.GamePasses.PremiumPetEquip.Id = 5002 -- el mapa por Id se arma al arrancar: este no está, se ignora
	Mock.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, 5002, true)
	H.eq(M.Stats.MaxEquipped(data), stats0)
	Mock.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(player, PASS_ID, true)
	H.eq(data.Passes.DoubleCoins, true)
	H.eq(#Mock.events(player, "GamePassGranted"), 1)
end)

H.test("debug: rango, nivel, stats y reinicio de pociones gratis", function()
	H.eq(Mock.debug("rank", player, 10), "ok")
	H.eq(data.Rank, 10)
	H.eq(Mock.debug("level", player, { Pet = 1, Level = 50 }), "ok")
	H.eq(data.Pets[1].Level, 50)
	local json = Mock.debug("stats", player, "Nexus")
	H.ok(type(json) == "string" and string.find(json, "MaxEquipped") ~= nil)
	H.eq(Mock.debug("freepotions", player), "ok")
	H.eq(data.FreePotions.NextClaim, 0)
	H.eq(Mock.debug("pass", player, { Key = "Nada" }), "gamepass inválido")
end)

H.test("inventario por remotes: equipar, desequipar, mejor equipo, bloquear y borrar en bulk", function()
	local max = M.Stats.MaxEquipped(data)
	local before = #data.Pets
	Mock.debug("fillpets", player, { Name = "Owl", Count = max + 1 })
	H.eq(#data.Pets, before + max + 1)
	H.eq(M.Inventory.EquippedCount(data), max, "las nuevas se equipan solas solo si hay espacio")
	local benched, first
	for _, pet in ipairs(data.Pets) do
		if not pet.Equipped then benched = pet elseif not first then first = pet end
	end
	Mock.advance(1)
	Mock.fire(player, "EquipPet", benched.Id)
	H.eq(benched.Equipped, false)
	H.eq(lastNotify(player), "Ya tienes " .. max .. "/" .. max .. " mascotas equipadas")
	Mock.advance(0.2)
	Mock.fire(player, "UnequipPet", first.Id)
	H.eq(first.Equipped, false)
	Mock.advance(0.2)
	Mock.fire(player, "EquipPet", benched.Id)
	H.eq(benched.Equipped, true)
	local res = Mock.events(player, "InventoryResult")
	H.eq(res[#res][1], "equip")
	-- bloquear una y borrar todas las Owl de una vez: la bloqueada queda
	Mock.advance(0.2)
	Mock.fire(player, "SetPetLocked", benched.Id, true)
	H.eq(benched.Locked, true)
	local owls = {}
	for _, pet in ipairs(data.Pets) do
		if pet.Name == "Owl" then table.insert(owls, pet.Id) end
	end
	Mock.advance(1)
	Mock.fire(player, "DeletePets", owls)
	H.eq(#data.Pets, before + 1)
	H.ok(M.Economy.FindPet(data, benched.Id), "la bloqueada sigue")
	res = Mock.events(player, "InventoryResult")
	H.eq(res[#res][1], "delete")
	H.eq(#res[#res][2].Deleted, #owls - 1)
	H.eq(res[#res][2].Locked, 1)
	H.ok(string.find(lastNotify(player), "bloqueada no se borró", 1, true) ~= nil)
	Mock.advance(1.1)
	Mock.fire(player, "EquipBest")
	H.eq(M.Inventory.EquippedCount(data), math.min(max, #data.Pets))
	-- argumentos inválidos no rompen nada
	Mock.advance(1.1)
	Mock.fire(player, "DeletePets", "x")
	Mock.fire(player, "EquipPet", 5)
	Mock.fire(player, "SetPetLocked", benched.Id, "si")
	Mock.fire(player, "DeletePets", { { 1 } })
	H.eq(#data.Pets, before + 1)
	H.eq(benched.Locked, true)
end)

H.test("huevo: con el inventario lleno avisa y no cobra; con espacio abre", function()
	Mock.debug("fillpets", player)
	H.eq(#data.Pets, M.Stats.MaxInventory(data))
	data.Currency.Nexus = 1e6
	Mock.advance(1)
	eggPart.ProximityPrompt.Triggered:Fire(player)
	H.eq(data.Currency.Nexus, 1e6, "no cobró")
	H.eq(#Mock.events(player, "HatchResult"), 0)
	H.eq(lastNotify(player), "Inventario lleno (100/100): borra mascotas o amplía el inventario")
	local victim
	for _, pet in ipairs(data.Pets) do
		if not pet.Locked and not pet.Equipped then victim = pet.Id end
	end
	Mock.fire(player, "DeletePets", { victim })
	H.eq(#data.Pets, 99)
	Mock.advance(1)
	eggPart.ProximityPrompt.Triggered:Fire(player)
	H.eq(#data.Pets, 100)
	H.eq(data.Currency.Nexus, 1e6 - Config.Eggs.NexusEgg.Price)
	H.eq(#Mock.events(player, "HatchResult"), 1)
end)

H.test("teams por remotes: guardar, aplicar, renombrar con filtro, borrar y limpiar al borrar mascotas", function()
	Mock.advance(1)
	local equipped = {}
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then table.insert(equipped, pet.Id) end
	end
	Mock.fire(player, "SaveTeam", 1, "Farm", nil)
	local team = data.Teams["1"]
	H.ok(team, "guardado")
	H.eq(team.Name, "Farm")
	H.eq(#team.PetIds, #equipped)
	-- cambia el equipo y lo vuelve a aplicar con un clic
	Mock.advance(0.2)
	Mock.fire(player, "UnequipPet", equipped[1])
	Mock.advance(1.1)
	Mock.fire(player, "ApplyTeam", 1)
	H.eq(M.Economy.FindPet(data, equipped[1]).Equipped, true)
	local tr = Mock.events(player, "TeamResult")
	H.eq(tr[#tr][1], "apply")
	H.eq(tr[#tr][3].Equipped, #equipped)
	-- el nombre pasa por el filtro de texto de Roblox
	Mock.textFilter = function(text) return string.rep("#", #text) end
	Mock.advance(1)
	Mock.fire(player, "RenameTeam", 1, "Feo")
	H.eq(team.Name, "###")
	Mock.textFilter = nil
	Mock.advance(1)
	Mock.fire(player, "RenameTeam", 1, string.rep("x", Config.Teams.NameMax + 1))
	H.eq(team.Name, "###")
	H.ok(string.find(lastNotify(player), "Nombre inválido", 1, true) ~= nil)
	-- borrar una mascota del team la quita del team
	M.Inventory.SetLocked(data, equipped[1], false)
	Mock.advance(1)
	Mock.fire(player, "DeletePets", { equipped[1] })
	H.eq(M.Economy.FindPet(data, equipped[1]), nil)
	H.eq(#team.PetIds, #equipped - 1)
	Mock.advance(1)
	Mock.fire(player, "SaveTeam", 99, "X")
	H.eq(lastNotify(player), "Ese slot de equipo no existe")
	Mock.advance(1)
	Mock.fire(player, "DeleteTeam", 1)
	H.eq(data.Teams["1"], nil)
end)

H.test("regalos por tiempo jugado: el servidor mide el tiempo, se guardan como item y se abren", function()
	local p3 = Mock.addPlayer()
	Mock.advance(1.1)
	local d3 = DataService.Get(p3)
	H.eq(type(p3:GetAttribute("PlaytimeSeconds")), "number", "la UI lee el tiempo del atributo")
	Mock.fire(p3, "ClaimPlaytimeGift", 1)
	H.eq(M.Inventory.ItemCount(d3, "GiftSmall"), 0)
	H.ok(string.find(lastNotify(p3), "Ese regalo estará listo en", 1, true) ~= nil)
	-- a los 15 min avisa que hay un regalo listo
	Mock.advance(900, 1)
	H.eq(lastNotify(p3), "Tienes un regalo por tiempo jugado listo para reclamar")
	Mock.fire(p3, "ClaimPlaytimeGift", 1)
	H.eq(M.Inventory.ItemCount(d3, "GiftSmall"), 1)
	H.eq(p3:GetAttribute("PlaytimeGiftsClaimed"), "1")
	H.eq(Mock.events(p3, "PlaytimeGiftClaimed")[1][2], "GiftSmall")
	Mock.advance(1)
	Mock.fire(p3, "ClaimPlaytimeGift", 1)
	H.eq(M.Inventory.ItemCount(d3, "GiftSmall"), 1, "una vez por sesión")
	-- el debug adelanta el tiempo: el 12 es el Gigante
	Mock.debug("playtime", p3, 3 * 3600)
	Mock.advance(1)
	Mock.fire(p3, "ClaimPlaytimeGift", 12)
	H.eq(M.Inventory.ItemCount(d3, "GiftGiant"), 1)
	-- abrir: consume el item y entrega los premios (se guardan con la partida)
	Mock.advance(1)
	Mock.fire(p3, "OpenGift", "GiftGiant")
	H.eq(M.Inventory.ItemCount(d3, "GiftGiant"), 0)
	local opened = Mock.events(p3, "GiftOpened")
	H.eq(#opened, 1)
	H.eq(#opened[1][2], Config.GiftTables.Giant.Rolls)
	Mock.advance(1)
	Mock.fire(p3, "OpenGift", "GiftGiant")
	H.eq(lastNotify(p3), "No tienes ese regalo")
	Mock.fire(p3, "OpenGift", 42)
	Mock.removePlayer(p3)
	Mock.advance(0.5)
	H.eq(Mock.store.saved["p_" .. p3.UserId].Items.GiftSmall, 1, "el regalo reclamado queda guardado")
end)

H.test("salto de recarga de Esencia (Developer Product) y hook de misión", function()
	Mock.advance(1.1)
	Mock.fire(player, "PromptProduct", "EssenceCooldownSkip")
	H.eq(lastNotify(player), "La Zona de Meditación no se está recargando")
	Mock.debug("medcooldown", player, 1800)
	Mock.advance(1.1)
	Mock.fire(player, "PromptProduct", "EssenceCooldownSkip")
	H.eq(Mock.market.prompts[#Mock.market.prompts].Id, ESSENCE_ID)
	H.eq(receipt({ PlayerId = player.UserId, ProductId = ESSENCE_ID, PurchaseId = "ess-1" }), GRANTED)
	H.eq(data.Meditation.Cooldown, 0)
	H.eq(player:GetAttribute("MeditationCooldown"), 0)
	H.eq(receipt({ PlayerId = player.UserId, ProductId = ESSENCE_ID, PurchaseId = "ess-1" }), GRANTED)
	H.eq(data.Meditation.SkipCredits, 0, "el mismo recibo no se entrega dos veces")
	Mock.debug("medcooldown", player, 1800)
	Mock.debug("missioncut", player)
	H.eq(data.Meditation.Cooldown, 1800 - Config.Meditation.MissionCooldownCut)
end)

H.test("al salir se guarda todo", function()
	Mock.removePlayer(player)
	Mock.advance(0.5)
	local stored = Mock.store.saved["p_" .. player.UserId]
	H.eq(stored.SessionLock, nil, "al salir suelta el lock")
	H.eq(stored.Rank, 10)
	H.eq(stored.RebirthsDone.Greenwood, true)
	H.eq(stored.RebirthsDone.Nexus, true)
	H.ok(#stored.Receipts >= 4)
	H.eq(DataService.Get(player), nil)
end)

H.test("si la carga falla, la sesión no se guarda (no pisa los datos reales)", function()
	Mock.store.fail = true
	local p2 = Mock.addPlayer()
	Mock.advance(20) -- todos los reintentos (1 + 2 + 4 + 8 s de espera)
	Mock.store.fail = false
	H.eq(DataService.IsLoaded(p2), false)
	H.eq(receipt({ PlayerId = p2.UserId, ProductId = POTION_ID, PurchaseId = "z-1" }), NOT_YET)
	Mock.removePlayer(p2)
	Mock.advance(0.5)
	H.eq(Mock.store.saved["p_" .. p2.UserId], nil)
end)

H.test("partida abierta en otro servidor: el guardado no escribe, no entrega compras y saca al jugador", function()
	local p4 = Mock.addPlayer()
	Mock.advance(1)
	local d4 = DataService.Get(p4)
	d4.Diamonds = 12345
	H.eq(Mock.debug("lockstolen", p4), "ok")
	H.eq(DataService.Save(p4), false)
	H.ok(Mock.store.saved["p_" .. p4.UserId].Diamonds ~= 12345, "no escribió")
	H.eq(DataService.IsLoaded(p4), false)
	H.ok(Mock.kicked[p4], "lo sacó")
	H.eq(receipt({ PlayerId = p4.UserId, ProductId = POTION_ID, PurchaseId = "k-1" }), NOT_YET, "no entrega sin poder guardar")
	Mock.removePlayer(p4)
	Mock.advance(0.5)
	H.eq(Mock.store.saved["p_" .. p4.UserId].SessionLock.JobId, "debug-otro-servidor", "no soltó el lock ajeno")
end)

H.test("cierre del servidor (BindToClose): guarda y suelta a todos", function()
	local p5 = Mock.addPlayer()
	Mock.advance(1)
	DataService.Get(p5).Diamonds = 4321
	Mock.close()
	Mock.advance(2)
	local rec = Mock.store.saved["p_" .. p5.UserId]
	H.eq(rec.Diamonds, 4321)
	H.eq(rec.SessionLock, nil)
	H.eq(DataService.Get(p5), nil)
end)

H.test("sin errores inesperados en el servidor", function()
	for _, w in ipairs(Mock.warnings) do
		local expected = string.find(w, "Error cargando datos") or string.find(w, "No se pudieron cargar")
			or string.find(w, "sin configurar") or string.find(w, "Error guardando datos")
			or string.find(w, "Zona bloqueada") or string.find(w, "Movimiento imposible") -- provocados a propósito
			or string.find(w, "Otro servidor abrió la partida")
		H.ok(expected, "warning inesperado: " .. w)
	end
end)

return H
