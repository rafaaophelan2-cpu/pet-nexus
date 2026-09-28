-- Pociones, pociones gratis (cooldown real + límite diario), recibos y Developer Products
local H = require("./harness")
local M = H.modules()
local Config, Stats, Purchases = M.Config, M.Stats, M.Purchases

local DAY = 86400
local T0 = 1790000000 -- un os.time() cualquiera

H.describe("Pociones")

H.test("usar suma 30 min y se acumula del mismo tipo", function()
	local d = H.data(M)
	H.eq(select(2, Purchases.UsePotion(d, "Luck")), "none")
	H.eq(select(2, Purchases.UsePotion(d, "Nada")), "type")
	H.eq(select(2, Purchases.UsePotion(d, 3)), "type")
	Purchases.AddPotions(d, { Luck = 2, Coins = 1, Inventada = 5, Diamonds = -3 })
	H.eq(d.Potions.Luck, 2); H.eq(d.Potions.Coins, 1)
	H.eq(d.Potions.Inventada, nil); H.eq(d.Potions.Diamonds, nil)
	H.eq(Purchases.UsePotion(d, "Luck"), true)
	H.eq(d.PotionTime.Luck, 1800)
	Purchases.TickPotions(d, 300)
	H.eq(d.PotionTime.Luck, 1500)
	Purchases.UsePotion(d, "Luck")
	H.eq(d.PotionTime.Luck, 3300, "se acumula")
	H.eq(d.Potions.Luck, 0)
	H.eq(Stats.Get(d, "Luck"), 2)
end)

H.test("el tiempo corre con TickPotions y avisa cuando se acaba", function()
	local d = H.data(M)
	Purchases.AddPotions(d, { Coins = 1, Diamonds = 1 })
	Purchases.UsePotion(d, "Coins")
	Purchases.UsePotion(d, "Diamonds")
	d.PotionTime.Diamonds = 5
	local ended = Purchases.TickPotions(d, 10)
	H.eq(#ended, 1); H.eq(ended[1], "Diamonds")
	H.eq(d.PotionTime.Diamonds, 0)
	H.eq(d.PotionTime.Coins, 1790)
	H.eq(Stats.Get(d, "Diamonds"), 1)
	H.eq(#Purchases.TickPotions(d, 10), 0, "no vuelve a avisar")
end)

H.describe("Pociones gratis")

H.test("reclamar da 1 de cada tipo y pone 3 h de cooldown real", function()
	local d = H.data(M)
	local ok, got = Purchases.ClaimFreePotions(d, T0)
	H.eq(ok, true)
	for id in pairs(Config.Potions.Types) do
		H.eq(d.Potions[id], 1, id)
		H.eq(got[id], 1)
	end
	local ok2, err, wait = Purchases.ClaimFreePotions(d, T0 + 60)
	H.eq(ok2, false); H.eq(err, "cooldown"); H.eq(wait, 3 * 3600 - 60)
	H.eq(Purchases.ClaimFreePotions(d, T0 + 3 * 3600), true, "pasadas 3 h (aunque haya estado desconectado)")
end)

H.test("salto: solo con cooldown activo y máximo 3 por día UTC", function()
	local d = H.data(M)
	H.eq(select(2, Purchases.CanSkipFreePotions(d, T0)), "ready")
	for k = 1, 3 do
		Purchases.ClaimFreePotions(d, T0 + k)
		H.eq(Purchases.CanSkipFreePotions(d, T0 + k), true, "salto " .. k)
		Purchases.ApplyFreePotionSkip(d, T0 + k)
		H.eq(Purchases.FreePotionsWait(d, T0 + k), 0)
	end
	Purchases.ClaimFreePotions(d, T0 + 10)
	H.eq(select(2, Purchases.CanSkipFreePotions(d, T0 + 10)), "limit")
	local nextDay = (math.floor(T0 / DAY) + 1) * DAY
	H.eq(Purchases.FreePotionSkipsToday(d, nextDay), 0)
	H.eq(Purchases.ClaimFreePotions(d, nextDay), true)
	H.eq(Purchases.CanSkipFreePotions(d, nextDay + 1), true, "al día siguiente se reinicia el límite")
end)

H.describe("Recibos y productos")

local function withIds(M2)
	local id = 1000
	for _, key in ipairs({ "Potion_Luck_3", "PotionBundle_10", "RankSkip1", "RankSkip2", "CoinPack3", "DiamondPack1", "FreePotionSkip",
		"EssenceCooldownSkip" }) do
		id += 1
		M2.Config.Products[key].Id = id
	end
end

H.test("mismo PurchaseId nunca se entrega dos veces", function()
	local M2 = H.modules()
	withIds(M2)
	local d = H.data(M2)
	local receipt = { ProductId = M2.Config.Products.Potion_Luck_3.Id, PurchaseId = "abc-1" }
	local ctx = { Dim = "Nexus", Now = T0 }
	H.eq((M2.Purchases.ProcessReceipt(d, receipt, ctx)), "granted")
	H.eq(d.Potions.Luck, 3)
	H.eq((M2.Purchases.ProcessReceipt(d, receipt, ctx)), "duplicate")
	H.eq(d.Potions.Luck, 3)
	H.eq((M2.Purchases.ProcessReceipt(d, { ProductId = 999999, PurchaseId = "x" }, ctx)), "unknown")
	H.eq((M2.Purchases.ProcessReceipt(d, { ProductId = 0, PurchaseId = "y" }, ctx)), "unknown", "Id 0 no es un producto")
end)

H.test("el historial de recibos se recorta sin perder los recientes", function()
	local d = H.data(M)
	for k = 1, Config.ReceiptHistory + 20 do Purchases.RecordReceipt(d, "r" .. k) end
	H.eq(#d.Receipts, Config.ReceiptHistory)
	H.ok(Purchases.ReceiptSeen(d, "r" .. (Config.ReceiptHistory + 20)))
	H.ok(not Purchases.ReceiptSeen(d, "r1"))
end)

H.test("bundles dan 10 / 25 de cada poción", function()
	local M2 = H.modules()
	withIds(M2)
	local d = H.data(M2)
	M2.Purchases.Grant(d, "PotionBundle_10", { Dim = "Nexus", Now = T0 })
	for id in pairs(Config.Potions.Types) do H.eq(d.Potions[id], 10) end
	M2.Purchases.Grant(d, "PotionBundle_25", { Dim = "Nexus", Now = T0 })
	for id in pairs(Config.Potions.Types) do H.eq(d.Potions[id], 35) end
end)

H.test("paquetes escalan con el progreso del mundo actual (mismo precio)", function()
	local d = H.data(M)
	d.Unlocked.Nexus = 1
	H.eq(Purchases.PackAmount("CoinPack3", d, "Nexus"), 10000)
	d.Unlocked.Nexus = 10
	local a10 = Purchases.PackAmount("CoinPack3", d, "Nexus")
	H.ok(a10 > 800000 and a10 < 1200000, "~1M en el área 10: " .. a10)
	local info = Purchases.Grant(d, "CoinPack3", { Dim = "Nexus", Now = T0 })
	H.eq(info.Amount, a10)
	H.eq(d.Currency.Nexus, a10)
	d.Unlocked.Nexus = 1
	H.eq(Purchases.PackAmount("DiamondPack1", d, "Nexus"), 100)
	d.Unlocked.Nexus = 5
	H.eq(Purchases.PackAmount("DiamondPack1", d, "Nexus"), 200)
	local before = d.Diamonds
	Purchases.Grant(d, "DiamondPack1", { Dim = "Nexus", Now = T0 })
	H.eq(d.Diamonds - before, 200, "sin multiplicador de diamantes")
end)

H.test("CanOffer revisa Id, rango siguiente y salto de pociones", function()
	local M2 = H.modules()
	withIds(M2)
	local P = M2.Purchases
	local d = H.data(M2)
	local ctx = { Dim = "Nexus", Now = T0 }
	H.eq(select(2, P.CanOffer(d, "Potion_Luck_1", ctx)), "unavailable", "Id 0")
	H.eq(select(2, P.CanOffer(d, "NoExiste", ctx)), "product")
	H.eq(P.CanOffer(d, "Potion_Luck_3", ctx), true)
	H.eq(select(2, P.CanOffer(d, "RankSkip1", ctx)), "locked")
	d.RebirthsDone.Greenwood = true
	H.eq(P.CanOffer(d, "RankSkip1", ctx), true)
	H.eq(select(2, P.CanOffer(d, "RankSkip2", ctx)), "rank")
	H.eq(select(2, P.CanOffer(d, "FreePotionSkip", ctx)), "ready")
	P.ClaimFreePotions(d, T0)
	H.eq(P.CanOffer(d, "FreePotionSkip", ctx), true)
	H.eq(select(2, P.CanOffer(d, "CoinPack3", { Dim = "Greenwood", Now = T0 })), "locked")
end)

H.test("recibo de salto de pociones reinicia el cooldown", function()
	local M2 = H.modules()
	withIds(M2)
	local d = H.data(M2)
	M2.Purchases.ClaimFreePotions(d, T0)
	local receipt = { ProductId = M2.Config.Products.FreePotionSkip.Id, PurchaseId = "skip-1" }
	H.eq((M2.Purchases.ProcessReceipt(d, receipt, { Dim = "Nexus", Now = T0 + 5 })), "granted")
	H.eq(M2.Purchases.FreePotionsWait(d, T0 + 5), 0)
	H.eq(M2.Purchases.FreePotionSkipsToday(d, T0 + 5), 1)
end)

H.test("salto de recarga de Esencia: solo durante la recarga; si ya terminó queda guardado", function()
	local M2 = H.modules()
	withIds(M2)
	local P = M2.Purchases
	local d = H.data(M2)
	local ctx = { Dim = "Nexus", Now = T0 }
	H.eq(select(2, P.CanOffer(d, "EssenceCooldownSkip", ctx)), "nocooldown")
	d.Meditation.Cooldown = 1200
	H.eq(P.CanOffer(d, "EssenceCooldownSkip", ctx), true)
	local id = M2.Config.Products.EssenceCooldownSkip.Id
	local status, key, info = P.ProcessReceipt(d, { ProductId = id, PurchaseId = "e-1" }, ctx)
	H.eq(status, "granted"); H.eq(key, "EssenceCooldownSkip")
	H.eq(info.Result, "skipped")
	H.eq(d.Meditation.Cooldown, 0)
	H.eq(d.Meditation.SkipCredits, 0)
	-- la recarga terminó entre el aviso y la compra: el salto no se pierde
	status, key, info = P.ProcessReceipt(d, { ProductId = id, PurchaseId = "e-2" }, ctx)
	H.eq(info.Result, "credit")
	H.eq(d.Meditation.SkipCredits, 1)
	H.eq((P.ProcessReceipt(d, { ProductId = id, PurchaseId = "e-2" }, ctx)), "duplicate")
	H.eq(d.Meditation.SkipCredits, 1)
end)

H.test("hook de misión: recorta la recarga sin pasarse de 0", function()
	local d = H.data(M)
	local Economy = M.Economy
	H.eq(Economy.ReduceMeditationCooldown(d, 900), 0, "sin recarga no recorta nada")
	d.Meditation.Cooldown = 1800
	H.eq(Economy.ReduceMeditationCooldown(d, Config.Meditation.MissionCooldownCut), 900)
	H.eq(d.Meditation.Cooldown, 900)
	H.eq(Economy.ReduceMeditationCooldown(d, 5000), 900)
	H.eq(d.Meditation.Cooldown, 0)
	H.eq(Economy.ReduceMeditationCooldown(d, -5), 0)
end)

H.test("todos los productos y gamepasses empiezan desactivados (Id = 0) y tienen entrega", function()
	local n = 0
	for key, def in pairs(Config.Products) do
		n += 1
		H.eq(def.Id, 0, key)
		H.ok(({ Potions = true, RankSkip = true, CoinPack = true, DiamondPack = true, FreePotionSkip = true, EssenceSkip = true })[def.Kind], key)
	end
	H.eq(n, 40)
	local p = 0
	for key, def in pairs(Config.GamePasses) do
		p += 1
		H.eq(def.Id, 0, key)
	end
	H.eq(p, 12)
	H.eq(Purchases.ProductKeyById(0), nil)
end)

return H
