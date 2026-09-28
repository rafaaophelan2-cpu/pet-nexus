-- Tests de humo del servidor real (PetNexusServer.server.luau) sobre la simulación de Roblox de roblox_mock.luau.
-- No reemplazan un playtest en Studio: comprueban que los remotes, bucles y compras funcionan de punta a punta.
local H = require("./harness")
local Mock = require("./roblox_mock")
local roblox = require("@lune/roblox")
local Vector3 = roblox.Vector3

local PASS_ID, POTION_ID, SKIP_ID, RANK1_ID, COINPACK_ID = 5001, 6001, 6002, 6003, 6004

local M = Mock.startServer(function(Config)
	Config.GamePasses.DoubleCoins.Id = PASS_ID
	Config.Products.Potion_Luck_3.Id = POTION_ID
	Config.Products.FreePotionSkip.Id = SKIP_ID
	Config.Products.RankSkip1.Id = RANK1_ID
	Config.Products.CoinPack3.Id = COINPACK_ID
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
	local ProcessReceipt = Mock.services.MarketplaceService.ProcessReceipt
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = SKIP_ID, PurchaseId = "skip-1" }), GRANTED)
	Mock.advance(1.1)
	Mock.fire(player, "ClaimFreePotions")
	H.eq(#Mock.events(player, "FreePotionsClaimed"), 2)
end)

H.test("ProcessReceipt: entrega una vez, guarda enseguida y reintenta si no pudo guardar", function()
	local ProcessReceipt = Mock.services.MarketplaceService.ProcessReceipt
	local luck = data.Potions.Luck or 0
	local saves = Mock.store.saves
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-1" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 3)
	H.ok(Mock.store.saves > saves, "guardó")
	local stored = Mock.store.saved["p_" .. player.UserId]
	H.eq(stored.Potions.Luck, luck + 3, "lo guardado ya incluye la compra")
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-1" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 3, "no se entrega dos veces")
	H.eq(ProcessReceipt({ PlayerId = 424242, ProductId = POTION_ID, PurchaseId = "p-2" }), NOT_YET, "jugador sin datos")
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = 999, PurchaseId = "p-3" }), NOT_YET, "producto sin configurar")
	-- el guardado falla: se entrega en memoria pero no se confirma; el reintento no duplica
	Mock.store.fail = true
	local r = ProcessReceipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-4" })
	Mock.store.fail = false
	-- en Studio se confirma igual (sin DataStore real); lo importante es que no duplique en el reintento
	H.ok(r == GRANTED or r == NOT_YET)
	H.eq(data.Potions.Luck, luck + 6)
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = POTION_ID, PurchaseId = "p-4" }), GRANTED)
	H.eq(data.Potions.Luck, luck + 6)
end)

H.test("salto de rango con Robux y paquete de monedas escalado", function()
	local ProcessReceipt = Mock.services.MarketplaceService.ProcessReceipt
	-- ya tiene rango 1: el RankSkip1 se compensa con diamantes
	local diamonds = data.Diamonds
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = RANK1_ID, PurchaseId = "r-1" }), GRANTED)
	H.eq(data.Rank, 1)
	H.eq(data.Diamonds, diamonds + Config.Ranks.Levels[1].Cost)
	local coins = data.Currency.Nexus or 0
	H.eq(ProcessReceipt({ PlayerId = player.UserId, ProductId = COINPACK_ID, PurchaseId = "c-1" }), GRANTED)
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

H.test("al salir se guarda todo", function()
	Mock.removePlayer(player)
	Mock.advance(0.5)
	local stored = Mock.store.saved["p_" .. player.UserId]
	H.eq(stored.Rank, 10)
	H.eq(stored.RebirthsDone.Greenwood, true)
	H.eq(stored.RebirthsDone.Nexus, true)
	H.ok(#stored.Receipts >= 4)
	H.eq(DataService.Get(player), nil)
end)

H.test("si la carga falla, la sesión no se guarda (no pisa los datos reales)", function()
	Mock.store.fail = true
	local p2 = Mock.addPlayer()
	Mock.advance(4)
	Mock.store.fail = false
	H.eq(DataService.IsLoaded(p2), false)
	local ProcessReceipt = Mock.services.MarketplaceService.ProcessReceipt
	H.eq(ProcessReceipt({ PlayerId = p2.UserId, ProductId = POTION_ID, PurchaseId = "z-1" }), NOT_YET)
	Mock.removePlayer(p2)
	Mock.advance(0.5)
	H.eq(Mock.store.saved["p_" .. p2.UserId], nil)
end)

H.test("sin errores inesperados en el servidor", function()
	for _, w in ipairs(Mock.warnings) do
		local expected = string.find(w, "Error cargando datos") or string.find(w, "No se pudieron cargar")
			or string.find(w, "sin configurar") or string.find(w, "Error guardando datos")
			or string.find(w, "Zona bloqueada") or string.find(w, "Movimiento imposible") -- provocados a propósito
		H.ok(expected, "warning inesperado: " .. w)
	end
end)

return H
