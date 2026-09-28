-- Pet Nexus: guardado de datos (DataStore) con sesión en memoria
local DataStoreService = game:GetService("DataStoreService")

local STORE_NAME = "PetNexus_v2" -- v2: Nexus pasa a ser el mundo 1 (datos de v1 no se usan)
local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then warn("[PetNexus] DataStore no disponible:", err) end
end

local DataService = {}
local sessions = {}

local function defaultData()
	return {
		Currency = { Nexus = 0 }, -- moneda propia de cada mundo (Nexus = Angel Coins)
		Diamonds = 0, -- moneda global
		-- Pets[i] = { Id, Name, Equipped, Variant = "Normal"|"Golden"|"Rainbow"|"Void", Enchant = { Id, Level } o nil }
		Pets = {},
		Unlocked = { Nexus = 1 },
		Essence = 0, -- no tradeable (ver Config.Meditation)
		-- segundos meditados en el ciclo / segundos de recarga restantes / fracción de Esencia pendiente (multiplicador)
		Meditation = { Progress = 0, Cooldown = 0, Carry = 0 },
		Upgrades = {}, -- [id] = nivel; las PerDimension: [id] = { [dim] = nivel } (ver Config.Upgrades)
		WorldsPaid = {}, -- mundos cuyo vehículo ya se pagó con Esencia
		Pity = {},
		Rebirths = 0,
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

-- Migra partidas guardadas a la forma actual (idempotente: se puede aplicar varias veces)
local function reconcile(data)
	fill(data, defaultData())
	for _, pet in ipairs(data.Pets) do
		if pet.Variant == nil then pet.Variant = "Normal" end -- partidas previas a las variantes
		if type(pet.Enchant) ~= "table" then pet.Enchant = nil end
	end
	return data
end
DataService.Reconcile = reconcile
DataService.Default = defaultData

function DataService.Load(player)
	local data
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("p_" .. player.UserId)
			end)
			if ok then data = result break end
			warn("[PetNexus] Error cargando datos (intento " .. attempt .. "):", result)
			task.wait(1)
		end
	end
	data = reconcile(data or defaultData())
	sessions[player] = data
	return data
end

function DataService.Get(player)
	return sessions[player]
end

function DataService.Save(player)
	local data = sessions[player]
	if not data or not store then return end
	local ok, err = pcall(function()
		store:UpdateAsync("p_" .. player.UserId, function()
			return data
		end)
	end)
	if not ok then warn("[PetNexus] Error guardando datos:", err) end
end

function DataService.Release(player)
	DataService.Save(player)
	sessions[player] = nil
end

function DataService.SaveAll()
	for player in pairs(sessions) do
		DataService.Save(player)
	end
end

return DataService
