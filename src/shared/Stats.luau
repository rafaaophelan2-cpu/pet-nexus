-- Pet Nexus: stats centralizados. Funciones puras: solo leen los datos del jugador (data) y Config, no tocan instancias.
-- Las usa el servidor para decidir todo y el cliente para mostrar valores. Regla y definiciones en Config.StatDefs:
--   final = Base x (1 + bonus de mejora) x (1 + suma de bonus de encantamiento de las mascotas EQUIPADAS)
local Config = require(script.Parent.Config)

local Stats = {}

-- Multiplicador de la variante de una mascota (Normal = x1)
function Stats.VariantMultiplier(variant)
	local v = Config.PetVariants[variant or Config.DefaultVariant]
	return v and v.Multiplier or 1
end

-- Poder real de una mascota (base x variante)
function Stats.PetPower(pet)
	local def = Config.Pets[pet.Name]
	if not def then return 0 end
	return def.Power * Stats.VariantMultiplier(pet.Variant)
end

-- Poder total de las mascotas equipadas (con rebirths): es lo que daña a los rompibles
function Stats.Power(data)
	local total = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then total += Stats.PetPower(pet) end
	end
	return total * (1 + (data.Rebirths or 0) * Config.RebirthBonus)
end

-- Bonus del encantamiento de UNA mascota sobre una stat, ya multiplicado por su variante (0 si no aplica)
function Stats.PetEnchantBonus(pet, stat)
	local e = pet.Enchant
	if type(e) ~= "table" then return 0 end
	local def = Config.Enchants[e.Id]
	if not def or def.Stat ~= stat then return 0 end
	local bonus = def.Levels[e.Level]
	if not bonus then return 0 end
	return bonus * Stats.VariantMultiplier(pet.Variant)
end

-- Suma de bonus de encantamiento de las mascotas equipadas para una stat
function Stats.EnchantSum(data, stat)
	local sum = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then sum += Stats.PetEnchantBonus(pet, stat) end
	end
	return sum
end

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

function Stats.Base(data, stat)
	local def = Config.StatDefs[stat]
	local base = def.Base
	if def.Rebirths then base *= 1 + (data.Rebirths or 0) * Config.RebirthBonus end
	return base
end

-- Cantidad máxima de mascotas equipadas (entero)
function Stats.MaxEquipped(data)
	return Config.MaxEquipped + Stats.UpgradeBonus(data, "MaxEquipped")
end

-- Valor final de una stat. dim solo importa para las mejoras por dimensión (Coins).
function Stats.Get(data, stat, dim)
	if stat == "MaxEquipped" then return Stats.MaxEquipped(data) end
	assert(Config.StatDefs[stat], "stat desconocida: " .. tostring(stat))
	return Stats.Base(data, stat) * (1 + Stats.UpgradeBonus(data, stat, dim)) * (1 + Stats.EnchantSum(data, stat))
end

-- Todas las stats de un jugador (para debug y para la UI futura). Coins usa la dimensión dada.
function Stats.Compute(data, dim)
	local out = { MaxEquipped = Stats.MaxEquipped(data), Power = Stats.Power(data) }
	for stat in pairs(Config.StatDefs) do
		out[stat] = Stats.Get(data, stat, dim)
	end
	return out
end

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
