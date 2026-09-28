-- Pet Nexus: stats centralizados. Funciones puras: solo leen los datos del jugador (data) y Config, no tocan instancias.
-- Las usa el servidor para decidir todo y el cliente para mostrar valores. Regla y definiciones en Config.StatDefs:
--   final = Base x (1 + mejora) x (1 + encantamientos equipados) x (1 + rebirths) x (1 + rango) x (1 + gamepasses)
--                x (1 + pociones activas)
-- Datos que se leen: Pets, Upgrades, RebirthsDone, Rank, Passes, PotionTime.
-- MaxEquipped y MaxInventory son enteros aparte: base + mejora + rebirths + gamepasses (sin multiplicar).
local Config = require(script.Parent.Config)

local Stats = {}

-- Multiplicador de la variante de una mascota (Normal = x1)
function Stats.VariantMultiplier(variant)
	local v = Config.PetVariants[variant or Config.DefaultVariant]
	return v and v.Multiplier or 1
end

-- Multiplicador por nivel de una mascota: 1 + nivel x BonusPerLevel
function Stats.LevelMultiplier(pet)
	local lv = type(pet.Level) == "number" and pet.Level or Config.PetLevels.StartLevel
	lv = math.clamp(lv, 0, Config.PetLevels.MaxLevel)
	return 1 + lv * Config.PetLevels.BonusPerLevel
end

-- Poder real de una mascota (base x variante x nivel)
function Stats.PetPower(pet)
	local def = Config.Pets[pet.Name]
	if not def then return 0 end
	return def.Power * Stats.VariantMultiplier(pet.Variant) * Stats.LevelMultiplier(pet)
end

-- Poder total de las mascotas equipadas: es lo que daña a los rompibles
function Stats.Power(data)
	local total = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then total += Stats.PetPower(pet) end
	end
	return total
end

-- Bonus del encantamiento de UNA mascota sobre una stat, ya multiplicado por su variante y su nivel (0 si no aplica)
function Stats.PetEnchantBonus(pet, stat)
	local e = pet.Enchant
	if type(e) ~= "table" then return 0 end
	local def = Config.Enchants[e.Id]
	if not def or def.Stat ~= stat then return 0 end
	local bonus = def.Levels[e.Level]
	if not bonus then return 0 end
	return bonus * Stats.VariantMultiplier(pet.Variant) * Stats.LevelMultiplier(pet)
end

-- Suma de bonus de encantamiento de las mascotas equipadas para una stat
function Stats.EnchantSum(data, stat)
	local sum = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then sum += Stats.PetEnchantBonus(pet, stat) end
	end
	return sum
end

---------------------------------------------------------------- mejoras
-- Nivel comprado de una mejora (PerDimension: el de ese mundo). 0 = sin comprar.
function Stats.UpgradeLevel(data, id, dim)
	local def = Config.Upgrades[id]
	local ups = data.Upgrades
	if not def or type(ups) ~= "table" then return 0 end
	local v = ups[id]
	if def.PerDimension then
		v = type(v) == "table" and dim ~= nil and v[dim] or 0
	end
	return type(v) == "number" and v or 0
end

function Stats.HasUpgrade(data, id)
	return Stats.UpgradeLevel(data, id) >= 1
end

-- Bonus total de mejoras sobre una stat (el nivel n da Levels[n].Bonus, no se suman niveles)
function Stats.UpgradeBonus(data, stat, dim)
	local total = 0
	for id, def in pairs(Config.Upgrades) do
		if def.Stat == stat then
			local entry = def.Levels[Stats.UpgradeLevel(data, id, dim)]
			if entry and entry.Bonus then total += entry.Bonus end
		end
	end
	return total
end

---------------------------------------------------------------- rebirths, rango, gamepasses y pociones
function Stats.RebirthDone(data, dim)
	return type(data.RebirthsDone) == "table" and data.RebirthsDone[dim] == true
end

-- Cantidad de rebirths hechos
function Stats.RebirthCount(data)
	local n = 0
	for dim in pairs(Config.Rebirths) do
		if Stats.RebirthDone(data, dim) then n += 1 end
	end
	return n
end

function Stats.RebirthBonus(data, stat)
	local total = 0
	for dim, def in pairs(Config.Rebirths) do
		if Stats.RebirthDone(data, dim) then total += def.Bonus[stat] or 0 end
	end
	return total
end

-- ¿Algún rebirth hecho desbloquea el rango?
function Stats.RankUnlocked(data)
	for dim, def in pairs(Config.Rebirths) do
		if def.Unlocks and def.Unlocks.Rank and Stats.RebirthDone(data, dim) then return true end
	end
	return false
end

function Stats.Rank(data)
	local r = data.Rank
	if type(r) ~= "number" then return 0 end
	return math.clamp(math.floor(r), 0, #Config.Ranks.Levels)
end

function Stats.RankBonus(data, stat)
	local entry = Config.Ranks.Levels[Stats.Rank(data)]
	if not entry then return 0 end
	for _, s in ipairs(Config.Ranks.Stats) do
		if s == stat then return entry.Bonus end
	end
	return 0
end

function Stats.HasPass(data, key)
	return type(data.Passes) == "table" and data.Passes[key] == true and Config.GamePasses[key] ~= nil
end

function Stats.PassBonus(data, stat)
	local total = 0
	for key, def in pairs(Config.GamePasses) do
		if def.Bonus and Stats.HasPass(data, key) then total += def.Bonus[stat] or 0 end
	end
	return total
end

-- Segundos que le quedan a la poción de ese tipo (0 = inactiva)
function Stats.PotionRemaining(data, potionType)
	local t = type(data.PotionTime) == "table" and data.PotionTime[potionType]
	return type(t) == "number" and math.max(t, 0) or 0
end

function Stats.PotionBonus(data, stat)
	local total = 0
	for id, def in pairs(Config.Potions.Types) do
		if def.Stat == stat and Stats.PotionRemaining(data, id) > 0 then total += def.Bonus end
	end
	return total
end

---------------------------------------------------------------- valor final
-- Cantidad máxima de mascotas equipadas (entero)
function Stats.MaxEquipped(data)
	return Config.MaxEquipped + Stats.UpgradeBonus(data, "MaxEquipped") + Stats.RebirthBonus(data, "MaxEquipped")
		+ Stats.PassBonus(data, "MaxEquipped")
end

-- Cantidad máxima de mascotas en el inventario (entero): base + mejora InventorySlots + rebirths + gamepasses
function Stats.MaxInventory(data)
	return Config.Inventory.BasePets + Stats.UpgradeBonus(data, "MaxInventory") + Stats.RebirthBonus(data, "MaxInventory")
		+ Stats.PassBonus(data, "MaxInventory")
end

-- Factores por fuente (para la UI y los tests): cada uno es 1 + la suma de bonus de esa fuente
function Stats.Breakdown(data, stat, dim)
	return {
		Base = Config.StatDefs[stat].Base,
		Upgrade = 1 + Stats.UpgradeBonus(data, stat, dim),
		Enchant = 1 + Stats.EnchantSum(data, stat),
		Rebirth = 1 + Stats.RebirthBonus(data, stat),
		Rank = 1 + Stats.RankBonus(data, stat),
		GamePass = 1 + Stats.PassBonus(data, stat),
		Potion = 1 + Stats.PotionBonus(data, stat),
	}
end

-- Valor final de una stat. dim solo importa para las mejoras por dimensión (Coins).
function Stats.Get(data, stat, dim)
	if stat == "MaxEquipped" then return Stats.MaxEquipped(data) end
	if stat == "MaxInventory" then return Stats.MaxInventory(data) end
	assert(Config.StatDefs[stat], "stat desconocida: " .. tostring(stat))
	local b = Stats.Breakdown(data, stat, dim)
	return b.Base * b.Upgrade * b.Enchant * b.Rebirth * b.Rank * b.GamePass * b.Potion
end

-- Todas las stats de un jugador (para debug y para la UI futura). Coins usa la dimensión dada.
function Stats.Compute(data, dim)
	local out = { MaxEquipped = Stats.MaxEquipped(data), MaxInventory = Stats.MaxInventory(data), Power = Stats.Power(data),
		Rank = Stats.Rank(data), Rebirths = Stats.RebirthCount(data) }
	for stat in pairs(Config.StatDefs) do
		out[stat] = Stats.Get(data, stat, dim)
	end
	return out
end

---------------------------------------------------------------- suerte
-- Pesos de un huevo con suerte aplicada (ver Config.LuckMinRarity). pool = { {petName, peso}, ... }
function Stats.LuckWeights(pool, luck)
	local out = {}
	for i, e in ipairs(pool) do
		local def = Config.Pets[e[1]]
		local w = e[2]
		if def and Config.Rarities[def.Rarity].Order >= Config.LuckMinRarity then w *= luck end
		out[i] = { e[1], w }
	end
	return out
end

-- Probabilidades (0..1) de un huevo con suerte aplicada, renormalizadas: { [petName] = p }
function Stats.EggChances(pool, luck)
	local weights = Stats.LuckWeights(pool, luck or 1)
	local total = 0
	for _, e in ipairs(weights) do total += e[2] end
	local out = {}
	for _, e in ipairs(weights) do out[e[1]] = (out[e[1]] or 0) + e[2] / total end
	return out
end

return Stats
