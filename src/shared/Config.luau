-- Pet Nexus: configuración central (compartida servidor/cliente)
local Config = {}

Config.MaxEquipped = 4
Config.MaxInventory = 60
Config.PityThreshold = 40 -- aperturas sin Rare+ antes de garantizar uno
Config.DamageTick = 0.25
Config.TargetRange = 45
Config.TeleportCooldown = 3
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
}

-- Esencia AFK (Zona de Meditación = Parts con tag "MeditationZone"). La otorga solo el servidor y NO se puede tradear:
-- vive como número en los datos del jugador y ningún remote la escribe; un futuro trade solo debe mover data.Pets.
-- (valores provisionales)
Config.Meditation = {
	SecondsPerEssence = 60, -- 1 Esencia por minuto dentro de la zona
	Cap = 35,               -- tope por ciclo (35 Esencia = 35 min AFK)
	Cooldown = 3600,        -- recarga al llegar al tope: 1 h que solo avanza mientras el jugador está conectado
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

Config.Breakables = {
	Coins      = { HP = 6,   Reward = 3,   Weight = 65 },
	Chest      = { HP = 45,  Reward = 28,  Weight = 28 },
	GiantChest = { HP = 300, Reward = 220, Weight = 7 },
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
	if math.abs(pos.X - d.Origin.X) > d.ZoneWidth / 2 + 10 then return nil end
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
