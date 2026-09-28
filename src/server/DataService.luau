-- Pet Nexus: guardado de datos (DataStore) con sesión en memoria
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "PetNexus_v2" -- v2: Nexus pasa a ser el mundo 1 (datos de v1 no se usan). Se mantiene: los datos migran solos.
local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then warn("[PetNexus] DataStore no disponible:", err) end
end

local DataService = {}
local sessions = {}
local loadFailed = {} -- [player] = true si no se pudieron leer sus datos: esa sesión nunca se guarda (no pisa lo real)

local function defaultData()
	return {
		Currency = {}, -- moneda propia de cada mundo ([dim] = cantidad; Nexus = Angel Coins, Greenwood = Coins)
		Diamonds = 0, -- moneda global
		-- Pets[i] = { Id, Name, Equipped, Variant = "Normal"|"Golden"|"Rainbow"|"Void", Enchant = { Id, Level } o nil,
		--            Level, XP (XP acumulada dentro del nivel actual) }
		Pets = {},
		Unlocked = {}, -- [dim] = área más alta desbloqueada; el mundo inicial se agrega al cargar (ver Reconcile)
		Essence = 0, -- no tradeable (ver Config.Meditation)
		-- segundos meditados en el ciclo / segundos de recarga restantes / fracción de Esencia pendiente (multiplicador)
		Meditation = { Progress = 0, Cooldown = 0, Carry = 0 },
		Upgrades = {}, -- [id] = nivel; las PerDimension: [id] = { [dim] = nivel } (ver Config.Upgrades)
		WorldsPaid = {}, -- mundos cuyo vehículo ya se pagó con Esencia
		Pity = {},
		RebirthsDone = {}, -- [dim] = true: rebirth de ese mundo hecho (ver Config.Rebirths)
		Rank = 0, -- 0 = sin rango (ver Config.Ranks)
		Passes = {}, -- [key] = true: gamepasses del jugador (el servidor lo actualiza al entrar y al comprar)
		Potions = {}, -- inventario: [tipo] = cantidad
		PotionTime = {}, -- [tipo] = segundos que le quedan a la poción activa (solo bajan con el jugador conectado)
		FreePotions = { NextClaim = 0, SkipDay = 0, SkipsUsed = 0 }, -- NextClaim en os.time(); SkipDay = día UTC
		Receipts = {}, -- PurchaseId ya entregados (los últimos Config.ReceiptHistory)
		TotalHatched = 0,
	}
end

-- Rellena lo que falte (también dentro de tablas anidadas) sin pisar lo que ya existe
local function fill(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		elseif type(v) == "table" and type(target[k]) == "table" then
			fill(target[k], v)
		end
	end
end

-- Migra partidas guardadas a la forma actual (idempotente: se puede aplicar varias veces).
-- opts (los pasa el servidor desde Config; todos opcionales):
--   StartWorld   mundo que siempre queda desbloqueado (área 1 como mínimo)
--   RebirthOrder lista de mundos por número de rebirth, para migrar el contador viejo data.Rebirths
--   StartLevel   nivel con el que quedan las mascotas que aún no tienen nivel
function DataService.Reconcile(data, opts)
	opts = opts or {}
	-- sistema viejo de rebirths (un número que daba +50% de poder y monedas): los primeros N rebirths nuevos quedan hechos
	-- (sin reiniciar nada)
	local oldRebirths = data.Rebirths
	data.Rebirths = nil
	fill(data, defaultData())
	if type(oldRebirths) == "number" and oldRebirths > 0 then
		for i, dim in ipairs(opts.RebirthOrder or {}) do
			if i <= oldRebirths then data.RebirthsDone[dim] = true end
		end
	end
	if opts.StartWorld then
		data.Unlocked[opts.StartWorld] = math.max(data.Unlocked[opts.StartWorld] or 0, 1)
	end
	for _, pet in ipairs(data.Pets) do
		if pet.Variant == nil then pet.Variant = "Normal" end -- partidas previas a las variantes
		if type(pet.Enchant) ~= "table" then pet.Enchant = nil end
		if type(pet.Level) ~= "number" then pet.Level = opts.StartLevel or 1 end -- partidas previas a los niveles
		if type(pet.XP) ~= "number" then pet.XP = 0 end
	end
	return data
end
DataService.Default = defaultData

function DataService.Load(player, opts)
	local data
	local failed = false
	if store then
		failed = true
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("p_" .. player.UserId)
			end)
			if ok then
				data = result
				failed = false
				break
			end
			warn("[PetNexus] Error cargando datos (intento " .. attempt .. "):", result)
			task.wait(1)
		end
	end
	if failed then warn("[PetNexus] No se pudieron cargar los datos de " .. player.Name .. ": la sesión no se guardará") end
	loadFailed[player] = failed or nil
	data = DataService.Reconcile(data or defaultData(), opts)
	sessions[player] = data
	return data
end

function DataService.Get(player)
	return sessions[player]
end

-- true si los datos del jugador se cargaron bien (se pueden entregar compras y guardar)
function DataService.IsLoaded(player)
	return sessions[player] ~= nil and not loadFailed[player]
end

-- Guarda y devuelve true si quedó guardado
function DataService.Save(player)
	local data = sessions[player]
	if not data or not store or loadFailed[player] then return false end
	local ok, err = pcall(function()
		store:UpdateAsync("p_" .. player.UserId, function()
			return data
		end)
	end)
	if not ok then warn("[PetNexus] Error guardando datos:", err) end
	return ok
end

function DataService.Release(player)
	DataService.Save(player)
	sessions[player] = nil
	loadFailed[player] = nil
end

function DataService.SaveAll()
	for player in pairs(sessions) do
		DataService.Save(player)
	end
end

return DataService
