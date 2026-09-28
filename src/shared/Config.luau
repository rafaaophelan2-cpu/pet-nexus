-- Pet Nexus: configuración central (compartida servidor/cliente)
local Config = {}

Config.MaxEquipped = 4 -- base; la mejora PetsEquipped suma encima (ver Stats.MaxEquipped)
Config.MaxInventory = 60
Config.HatchCooldown = 0.8 -- segundos entre aperturas de huevo (base; la stat HatchSpeed lo divide)
Config.BaseWalkSpeed = 16 -- velocidad de caminar base del jugador (la de Roblox por defecto)
Config.RebirthBonus = 0.5 -- cada rebirth suma +50% al poder de las mascotas y a las monedas
Config.PityThreshold = 40 -- aperturas sin Rare+ antes de garantizar uno
Config.DamageTick = 0.25
Config.TargetRange = 45
Config.TeleportCooldown = 3
-- segundos mínimos entre peticiones de cada remote nuevo (anticheat)
Config.RateLimits = { Enchant = 0.3, AutoEnchant = 1, Upgrade = 0.4, Variant = 0.5 }
Config.AreasPerWorld = 20
Config.ShowPlannedMachines = true -- vista previa de íconos de máquinas aún no construidas (apagar antes de publicar)

Config.Rarities = {
	Common    = { Order = 1, Color = Color3.fromRGB(210, 210, 215) },
	Uncommon  = { Order = 2, Color = Color3.fromRGB(95, 225, 115) },
	Rare      = { Order = 3, Color = Color3.fromRGB(70, 155, 255) },
	Epic      = { Order = 4, Color = Color3.fromRGB(185, 90, 255) },
	Legendary = { Order = 5, Color = Color3.fromRGB(255, 195, 40) },
}

-- Mascotas del mundo Nexus
Config.Pets = {
	Sprout      = { Rarity = "Common",    Power = 1,   Color = Color3.fromRGB(150, 235, 140) },
	Bunny       = { Rarity = "Common",    Power = 2,   Color = Color3.fromRGB(255, 225, 240) },
	Fox         = { Rarity = "Uncommon",  Power = 4,   Color = Color3.fromRGB(255, 160, 80) },
	Owl         = { Rarity = "Rare",      Power = 9,   Color = Color3.fromRGB(200, 170, 255) },
	Fawn        = { Rarity = "Uncommon",  Power = 7,   Color = Color3.fromRGB(240, 200, 160) },
	CloudCat    = { Rarity = "Rare",      Power = 16,  Color = Color3.fromRGB(235, 240, 255) },
	StarStag    = { Rarity = "Epic",      Power = 40,  Color = Color3.fromRGB(255, 225, 140) },
	NexusDragon = { Rarity = "Legendary", Power = 150, Color = Color3.fromRGB(130, 220, 255) },
}

-- Nombre visible de una mascota: usa def.Display si existe; si no, separa el CamelCase ("NexusDragon" -> "Nexus Dragon")
function Config.PetName(id)
	local def = Config.Pets[id]
	if def and def.Display then return def.Display end
	local s = tostring(id):gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
	return s
end

-- Probabilidades en % (se muestran al jugador). Zone 1 = disponible desde el inicio (lobby).
Config.Eggs = {
	NexusEgg = {
		Display = "Nexus Egg", Dimension = "Nexus", Zone = 1, Price = 100,
		Color = Color3.fromRGB(160, 225, 255),
		Pets = { {"Sprout", 60}, {"Bunny", 30}, {"Fox", 9}, {"Owl", 1} },
	},
	CottonEgg = {
		Display = "Cotton Egg", Dimension = "Nexus", Zone = 2, Price = 2000,
		Color = Color3.fromRGB(255, 185, 225),
		Pets = { {"Fawn", 62}, {"CloudCat", 30}, {"StarStag", 7.5}, {"NexusDragon", 0.5} },
	},
}

-- Moneda propia de cada mundo (modelo 3D en PetNexusAssets.Currency e ícono en Icons)
Config.Currencies = {
	Nexus = { Name = "Angel Coins", Short = "Angel", Model = "AngelCoin", Icon = "AngelCoin", Color = Color3.fromRGB(255, 236, 170) },
}
function Config.CurrencyOf(dim)
	return Config.Currencies[dim] or Config.Currencies.Nexus
end

-- Máquinas / servicios que aparecen como íconos en las tarjetas del menú de TP
Config.Machines = {
	Shop       = { Icon = "Shop",       Name = "Tienda",             Built = false },
	FreeGift   = { Icon = "FreeGift",   Name = "Regalo gratis",      Built = false },
	Golden     = { Icon = "Golden",     Name = "Máquina Dorada",     Built = false },
	Meditation = { Icon = "Meditation", Name = "Zona de Meditación", Built = false },
	Rainbow    = { Icon = "Rainbow",    Name = "Máquina Arcoíris",   Built = false },
	Void       = { Icon = "Void",       Name = "Máquina Void",       Built = false }, -- aún sin área (agregar "Void" a Features)
}

-- Área del mundo donde está una máquina (la primera que la tenga en Features; LobbyFeatures cuenta como área 1).
-- nil = esa máquina no existe en ese mundo.
function Config.MachineArea(dim, machineId)
	local d = Config.Dimensions[dim]
	if not d then return nil end
	for i, a in ipairs(d.Areas) do
		for _, f in ipairs(a.Features or {}) do
			if f == machineId then return i end
		end
	end
	for _, f in ipairs(d.LobbyFeatures or {}) do
		if f == machineId then return 1 end
	end
	return nil
end

-- Esencia AFK (Zona de Meditación = Parts con tag "MeditationZone"). La otorga solo el servidor y NO se puede tradear:
-- vive como número en los datos del jugador y ningún remote la escribe; un futuro trade solo debe mover data.Pets.
-- Tope de 15 min: Roblox expulsa tras 20 min sin input, así el ciclo se puede completar 100% AFK.
Config.Meditation = {
	SecondsPerEssence = 1,  -- 1 Esencia por segundo dentro de la zona (x multiplicador)
	Cap = 900,              -- tope de Esencia por ciclo (sin multiplicador): 900 x 1 s = 15 min de meditación
	Cooldown = 1800,        -- recarga al llegar al tope: 30 min que solo avanzan mientras el jugador está conectado
	BaseMultiplier = 1,     -- base de la stat Essence (x1); los encantamientos Essence Master la suben (ver Config.StatDefs)
}

---------------------------------------------------------------- stats (cálculo en Stats.luau)
-- Regla: final = Base x (1 + bonus de mejora) x (1 + suma de bonus de encantamiento de las mascotas EQUIPADAS).
-- El bonus de encantamiento de cada mascota se multiplica por el multiplicador de su variante.
-- MaxEquipped es aparte (entero): Config.MaxEquipped + mascotas extra de la mejora PetsEquipped.
-- Rebirths = true: la base además se multiplica por (1 + Rebirths x RebirthBonus), como ya pasaba con las monedas.
Config.StatDefs = {
	Coins      = { Base = 1, Rebirths = true },      -- monedas del mundo al romper (la mejora Coins es por dimensión)
	Diamonds   = { Base = 1 },                       -- diamantes que se ganan
	Essence    = { Base = Config.Meditation.BaseMultiplier }, -- Esencia de la Zona de Meditación
	Luck       = { Base = 1 },                       -- suerte al abrir huevos (ver LuckMinRarity)
	WalkSpeed  = { Base = Config.BaseWalkSpeed },    -- studs/s del jugador
	PetSpeed   = { Base = 1 },                       -- velocidad de las mascotas (el servidor no la usa: queda para el cliente)
	BreakSpeed = { Base = 1 },                       -- multiplica el daño por segundo a los rompibles (Haste)
	HatchSpeed = { Base = 1 },                       -- divide Config.HatchCooldown
}

-- Suerte al abrir huevos: cada mascota con rareza de Order >= LuckMinRarity multiplica su peso por Luck; las demás quedan
-- igual; luego se renormaliza: P(i) = w'(i) / suma(w'). Con Luck = 1 no cambia nada.
-- La tarjeta del huevo sigue mostrando las probabilidades base.
Config.LuckMinRarity = 3 -- Rare o superior

---------------------------------------------------------------- variantes de mascota
-- Excluyentes (una sola por mascota, pet.Variant). Multiplican el Power de la mascota y el bonus de su encantamiento.
Config.DefaultVariant = "Normal"
Config.PetVariants = {
	Normal  = { Order = 1, Multiplier = 1 },
	Golden  = { Order = 2, Multiplier = 1.5 },
	Rainbow = { Order = 3, Multiplier = 2 },
	Void    = { Order = 4, Multiplier = 3 },
}

-- PROVISIONAL: recetas de las máquinas de variantes. Se entregan Pets mascotas iguales (mismo Name) de la variante From;
-- la primera de la lista se conserva (con su encantamiento) y pasa a la variante nueva, las demás se consumen.
-- Machine = id de Config.Machines: se usa en el área del mundo que la tenga en Features (hay que tenerla desbloqueada).
-- Currency: "Dimension" = moneda del mundo de la máquina, "Diamonds" = diamantes.
Config.VariantRecipes = {
	Golden  = { From = "Normal",  Pets = 5, Machine = "Golden",  Currency = "Dimension", Price = 5000 },
	Rainbow = { From = "Golden",  Pets = 5, Machine = "Rainbow", Currency = "Dimension", Price = 250000 },
	Void    = { From = "Rainbow", Pets = 5, Machine = "Void",    Currency = "Diamonds",  Price = 1000 },
}

---------------------------------------------------------------- encantamientos
-- 1 slot por mascota: pet.Enchant = { Id, Level } o nil. Encantar reemplaza el actual.
-- Tirada: 1) tier según Weight de EnchantTiers; 2) encantamiento del tier según su Weight (default 1);
-- 3) nivel según LevelWeights del encantamiento (o EnchantLevelWeights recortado a su cantidad de niveles).
-- Levels[n] = bonus del nivel n (0.2 = +20%) sobre la stat Stat (clave de StatDefs).
-- Para agregar: un tier nuevo en EnchantTiers y/o una entrada nueva en Enchants con Tier, Stat, Name y Levels.
Config.EnchantTiers = {
	Normal = { Order = 1, Weight = 97 },
	Rare   = { Order = 2, Weight = 3 }, -- 3% de las tiradas
}
Config.EnchantLevelWeights = { 45, 27, 15, 9, 4 } -- niveles altos menos probables
Config.Enchants = {
	Coins         = { Order = 1, Tier = "Normal", Stat = "Coins",      Name = "Coins",          Levels = { 0.2, 0.4, 0.6, 0.8, 1.0 } },
	Diamonds      = { Order = 2, Tier = "Normal", Stat = "Diamonds",   Name = "Diamonds",       Levels = { 0.2, 0.4, 0.6, 0.8, 1.0 } },
	Speed         = { Order = 3, Tier = "Normal", Stat = "PetSpeed",   Name = "Speed",          Levels = { 0.2, 0.4, 0.6, 0.8, 1.0 } },
	Luck          = { Order = 4, Tier = "Normal", Stat = "Luck",       Name = "Luck",           Levels = { 0.2, 0.4, 0.6, 0.8, 1.0 } },
	Hatcher       = { Order = 5, Tier = "Normal", Stat = "HatchSpeed", Name = "Hatcher",        Levels = { 0.2, 0.4, 0.6, 0.8, 1.0 } },
	Haste         = { Order = 6, Tier = "Normal", Stat = "BreakSpeed", Name = "Haste",          Levels = { 0.2, 0.4, 0.6 } },
	EssenceMaster = { Order = 7, Tier = "Rare",   Stat = "Essence",    Name = "Essence Master", Levels = { 0.5, 1.0, 2.0 } },
}
Config.EnchantCost = 25 -- PROVISIONAL: diamantes por tirada (manual o automática)
Config.AutoEnchant = { Interval = 0.5 } -- segundos entre tiradas del auto enchant (no instantáneo)

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
function Config.EnchantLabel(id, level)
	local def = Config.Enchants[id]
	return (def and def.Name or tostring(id)) .. " " .. (ROMAN[level] or tostring(level))
end

---------------------------------------------------------------- mejoras (máquina de mejoras)
-- Levels[n].Bonus = bonus TOTAL con el nivel n (no se suman entre niveles). Stat = clave de StatDefs, o "MaxEquipped"
-- (Bonus = mascotas extra). Unlock = true: la mejora solo desbloquea algo (AutoEnchant: nivel 1 = desbloqueado).
-- PerDimension = se compra y aplica por mundo (Coins de Nexus solo afecta a Angel Coins): se paga en la moneda de ese mundo
-- y el precio se escala con Config.UpgradePriceScale(dim). Las globales se compran en la máquina del mundo Dimension.
-- Currency: "Dimension" (moneda del mundo de la máquina) o "Diamonds".
-- PROVISIONAL: todos los precios. Diamonds, PetsEquipped y AutoEnchant se pagan con diamantes (son de progreso global).
Config.Upgrades = {
	WalkSpeed = { Order = 1, Name = "Velocidad", Stat = "WalkSpeed", Dimension = "Nexus", Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 500 }, { Bonus = 0.25, Price = 5000 }, { Bonus = 0.50, Price = 50000 }, { Bonus = 0.75, Price = 500000 },
	} },
	Coins = { Order = 2, Name = "Monedas", Stat = "Coins", PerDimension = true, Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 1000 }, { Bonus = 0.25, Price = 10000 }, { Bonus = 0.50, Price = 100000 }, { Bonus = 0.75, Price = 1000000 },
	} },
	Diamonds = { Order = 3, Name = "Diamantes", Stat = "Diamonds", Dimension = "Nexus", Currency = "Diamonds", Levels = {
		{ Bonus = 0.10, Price = 50 }, { Bonus = 0.25, Price = 250 }, { Bonus = 0.50, Price = 1000 }, { Bonus = 0.75, Price = 5000 },
	} },
	Luck = { Order = 4, Name = "Suerte", Stat = "Luck", Dimension = "Nexus", Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 2000 }, { Bonus = 0.25, Price = 20000 }, { Bonus = 0.50, Price = 200000 }, { Bonus = 0.75, Price = 2000000 },
	} },
	PetsEquipped = { Order = 5, Name = "Mascotas equipadas", Stat = "MaxEquipped", Dimension = "Nexus", Currency = "Diamonds", Levels = {
		{ Bonus = 1, Price = 2500 },
	} },
	AutoEnchant = { Order = 6, Name = "Auto Enchant", Unlock = true, Dimension = "Nexus", Currency = "Diamonds", Levels = {
		{ Price = 1000 },
	} },
}

-- Orden de mundos (menú de TP). Solo los que están en Config.Dimensions son jugables.
Config.DimensionList = {
	{ Id = "Nexus",      Display = "Nexus",      Color = Color3.fromRGB(130, 210, 255), Lobby = "Nexus Plaza",    Vehicle = "Nexus Airship" },
	{ Id = "Eden",       Display = "Eden",       Color = Color3.fromRGB(120, 220, 110), Lobby = "Eden Sanctuary", Vehicle = "Campana de buceo" },
	{ Id = "Atlantis",   Display = "Atlantis",   Color = Color3.fromRGB(90, 190, 255),  Lobby = "Atlantis Dome",  Vehicle = "Burbuja de chicle" },
	{ Id = "Candyverse", Display = "Candyverse", Color = Color3.fromRGB(255, 140, 210), Lobby = "Candy Plaza",    Vehicle = "Candy Express" },
	{ Id = "NeonCity",   Display = "Neon City",  Color = Color3.fromRGB(170, 100, 255), Lobby = "Neon Hub",       Vehicle = "Arcade gigante" },
	{ Id = "Glitch",     Display = "Glitch",     Color = Color3.fromRGB(80, 240, 190),  Lobby = "Glitch Lobby" },
}

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

-- Mundos jugables. Areas[i] = { Name, Plot (color de la parcela), Features = {ids de Config.Machines} }
Config.Dimensions = {
	Nexus = {
		Order = 1,
		Origin = Vector3.new(0, 0, 200), -- centro del área 1
		LobbyCenter = Vector3.new(0, 0, 40),
		ZoneCount = 20,
		AreasBuilt = 2, -- áreas con mapa construido (las demás se ven como "Próximamente")
		ZoneLength = 140,
		ZoneWidth = 126,
		PlotWidth = 96,
		PlotLength = 104,
		LobbyFeatures = { "Shop" },
		NextWorld = { Dim = "Eden", Essence = 100 }, -- el vehículo requiere Esencia (costo único)
		Areas = {
			{ Name = "Sky Spawn",        Plot = C(150, 235, 160) },
			{ Name = "Cotton Fields",    Plot = C(255, 185, 215) },
			{ Name = "Crystal Garden",   Plot = C(165, 215, 255) },
			{ Name = "Rainbow Bridge",   Plot = C(205, 185, 255), Features = { "FreeGift" } },
			{ Name = "Star Castle",      Plot = C(255, 230, 145) },
			{ Name = "Moon Meadow",      Plot = C(175, 165, 235) },
			{ Name = "Portal Park",      Plot = C(135, 225, 215) },
			{ Name = "Aurora Falls",     Plot = C(155, 240, 200), Features = { "Golden" } },
			{ Name = "Floating Isles",   Plot = C(175, 230, 145) },
			{ Name = "Sun Temple",       Plot = C(255, 210, 120), Features = { "Meditation" } },
			{ Name = "Cloud Harbor",     Plot = C(185, 220, 255) },
			{ Name = "Prism Peaks",      Plot = C(240, 195, 255) },
			{ Name = "Starlight Market", Plot = C(255, 195, 165) },
			{ Name = "Comet Crater",     Plot = C(195, 180, 225) },
			{ Name = "Nebula Grove",     Plot = C(205, 160, 240) },
			{ Name = "Crystal Caverns",  Plot = C(145, 205, 250), Features = { "Rainbow" } },
			{ Name = "Sky Lighthouse",   Plot = C(255, 215, 190) },
			{ Name = "Orbit Station",    Plot = C(185, 205, 235) },
			{ Name = "Galaxy Gate",      Plot = C(160, 150, 225) },
			{ Name = "Nexus Core",       Plot = C(125, 230, 255) },
		},
	},
}

function Config.WorldInfo(dim)
	for _, d in ipairs(Config.DimensionList) do
		if d.Id == dim then return d end
	end
end

function Config.AreaName(dim, i)
	local d = Config.Dimensions[dim]
	local a = d and d.Areas and d.Areas[i]
	return a and a.Name or ("Area " .. i)
end

-- Índice global del área (mundo 2 área 1 = 21): define precio y multiplicador
function Config.GlobalIndex(dim, i)
	local d = Config.Dimensions[dim]
	local order = d and d.Order or 1
	return (order - 1) * Config.AreasPerWorld + i
end

-- (valores provisionales: rebalancear cuando haya más huevos/mascotas)
function Config.ZonePrice(dim, i)
	local g = Config.GlobalIndex(dim, i)
	if g <= 1 then return 0 end
	return math.floor(150 * (1.9 ^ (g - 2)))
end

function Config.ZoneMultiplier(dim, i)
	return 1.65 ^ (Config.GlobalIndex(dim, i) - 1)
end

-- Escala de precio de las mejoras por dimensión (PerDimension): sigue a la economía de cada mundo (Nexus = x1)
function Config.UpgradePriceScale(dim)
	return Config.ZoneMultiplier(dim, 1)
end

-- DiamondChance / Diamonds (PROVISIONAL): al romperse, cada jugador que le hizo daño tira DiamondChance y si sale
-- gana Diamonds x su multiplicador de Diamonds. Los diamantes son globales (data.Diamonds), no por mundo.
Config.Breakables = {
	Coins      = { HP = 6,   Reward = 3,   Weight = 65, DiamondChance = 0.02, Diamonds = 1 },
	Chest      = { HP = 45,  Reward = 28,  Weight = 28, DiamondChance = 0.15, Diamonds = 2 },
	GiantChest = { HP = 300, Reward = 220, Weight = 7,  DiamondChance = 1,    Diamonds = 10 },
}
Config.BreakablesPerZone = 22

function Config.ZoneCenter(dimension, i)
	local d = Config.Dimensions[dimension]
	return d.Origin + Vector3.new(0, 0, (i - 1) * d.ZoneLength)
end

-- Punto de llegada al teletransportarse a un área (en el camino, justo antes de la parcela)
function Config.ZoneEntry(dimension, i)
	local d = Config.Dimensions[dimension]
	return Config.ZoneCenter(dimension, i) - Vector3.new(0, 0, d.PlotLength / 2 + 7)
end

function Config.LobbySpawn(dimension)
	local d = Config.Dimensions[dimension]
	return d.LobbyCenter - Vector3.new(0, 0, 30)
end

function Config.ZoneFromPosition(dimension, pos)
	local d = Config.Dimensions[dimension]
	if math.abs(pos.X - d.Origin.X) > 130 then return nil end -- todo el ancho del mundo (camino + islas laterales), no solo el camino
	local rel = pos.Z - d.Origin.Z + d.ZoneLength / 2
	local i = math.floor(rel / d.ZoneLength) + 1
	if i < 1 or i > d.ZoneCount then return nil end
	return i
end

function Config.FormatNumber(n)
	n = math.floor(n)
	local suffixes = {"", "K", "M", "B", "T", "Qa"}
	local i = 1
	local v = n
	while v >= 1000 and i < #suffixes do
		v = v / 1000
		i += 1
	end
	if i == 1 then return tostring(n) end
	return string.format(v < 10 and "%.2f%s" or (v < 100 and "%.1f%s" or "%.0f%s"), v, suffixes[i])
end

return Config
