-- Pet Nexus: pociones, pociones gratis y Developer Products como funciones puras sobre los datos del jugador.
-- El servidor hace la parte de Roblox (MarketplaceService, guardado); aquí solo se decide qué se entrega.
-- 'now' es siempre os.time() (segundos Unix): las funciones no leen el reloj para poder probarlas.
local Config = require(script.Parent.Config)
local Stats = require(script.Parent.Stats)
local Progression = require(script.Parent.Progression)
local Economy = require(script.Parent.Economy)

local Purchases = {}

---------------------------------------------------------------- pociones
function Purchases.AddPotions(data, potions)
	for id, n in pairs(potions) do
		if Config.Potions.Types[id] and type(n) == "number" and n > 0 then
			data.Potions[id] = (data.Potions[id] or 0) + math.floor(n)
		end
	end
end

-- Usa una poción del inventario: suma Config.Potions.Duration a su tiempo. Errores: type, none
function Purchases.UsePotion(data, potionType)
	if type(potionType) ~= "string" or not Config.Potions.Types[potionType] then return false, "type" end
	if (data.Potions[potionType] or 0) < 1 then return false, "none" end
	data.Potions[potionType] -= 1
	data.PotionTime[potionType] = Stats.PotionRemaining(data, potionType) + Config.Potions.Duration
	return true, data.PotionTime[potionType]
end

-- Descuenta dt segundos a las pociones activas (solo se llama con el jugador conectado). Devuelve las que se acabaron.
function Purchases.TickPotions(data, dt)
	local ended = {}
	for id, t in pairs(data.PotionTime) do
		if type(t) == "number" and t > 0 then
			local left = math.max(0, t - dt)
			data.PotionTime[id] = left
			if left == 0 then table.insert(ended, id) end
		end
	end
	return ended
end

---------------------------------------------------------------- pociones gratis
local function day(now)
	return math.floor(now / 86400) -- día UTC
end

-- Segundos que faltan para poder reclamar (0 = ya se puede)
function Purchases.FreePotionsWait(data, now)
	return math.max(0, (data.FreePotions.NextClaim or 0) - now)
end

-- Saltos del cooldown usados hoy
function Purchases.FreePotionSkipsToday(data, now)
	local fp = data.FreePotions
	return fp.SkipDay == day(now) and (fp.SkipsUsed or 0) or 0
end

-- Reclama 1 poción de cada tipo. Error: cooldown (extra = segundos que faltan)
function Purchases.ClaimFreePotions(data, now)
	local wait = Purchases.FreePotionsWait(data, now)
	if wait > 0 then return false, "cooldown", wait end
	local potions = {}
	for id in pairs(Config.Potions.Types) do potions[id] = Config.FreePotions.Amount end
	Purchases.AddPotions(data, potions)
	data.FreePotions.NextClaim = now + Config.FreePotions.Cooldown
	return true, potions
end

-- ¿Tiene sentido ofrecer el salto? Errores: ready (no hay cooldown), limit (ya usó los saltos de hoy)
function Purchases.CanSkipFreePotions(data, now)
	if Purchases.FreePotionsWait(data, now) <= 0 then return false, "ready" end
	if Purchases.FreePotionSkipsToday(data, now) >= Config.FreePotions.SkipsPerDay then return false, "limit" end
	return true
end

-- Aplica un salto pagado: el cooldown se reinicia y cuenta para el límite del día
function Purchases.ApplyFreePotionSkip(data, now)
	local fp = data.FreePotions
	if fp.SkipDay ~= day(now) then
		fp.SkipDay = day(now)
		fp.SkipsUsed = 0
	end
	fp.SkipsUsed = (fp.SkipsUsed or 0) + 1
	fp.NextClaim = 0
end

---------------------------------------------------------------- recibos
function Purchases.ReceiptSeen(data, purchaseId)
	for _, id in ipairs(data.Receipts) do
		if id == purchaseId then return true end
	end
	return false
end

-- Recuerda el PurchaseId (solo los últimos Config.ReceiptHistory)
function Purchases.RecordReceipt(data, purchaseId)
	table.insert(data.Receipts, purchaseId)
	while #data.Receipts > Config.ReceiptHistory do
		table.remove(data.Receipts, 1)
	end
end

---------------------------------------------------------------- Developer Products
function Purchases.ProductKeyById(productId)
	if type(productId) ~= "number" or productId <= 0 then return nil end
	for key, def in pairs(Config.Products) do
		if def.Id == productId then return key end
	end
	return nil
end

-- Área más alta desbloqueada del mundo (mínimo 1)
local function progressArea(data, dim)
	return math.max(1, data.Unlocked[dim] or 0)
end

-- Cantidad que da un paquete de monedas/diamantes según el progreso del jugador en el mundo dim
function Purchases.PackAmount(key, data, dim)
	local def = Config.Products[key]
	local area = progressArea(data, dim)
	if def.Kind == "CoinPack" then
		return math.floor(def.Amount * Config.ZoneMultiplier(dim, area))
	elseif def.Kind == "DiamondPack" then
		return math.floor(def.Amount * (1 + Config.PackScale.DiamondPerArea * (area - 1)))
	end
	return 0
end

-- ¿Se puede ofrecer este producto ahora? (el servidor lo revisa antes de abrir la compra)
-- ctx = { Dim = mundo actual, Now = os.time() }.
-- Errores: product, unavailable, locked, rank (no es el siguiente), ready, limit, nocooldown (la meditación no se recarga)
function Purchases.CanOffer(data, key, ctx)
	local def = Config.Products[key]
	if not def then return false, "product" end
	if (def.Id or 0) <= 0 then return false, "unavailable" end
	if def.Kind == "RankSkip" then
		if not Stats.RankUnlocked(data) then return false, "locked" end
		if def.Rank ~= Stats.Rank(data) + 1 then return false, "rank" end
	elseif def.Kind == "FreePotionSkip" then
		return Purchases.CanSkipFreePotions(data, ctx.Now)
	elseif def.Kind == "EssenceSkip" then
		if (data.Meditation.Cooldown or 0) <= 0 then return false, "nocooldown" end
	elseif def.Kind == "CoinPack" then
		if not Config.Dimensions[ctx.Dim] or (data.Unlocked[ctx.Dim] or 0) < 1 then return false, "locked" end
	end
	return true
end

-- Entrega un producto (sin revisar recibos: eso lo hace ProcessReceipt). Devuelve info para el cliente.
function Purchases.Grant(data, key, ctx)
	local def = Config.Products[key]
	if def.Kind == "Potions" then
		Purchases.AddPotions(data, def.Potions)
		return { Kind = def.Kind, Potions = def.Potions }
	elseif def.Kind == "RankSkip" then
		local result, value = Progression.GrantRankSkip(data, def.Rank)
		return { Kind = def.Kind, Result = result, Rank = result == "rank" and value or nil, Diamonds = result == "compensated" and value or nil }
	elseif def.Kind == "CoinPack" then
		local amount = Purchases.PackAmount(key, data, ctx.Dim)
		data.Currency[ctx.Dim] = (data.Currency[ctx.Dim] or 0) + amount
		return { Kind = def.Kind, Dim = ctx.Dim, Amount = amount }
	elseif def.Kind == "DiamondPack" then
		local amount = Purchases.PackAmount(key, data, ctx.Dim)
		data.Diamonds = (data.Diamonds or 0) + amount -- comprados: cantidad exacta, sin multiplicador
		return { Kind = def.Kind, Amount = amount }
	elseif def.Kind == "FreePotionSkip" then
		Purchases.ApplyFreePotionSkip(data, ctx.Now)
		return { Kind = def.Kind }
	elseif def.Kind == "EssenceSkip" then
		-- si la recarga ya terminó mientras se compraba, el salto queda guardado para la próxima (no se pierde)
		if Economy.ReduceMeditationCooldown(data, math.huge) > 0 then
			return { Kind = def.Kind, Result = "skipped" }
		end
		data.Meditation.SkipCredits = (data.Meditation.SkipCredits or 0) + 1
		return { Kind = def.Kind, Result = "credit" }
	end
	error("producto sin entrega: " .. tostring(key))
end

-- Núcleo de ProcessReceipt: "unknown" (producto no configurado), "duplicate" (ya entregado) o "granted".
-- La entrega y el registro del PurchaseId van juntos en memoria; el servidor guarda enseguida.
function Purchases.ProcessReceipt(data, receipt, ctx)
	local key = Purchases.ProductKeyById(receipt.ProductId)
	if not key then return "unknown" end
	if Purchases.ReceiptSeen(data, receipt.PurchaseId) then return "duplicate", key end
	local info = Purchases.Grant(data, key, ctx)
	Purchases.RecordReceipt(data, receipt.PurchaseId)
	return "granted", key, info
end

return Purchases
