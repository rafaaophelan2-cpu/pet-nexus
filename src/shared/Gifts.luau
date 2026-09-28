-- Pet Nexus: regalos por tiempo jugado y apertura de regalos, como funciones puras.
-- La sesión de regalos NO se guarda (se reinicia al salir del juego): el servidor la crea al entrar con Gifts.NewSession
-- y mide el tiempo con su propio reloj (os.clock), así que el cliente no puede adelantarlo.
-- Los regalos reclamados sí se guardan: quedan como items en data.Items y se abren con Gifts.Open.
-- Ver Config.PlaytimeGifts (horario y etapas) y Config.GiftTables (premios).
local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Progression = require(script.Parent.Progression)
local Purchases = require(script.Parent.Purchases)
local Inventory = require(script.Parent.Inventory)

local Gifts = {}

---------------------------------------------------------------- horario y etapas
function Gifts.Count()
	return #Config.PlaytimeGifts.Minutes
end

-- Segundos seguidos de juego que pide el regalo n (nil si no existe)
function Gifts.Time(n)
	local m = Config.PlaytimeGifts.Minutes[n]
	return m and m * 60 or nil
end

-- Item que da el regalo n según su etapa (nil si no existe)
function Gifts.ItemFor(n)
	if not Gifts.Time(n) then return nil end
	for _, stage in ipairs(Config.PlaytimeGifts.Stages) do
		if n <= stage.Last then return stage.Item end
	end
	return nil
end

---------------------------------------------------------------- sesión (en memoria del servidor)
function Gifts.NewSession(now)
	return { Start = now, Offset = 0, Claimed = {} }
end

-- Segundos jugados en esta sesión (Offset solo lo cambia el comando de debug)
function Gifts.Elapsed(session, now)
	return math.max(0, now - session.Start + (session.Offset or 0))
end

-- Estado de los regalos a partir de los segundos jugados y los reclamados ({ [n] = true }).
-- Lo usa el cliente con los atributos PlaytimeSeconds / PlaytimeGiftsClaimed del jugador.
-- Devuelve { Seconds, Gifts = { { N, Item, Time, Claimed, Ready, Remaining }, ... } }
function Gifts.StatusFrom(seconds, claimed)
	local list = {}
	for n = 1, Gifts.Count() do
		local t = Gifts.Time(n)
		local done = claimed[n] == true
		list[n] = { N = n, Item = Gifts.ItemFor(n), Time = t, Claimed = done, Ready = not done and seconds >= t,
			Remaining = math.max(0, t - seconds) }
	end
	return { Seconds = seconds, Gifts = list }
end

function Gifts.Status(session, now)
	return Gifts.StatusFrom(Gifts.Elapsed(session, now), session.Claimed)
end

-- Regalos listos para reclamar
function Gifts.ReadyCount(session, now)
	local n = 0
	for _, g in ipairs(Gifts.Status(session, now).Gifts) do
		if g.Ready then n += 1 end
	end
	return n
end

-- Reclamados como texto "1,2,5" (atributo PlaytimeGiftsClaimed) y al revés
function Gifts.ClaimedText(session)
	local list = {}
	for n = 1, Gifts.Count() do
		if session.Claimed[n] then table.insert(list, tostring(n)) end
	end
	return table.concat(list, ",")
end

function Gifts.ParseClaimed(text)
	local set = {}
	for part in string.gmatch(text or "", "%d+") do set[tonumber(part)] = true end
	return set
end

-- Reclama el regalo n: lo guarda como item en data.Items. Devuelve true, itemId.
-- Errores: gift (n inválido), claimed (ya reclamado en esta sesión), wait (extra = segundos que faltan), item
function Gifts.Claim(session, data, n, now)
	if type(n) ~= "number" or n ~= math.floor(n) or not Gifts.Time(n) then return false, "gift" end
	if session.Claimed[n] then return false, "claimed" end
	local left = Gifts.Time(n) - Gifts.Elapsed(session, now)
	if left > 0 then return false, "wait", left end
	local itemId = Gifts.ItemFor(n)
	if not Inventory.AddItem(data, itemId, 1) then return false, "item" end
	session.Claimed[n] = true
	return true, itemId
end

---------------------------------------------------------------- apertura (sin suerte)
-- Tabla de premios del item (nil si no es un regalo)
function Gifts.TableOf(itemId)
	local def = type(itemId) == "string" and Config.Items[itemId]
	if not def or def.Type ~= "Gift" then return nil end
	return Config.GiftTables[def.Gift]
end

-- Mundo donde se entregan las monedas: el actual si está desbloqueado; si no, el más avanzado
local function rewardWorld(data, dim)
	if type(dim) == "string" and Config.Dimensions[dim] and (data.Unlocked[dim] or 0) >= 1 then return dim end
	return Progression.CurrentWorld(data, nil)
end

-- Escala de las monedas: la curva de recompensas en el área más alta desbloqueada del mundo (igual que CoinPack)
function Gifts.CoinScale(data, dim)
	return Config.ZoneMultiplier(dim, math.max(1, data.Unlocked[dim] or 0))
end

-- Cantidad real de un premio (solo Coins se escala; nada usa stats del jugador)
function Gifts.RewardAmount(reward, data, dim)
	if reward.Kind == "Coins" then
		return math.floor(reward.Amount * Gifts.CoinScale(data, dim))
	end
	return reward.Amount
end

-- Premios posibles y su probabilidad por tirada (para mostrarlos al pasar el mouse).
-- Con data (y dim opcional) Amount ya viene escalado para ese jugador; sin data es la cantidad base.
-- Devuelve { Rolls, Rewards = { { Kind, Amount, Base, Potion, Item, Dim, Chance (0..1) }, ... } } o nil.
function Gifts.Chances(itemId, data, dim)
	local tbl = Gifts.TableOf(itemId)
	if not tbl then return nil end
	local total = 0
	for _, r in ipairs(tbl.Rewards) do total += math.max(0, r.Weight) end
	local world = data and rewardWorld(data, dim) or nil
	local out = {}
	for i, r in ipairs(tbl.Rewards) do
		out[i] = {
			Kind = r.Kind, Base = r.Amount, Amount = data and Gifts.RewardAmount(r, data, world) or r.Amount,
			Potion = r.Potion, Item = r.Item, Dim = r.Kind == "Coins" and world or nil,
			Chance = total > 0 and math.max(0, r.Weight) / total or 0,
		}
	end
	return { Rolls = tbl.Rolls or 1, Rewards = out }
end

-- Tiradas de una tabla: solo sus pesos (sin suerte). Devuelve la lista de premios elegidos (definiciones de Config).
function Gifts.Roll(rng, tbl)
	local weights = {}
	for i, r in ipairs(tbl.Rewards) do weights[i] = { i, r.Weight } end
	local out = {}
	for _ = 1, tbl.Rolls or 1 do
		table.insert(out, tbl.Rewards[Economy.PickWeighted(rng, weights)])
	end
	return out
end

-- Abre un regalo del inventario: tira su tabla, entrega los premios y lo consume.
-- ctx = { Dim = mundo actual }. Devuelve true, { { Kind, Amount, Dim?, Potion?, Item? }, ... }.
-- Errores: item (no es un regalo), none (no tiene)
function Gifts.Open(data, itemId, rng, ctx)
	local tbl = Gifts.TableOf(itemId)
	if not tbl then return false, "item" end
	if Inventory.ItemCount(data, itemId) < 1 then return false, "none" end
	local dim = rewardWorld(data, ctx and ctx.Dim)
	local picks = Gifts.Roll(rng, tbl)
	Inventory.RemoveItem(data, itemId, 1)
	local rewards = {}
	for _, r in ipairs(picks) do
		local amount = Gifts.RewardAmount(r, data, dim)
		if r.Kind == "Coins" then
			data.Currency[dim] = (data.Currency[dim] or 0) + amount
			table.insert(rewards, { Kind = r.Kind, Amount = amount, Dim = dim })
		elseif r.Kind == "Diamonds" then
			data.Diamonds = (data.Diamonds or 0) + amount -- cantidad exacta: sin multiplicador de Diamonds
			table.insert(rewards, { Kind = r.Kind, Amount = amount })
		elseif r.Kind == "Potion" then
			Purchases.AddPotions(data, { [r.Potion] = amount })
			table.insert(rewards, { Kind = r.Kind, Amount = amount, Potion = r.Potion })
		elseif r.Kind == "Item" then
			Inventory.AddItem(data, r.Item, amount)
			table.insert(rewards, { Kind = r.Kind, Amount = amount, Item = r.Item })
		end
	end
	return true, rewards
end

return Gifts
