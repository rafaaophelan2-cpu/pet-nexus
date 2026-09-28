-- Pet Nexus: reglas de economía como funciones puras sobre los datos del jugador (data).
-- No tocan instancias ni remotes: el servidor valida la petición, llama aquí y luego sincroniza/notifica.
-- rng = cualquier objeto con :NextNumber() en [0, 1) (Random.new() en Roblox; un generador con seed en los tests).
-- Las funciones que pueden fallar devuelven (false, codigo, extra) o (true, resultado...).
local Config = require(script.Parent.Config)
local Stats = require(script.Parent.Stats)

local Economy = {}

local function rarityOrder(petName)
	local def = Config.Pets[petName]
	return def and Config.Rarities[def.Rarity].Order or 0
end

local function byOrder(a, b)
	if a[3] ~= b[3] then return a[3] < b[3] end
	return a[1] < b[1]
end

-- Elige una clave de list = { {clave, peso}, ... } según sus pesos (los pesos <= 0 nunca salen)
function Economy.PickWeighted(rng, list)
	local total = 0
	for _, e in ipairs(list) do
		if e[2] > 0 then total += e[2] end
	end
	if total <= 0 then return nil end
	local r = rng:NextNumber() * total
	local last
	for _, e in ipairs(list) do
		if e[2] > 0 then
			last = e[1]
			if r < e[2] then return e[1] end
			r -= e[2]
		end
	end
	return last -- solo por redondeo
end

---------------------------------------------------------------- mascotas
function Economy.NewPet(id, name)
	return { Id = id, Name = name, Equipped = false, Variant = Config.DefaultVariant, Level = Config.PetLevels.StartLevel, XP = 0 }
end

function Economy.FindPet(data, petId)
	for i, pet in ipairs(data.Pets) do
		if pet.Id == petId then return pet, i end
	end
	return nil
end

-- Equipa las mejores por poder real (con variante), hasta Stats.MaxEquipped
function Economy.EquipBest(data)
	table.sort(data.Pets, function(a, b) return Stats.PetPower(a) > Stats.PetPower(b) end)
	local max = Stats.MaxEquipped(data)
	for i, pet in ipairs(data.Pets) do
		pet.Equipped = i <= max
	end
end

-- Tirada de huevo: pity (tras PityThreshold aperturas sin Rare+ solo salen Rare+) y suerte (Stats.LuckWeights)
function Economy.RollEgg(rng, eggId, data, luck)
	local egg = Config.Eggs[eggId]
	data.Pity[eggId] = (data.Pity[eggId] or 0) + 1
	local pool = egg.Pets
	local forced = data.Pity[eggId] >= Config.PityThreshold
	if forced then
		pool = {}
		for _, e in ipairs(egg.Pets) do
			if rarityOrder(e[1]) >= 3 then table.insert(pool, e) end
		end
	end
	local pick = Economy.PickWeighted(rng, Stats.LuckWeights(pool, luck or 1))
	if rarityOrder(pick) >= 3 then
		data.Pity[eggId] = 0
	end
	return pick, forced
end

---------------------------------------------------------------- monedas / diamantes / esencia
-- Currency: "Diamonds" o "Dimension" (moneda del mundo dim)
function Economy.Balance(data, currency, dim)
	if currency == "Diamonds" then return data.Diamonds or 0 end
	return data.Currency[dim] or 0
end

function Economy.Spend(data, currency, dim, amount)
	if currency == "Diamonds" then
		data.Diamonds = (data.Diamonds or 0) - amount
	else
		data.Currency[dim] = (data.Currency[dim] or 0) - amount
	end
end

-- Única forma de GANAR diamantes: aplica el multiplicador de Diamonds. Devuelve lo que se sumó.
function Economy.AddDiamonds(data, base)
	local amount = math.floor(base * Stats.Get(data, "Diamonds"))
	if amount > 0 then data.Diamonds = (data.Diamonds or 0) + amount end
	return amount
end

-- Diamantes base que suelta un rompible para un jugador (0 si no sale). Ver Config.Breakables.
function Economy.RollDiamondDrop(rng, kindName)
	local k = Config.Breakables[kindName]
	if not k or not k.DiamondChance or rng:NextNumber() >= k.DiamondChance then return 0 end
	return k.Diamonds or 0
end

-- Suma Esencia de meditación: ticks x multiplicador; la parte decimal queda en data.Meditation.Carry
-- para que data.Essence siempre sea entero. Devuelve la Esencia entera sumada.
function Economy.GrantEssence(data, ticks, mult)
	local m = data.Meditation
	local amount = ticks * mult + (m.Carry or 0)
	local whole = math.floor(amount)
	m.Carry = amount - whole
	if whole > 0 then data.Essence += whole end
	return whole
end

-- Recorta la recarga de la Zona de Meditación en 'seconds' (math.huge = la termina). Devuelve los segundos recortados.
-- La usan el Developer Product EssenceCooldownSkip y, más adelante, las misiones (Config.Meditation.MissionCooldownCut).
function Economy.ReduceMeditationCooldown(data, seconds)
	local m = data.Meditation
	local before = math.max(0, m.Cooldown or 0)
	if type(seconds) ~= "number" or seconds <= 0 or before == 0 then return 0 end
	m.Cooldown = math.max(0, before - seconds)
	return before - m.Cooldown
end

---------------------------------------------------------------- encantamientos
local function levelWeights(def)
	local src = def.LevelWeights or Config.EnchantLevelWeights
	local out = {}
	for lvl = 1, #def.Levels do
		out[lvl] = { lvl, src[lvl] or src[#src] or 1 } -- si hay más niveles que pesos, repite el último
	end
	return out
end

local function enchantsOfTier(tier)
	local list = {}
	for id, e in pairs(Config.Enchants) do
		if e.Tier == tier then table.insert(list, { id, e.Weight or 1, e.Order or 0 }) end
	end
	table.sort(list, byOrder)
	return list
end

local function tierList()
	local list = {}
	for id, t in pairs(Config.EnchantTiers) do
		if #enchantsOfTier(id) > 0 then table.insert(list, { id, t.Weight, t.Order or 0 }) end
	end
	table.sort(list, byOrder)
	return list
end

-- Tirada: tier -> encantamiento del tier -> nivel. Devuelve id, nivel, tier.
function Economy.RollEnchant(rng)
	local tier = Economy.PickWeighted(rng, tierList())
	local id = Economy.PickWeighted(rng, enchantsOfTier(tier))
	local level = Economy.PickWeighted(rng, levelWeights(Config.Enchants[id]))
	return id, level, tier
end

-- Probabilidades exactas (0..1) de la tirada: { Tiers = {[tier] = p}, Enchants = {[id] = {[nivel] = p}} }
function Economy.EnchantChances()
	local out = { Tiers = {}, Enchants = {} }
	local function norm(list)
		local total = 0
		for _, e in ipairs(list) do if e[2] > 0 then total += e[2] end end
		return total
	end
	local tiers = tierList()
	local tTotal = norm(tiers)
	for _, t in ipairs(tiers) do
		local pt = math.max(t[2], 0) / tTotal
		out.Tiers[t[1]] = pt
		local list = enchantsOfTier(t[1])
		local eTotal = norm(list)
		for _, e in ipairs(list) do
			local pe = pt * math.max(e[2], 0) / eTotal
			local lw = levelWeights(Config.Enchants[e[1]])
			local lTotal = norm(lw)
			out.Enchants[e[1]] = {}
			for _, l in ipairs(lw) do
				out.Enchants[e[1]][l[1]] = pe * math.max(l[2], 0) / lTotal
			end
		end
	end
	return out
end

-- Una tirada pagada sobre una mascota del jugador: cobra EnchantCost en diamantes y reemplaza el encantamiento
function Economy.EnchantPet(data, petId, rng)
	local pet = Economy.FindPet(data, petId)
	if not pet then return false, "pet" end
	local cost = Config.EnchantCost
	local have = data.Diamonds or 0
	if have < cost then return false, "funds", cost - have end
	data.Diamonds = have - cost
	local id, level, tier = Economy.RollEnchant(rng)
	pet.Enchant = { Id = id, Level = level }
	return true, pet.Enchant, tier
end

-- ¿El encantamiento cumple el objetivo del auto enchant?
function Economy.MatchesTarget(enchant, targetId, minLevel)
	return type(enchant) == "table" and enchant.Id == targetId and (enchant.Level or 0) >= (minLevel or 1)
end

---------------------------------------------------------------- mejoras
-- Precio de un nivel: price, currency, dimensión de la moneda (las globales sin Dimension: el mundo inicial)
function Economy.UpgradeCost(id, level, dim)
	local def = Config.Upgrades[id]
	local entry = def and def.Levels[level]
	if not entry then return nil end
	if def.PerDimension then
		return math.floor(entry.Price * Config.UpgradePriceScale(dim)), def.Currency, dim
	end
	return entry.Price, def.Currency, def.Dimension or Config.SpawnWorld()
end

-- Compra el nivel 'level' (tiene que ser el siguiente). dim: mundo de la mejora (solo PerDimension).
-- Errores: upgrade, level, dim, owned, max, order, funds (extra = lo que falta)
function Economy.BuyUpgrade(data, id, level, dim)
	local def = Config.Upgrades[id]
	if not def then return false, "upgrade" end
	if type(level) ~= "number" or level ~= math.floor(level) then return false, "level" end
	if def.PerDimension then
		if type(dim) ~= "string" or not Config.Dimensions[dim] then return false, "dim" end
	else
		dim = nil
	end
	local current = Stats.UpgradeLevel(data, id, dim)
	if level <= current then return false, "owned" end
	if level > #def.Levels then return false, "max" end
	if level ~= current + 1 then return false, "order" end
	local price, currency, curDim = Economy.UpgradeCost(id, level, dim)
	if currency ~= "Diamonds" and (data.Unlocked[curDim] or 0) < 1 then return false, "dim" end
	local have = Economy.Balance(data, currency, curDim)
	if have < price then return false, "funds", price - have end
	Economy.Spend(data, currency, curDim, price)
	if def.PerDimension then
		if type(data.Upgrades[id]) ~= "table" then data.Upgrades[id] = {} end
		data.Upgrades[id][dim] = level
	else
		data.Upgrades[id] = level
	end
	return true
end

---------------------------------------------------------------- variantes
-- Convierte con la receta Config.VariantRecipes[target] usando la máquina del mundo dim.
-- petIds[1] se conserva (sube de variante, mantiene su encantamiento); el resto se consume.
-- Errores: variant, count, machine, locked, pet, mismatch, from, funds (extra = lo que falta)
function Economy.ConvertVariant(data, petIds, target, dim)
	local recipe = Config.VariantRecipes[target]
	if not recipe then return false, "variant" end
	if type(petIds) ~= "table" or #petIds ~= recipe.Pets then return false, "count" end
	local area = type(dim) == "string" and Config.MachineArea(dim, recipe.Machine)
	if not area then return false, "machine" end
	if (data.Unlocked[dim] or 0) < area then return false, "locked" end
	local seen, pets = {}, {}
	for i = 1, recipe.Pets do
		local id = petIds[i]
		if type(id) ~= "string" or seen[id] then return false, "count" end
		seen[id] = true
		local pet = Economy.FindPet(data, id)
		if not pet then return false, "pet" end
		if pets[1] and pet.Name ~= pets[1].Name then return false, "mismatch" end
		if (pet.Variant or Config.DefaultVariant) ~= recipe.From then return false, "from" end
		pets[i] = pet
	end
	local have = Economy.Balance(data, recipe.Currency, dim)
	if have < recipe.Price then return false, "funds", recipe.Price - have end
	Economy.Spend(data, recipe.Currency, dim, recipe.Price)
	local kept = pets[1]
	kept.Variant = target
	seen[kept.Id] = nil
	for i = #data.Pets, 1, -1 do
		if seen[data.Pets[i].Id] then table.remove(data.Pets, i) end
	end
	return true, kept
end

return Economy
