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
		Pets = {},
		Unlocked = { Nexus = 1 },
		Essence = 0,
		WorldsPaid = {}, -- mundos cuyo vehículo ya se pagó con Esencia
		Pity = {},
		Rebirths = 0,
		TotalHatched = 0,
	}
end

local function reconcile(data)
	for k, v in pairs(defaultData()) do
		if data[k] == nil then data[k] = v end
	end
	return data
end

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
