-- Pet Nexus: inventario (mascotas, teams e items) como funciones puras sobre los datos del jugador (data).
-- Igual que Economy: no tocan instancias ni remotes; devuelven (false, codigo, extra) o (true, resultado...).
-- Datos que se usan: Pets (pet.Equipped, pet.Locked), Teams, Items, Potions, PotionTime.
-- El jugador controla su equipo: nada aquí equipa mascotas por su cuenta salvo AddPet (si queda un espacio libre).
local Config = require(script.Parent.Config)
local Stats = require(script.Parent.Stats)
local Economy = require(script.Parent.Economy)

local Inventory = {}

Inventory.Tabs = { "Pets", "Items", "Potions", "Teams" } -- pestañas de la UI, en orden

local function petIndex(data)
	local byId = {}
	for _, pet in ipairs(data.Pets) do byId[pet.Id] = pet end
	return byId
end

local function byPower(a, b)
	local pa, pb = Stats.PetPower(a), Stats.PetPower(b)
	if pa ~= pb then return pa > pb end
	return tostring(a.Id) < tostring(b.Id)
end

---------------------------------------------------------------- capacidad
function Inventory.MaxPets(data)
	return Stats.MaxInventory(data)
end

-- Espacios libres (0 si está lleno o pasado del máximo)
function Inventory.Space(data)
	return math.max(0, Inventory.MaxPets(data) - #data.Pets)
end

function Inventory.IsFull(data)
	return Inventory.Space(data) <= 0
end

function Inventory.EquippedCount(data)
	local n = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then n += 1 end
	end
	return n
end

---------------------------------------------------------------- mascotas
-- Única forma de recibir una mascota. Errores: name (no existe en Config.Pets), full (extra = máximo).
-- La mascota nueva se equipa sola solo si queda un espacio de equipo libre (Config.Inventory.AutoEquipNew).
function Inventory.AddPet(data, id, name)
	if not Config.Pets[name] then return false, "name" end
	if Inventory.IsFull(data) then return false, "full", Inventory.MaxPets(data) end
	local pet = Economy.NewPet(id, name)
	if Config.Inventory.AutoEquipNew and Inventory.EquippedCount(data) < Stats.MaxEquipped(data) then
		pet.Equipped = true
	end
	table.insert(data.Pets, pet)
	return true, pet
end

-- Errores: pet (no existe), equipped (ya estaba), slots (sin espacio de equipo; extra = MaxEquipped)
function Inventory.Equip(data, petId)
	local pet = Economy.FindPet(data, petId)
	if not pet then return false, "pet" end
	if pet.Equipped then return false, "equipped" end
	local max = Stats.MaxEquipped(data)
	if Inventory.EquippedCount(data) >= max then return false, "slots", max end
	pet.Equipped = true
	return true, pet
end

-- Errores: pet, unequipped (no estaba equipada)
function Inventory.Unequip(data, petId)
	local pet = Economy.FindPet(data, petId)
	if not pet then return false, "pet" end
	if not pet.Equipped then return false, "unequipped" end
	pet.Equipped = false
	return true, pet
end

-- Equipa las mejores por poder real (Economy.EquipBest). Devuelve cuántas quedaron equipadas.
function Inventory.EquipBest(data)
	Economy.EquipBest(data)
	return Inventory.EquippedCount(data)
end

-- Si hay más equipadas que MaxEquipped (por ejemplo, se perdió un gamepass) desequipa las más débiles.
-- Devuelve cuántas se desequiparon.
function Inventory.ClampEquipped(data)
	local equipped = {}
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then table.insert(equipped, pet) end
	end
	local max = Stats.MaxEquipped(data)
	if #equipped <= max then return 0 end
	table.sort(equipped, byPower)
	for i = max + 1, #equipped do equipped[i].Equipped = false end
	return #equipped - max
end

-- Bloquea o desbloquea una mascota (una bloqueada no se puede borrar). Errores: pet, value
function Inventory.SetLocked(data, petId, locked)
	if type(locked) ~= "boolean" then return false, "value" end
	local pet = Economy.FindPet(data, petId)
	if not pet then return false, "pet" end
	pet.Locked = locked or nil
	return true, pet
end

-- Borra varias mascotas a la vez. Se saltan las bloqueadas y las que no existen; una equipada se desequipa al borrarse
-- y se quita de los teams que la tengan. Nunca deja menos de Config.Inventory.MinPets.
-- Devuelve true, { Deleted = {ids}, Locked = n, Missing = n }.
-- Errores: list (lista inválida), min (quedarían menos del mínimo; extra = mínimo), none (no se borró nada; extra = info)
function Inventory.DeletePets(data, petIds)
	if type(petIds) ~= "table" then return false, "list" end
	local n = #petIds
	if n < 1 or n > math.max(#data.Pets, Inventory.MaxPets(data)) then return false, "list" end
	local byId = petIndex(data)
	local seen, del, count = {}, {}, 0
	local info = { Deleted = {}, Locked = 0, Missing = 0 }
	for i = 1, n do
		local id = petIds[i]
		if type(id) ~= "string" then return false, "list" end
		if not seen[id] then
			seen[id] = true
			local pet = byId[id]
			if not pet then
				info.Missing += 1
			elseif pet.Locked then
				info.Locked += 1
			else
				del[id] = true
				count += 1
			end
		end
	end
	if count == 0 then return false, "none", info end
	if #data.Pets - count < Config.Inventory.MinPets then return false, "min", Config.Inventory.MinPets end
	-- compacta la lista en el lugar (la tabla data.Pets sigue siendo la misma)
	local pets, j = data.Pets, 0
	for i = 1, #pets do
		local pet = pets[i]
		if del[pet.Id] then
			pet.Equipped = false
			table.insert(info.Deleted, pet.Id)
		else
			j += 1
			pets[j] = pet
		end
	end
	for i = #pets, j + 1, -1 do pets[i] = nil end
	Inventory.RemoveFromTeams(data, del)
	return true, info
end

---------------------------------------------------------------- teams
-- data.Teams["<slot>"] = { Name, PetIds = {ids} } (clave texto: el DataStore no admite listas con huecos)
local function teamKey(slot)
	return tostring(slot)
end

function Inventory.ValidSlot(slot)
	return type(slot) == "number" and slot == math.floor(slot) and slot >= 1 and slot <= Config.Teams.Max
end

function Inventory.GetTeam(data, slot)
	if not Inventory.ValidSlot(slot) then return nil end
	return data.Teams[teamKey(slot)]
end

function Inventory.DefaultTeamName(slot)
	return "Equipo " .. slot
end

-- Limpia un nombre escrito por el jugador: sin caracteres de control, espacios recortados, 1..Config.Teams.NameMax.
-- nil = inválido. El servidor además lo pasa por el filtro de texto de Roblox.
function Inventory.CleanTeamName(name)
	if type(name) ~= "string" then return nil end
	name = name:gsub("%c", " ")
	name = name:gsub("%s+", " ")
	name = name:gsub("^ ", "")
	name = name:gsub(" $", "")
	local len = utf8.len(name)
	if not len or len < 1 or len > Config.Teams.NameMax then return nil end
	return name
end

-- Guarda un team en el slot. petIds = nil: guarda el equipo actual. name = nil: conserva el nombre del slot
-- (o "Equipo <slot>" si estaba vacío). Errores: slot, name, pets (lista inválida o repetida), pet (alguna no existe),
-- size (más que MaxEquipped; extra = máximo), empty (sin mascotas)
function Inventory.SaveTeam(data, slot, name, petIds)
	if not Inventory.ValidSlot(slot) then return false, "slot" end
	local old = data.Teams[teamKey(slot)]
	local clean
	if name == nil then
		clean = old and old.Name or Inventory.DefaultTeamName(slot)
	else
		clean = Inventory.CleanTeamName(name)
		if not clean then return false, "name" end
	end
	local ids = {}
	if petIds == nil then
		for _, pet in ipairs(data.Pets) do
			if pet.Equipped then table.insert(ids, pet.Id) end
		end
	else
		if type(petIds) ~= "table" then return false, "pets" end
		local max = Stats.MaxEquipped(data)
		local n = #petIds
		if n > max then return false, "size", max end
		local byId, seen = petIndex(data), {}
		for i = 1, n do
			local id = petIds[i]
			if type(id) ~= "string" or seen[id] then return false, "pets" end
			seen[id] = true
			if not byId[id] then return false, "pet" end
			table.insert(ids, id)
		end
	end
	if #ids == 0 then return false, "empty" end
	local team = { Name = clean, PetIds = ids }
	data.Teams[teamKey(slot)] = team
	return true, team
end

-- Equipa el team del slot con un clic: desequipa todo y equipa sus mascotas (hasta MaxEquipped).
-- Las que ya no existen se omiten (y se quitan del team). Si no queda ninguna, no toca el equipo actual.
-- Devuelve true, { Equipped = n, Missing = n, Skipped = n (sobraban por MaxEquipped) }.
-- Errores: slot, empty (slot sin team o team vacío), missing (ninguna existe; extra = cuántas faltan)
function Inventory.ApplyTeam(data, slot)
	if not Inventory.ValidSlot(slot) then return false, "slot" end
	local team = data.Teams[teamKey(slot)]
	if not team or #team.PetIds == 0 then return false, "empty" end
	local byId = petIndex(data)
	local max = Stats.MaxEquipped(data)
	local toEquip, kept = {}, {}
	local missing, skipped = 0, 0
	for _, id in ipairs(team.PetIds) do
		local pet = byId[id]
		if not pet then
			missing += 1
		else
			table.insert(kept, id)
			if #toEquip < max then table.insert(toEquip, pet) else skipped += 1 end
		end
	end
	team.PetIds = kept
	if #toEquip == 0 then return false, "missing", missing end
	for _, pet in ipairs(data.Pets) do pet.Equipped = false end
	for _, pet in ipairs(toEquip) do pet.Equipped = true end
	return true, { Equipped = #toEquip, Missing = missing, Skipped = skipped }
end

-- Errores: slot, empty, name
function Inventory.RenameTeam(data, slot, name)
	if not Inventory.ValidSlot(slot) then return false, "slot" end
	local team = data.Teams[teamKey(slot)]
	if not team then return false, "empty" end
	local clean = Inventory.CleanTeamName(name)
	if not clean then return false, "name" end
	team.Name = clean
	return true, team
end

-- Errores: slot, empty
function Inventory.DeleteTeam(data, slot)
	if not Inventory.ValidSlot(slot) then return false, "slot" end
	if not data.Teams[teamKey(slot)] then return false, "empty" end
	data.Teams[teamKey(slot)] = nil
	return true
end

-- Quita de todos los teams las mascotas de idSet ({ [id] = true }). Devuelve cuántas referencias quitó.
function Inventory.RemoveFromTeams(data, idSet)
	local removed = 0
	for _, team in pairs(data.Teams) do
		local kept = {}
		for _, id in ipairs(team.PetIds) do
			if idSet[id] then removed += 1 else table.insert(kept, id) end
		end
		team.PetIds = kept
	end
	return removed
end

-- Quita de los teams las mascotas que ya no existen (por ejemplo, las consumidas por una máquina de variantes)
function Inventory.PruneTeams(data)
	local byId = petIndex(data)
	local gone = {}
	for _, team in pairs(data.Teams) do
		for _, id in ipairs(team.PetIds) do
			if not byId[id] then gone[id] = true end
		end
	end
	return Inventory.RemoveFromTeams(data, gone)
end

---------------------------------------------------------------- items
function Inventory.ItemCount(data, itemId)
	local n = data.Items[itemId]
	return type(n) == "number" and n or 0
end

-- Suma n (entero >= 1) del item. false si el item no existe en Config.Items o n es inválido.
function Inventory.AddItem(data, itemId, n)
	n = n or 1
	if not Config.Items[itemId] or type(n) ~= "number" or n < 1 then return false end
	data.Items[itemId] = Inventory.ItemCount(data, itemId) + math.floor(n)
	return true
end

-- Quita n (1 por defecto). false si no alcanzan.
function Inventory.RemoveItem(data, itemId, n)
	n = n or 1
	local have = Inventory.ItemCount(data, itemId)
	if type(n) ~= "number" or n < 1 or have < n then return false end
	local left = have - math.floor(n)
	data.Items[itemId] = left > 0 and left or nil
	return true
end

---------------------------------------------------------------- vista para la UI
-- Todo lo que necesitan las pestañas Pets / Items / Potions / Teams (lo pueden llamar el cliente y el servidor):
--   Pets    = { Count, Max, Equipped, MaxEquipped, List = mascotas (equipadas primero, luego por poder) }
--   Items   = { { Id, Name, Rarity, Type, Icon, Count }, ... } por Order (los regalos se abren con OpenGift)
--   Potions = { { Id, Name, Stat, Bonus, Count, Remaining }, ... } por Order (se usan con UsePotion)
--   Teams   = { Max, List = { { Slot, Name, PetIds, Missing, Empty }, ... } } un elemento por slot
function Inventory.View(data)
	local pets = table.clone(data.Pets)
	table.sort(pets, function(a, b)
		if (a.Equipped == true) ~= (b.Equipped == true) then return a.Equipped == true end
		return byPower(a, b)
	end)
	local list = {}
	for _, pet in ipairs(pets) do
		table.insert(list, {
			Id = pet.Id, Name = pet.Name, Display = Config.PetName(pet.Name), Equipped = pet.Equipped == true,
			Locked = pet.Locked == true, Variant = pet.Variant, Enchant = pet.Enchant, Level = pet.Level,
			Power = Stats.PetPower(pet),
		})
	end

	local items = {}
	for id, def in pairs(Config.Items) do
		local count = Inventory.ItemCount(data, id)
		if count > 0 then
			table.insert(items, { Id = id, Name = def.Name, Rarity = def.Rarity, Type = def.Type, Icon = def.Icon,
				Count = count, Order = def.Order or 0 })
		end
	end
	table.sort(items, function(a, b) return a.Order < b.Order end)

	local potions = {}
	for id, def in pairs(Config.Potions.Types) do
		table.insert(potions, { Id = id, Name = def.Name, Stat = def.Stat, Bonus = def.Bonus, Order = def.Order or 0,
			Count = data.Potions[id] or 0, Remaining = Stats.PotionRemaining(data, id) })
	end
	table.sort(potions, function(a, b) return a.Order < b.Order end)

	local byId = petIndex(data)
	local teams = {}
	for slot = 1, Config.Teams.Max do
		local team = data.Teams[teamKey(slot)]
		if team then
			local missing = 0
			for _, id in ipairs(team.PetIds) do
				if not byId[id] then missing += 1 end
			end
			table.insert(teams, { Slot = slot, Name = team.Name, PetIds = table.clone(team.PetIds), Missing = missing, Empty = false })
		else
			table.insert(teams, { Slot = slot, Empty = true })
		end
	end

	return {
		Pets = { Count = #data.Pets, Max = Inventory.MaxPets(data), Equipped = Inventory.EquippedCount(data),
			MaxEquipped = Stats.MaxEquipped(data), List = list },
		Items = items,
		Potions = potions,
		Teams = { Max = Config.Teams.Max, List = teams },
	}
end

return Inventory
