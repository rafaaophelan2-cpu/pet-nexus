-- Pet Nexus: configuración central (compartida servidor/cliente)
local Config = {}

Config.MaxEquipped = 3 -- base; suman la mejora PetsEquipped, los rebirths y los gamepasses (ver Stats.MaxEquipped)
Config.MaxInventory = 60
Config.HatchCooldown = 0.8 -- segundos entre aperturas de huevo (base; la stat HatchSpeed lo divide)
Config.BaseWalkSpeed = 16 -- velocidad de caminar base del jugador (la de Roblox por defecto)
Config.PityThreshold = 40 -- aperturas sin Rare+ antes de garantizar uno
Config.DamageTick = 0.25
Config.TargetRange = 45
Config.TeleportCooldown = 3
-- segundos mínimos entre peticiones de cada remote (anticheat)
Config.RateLimits = {
	Enchant = 0.3, AutoEnchant = 1, Upgrade = 0.4, Variant = 0.5,
	Rebirth = 2, Rank = 0.4, Potion = 0.3, FreePotions = 1, Prompt = 1,
}
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
-- PROVISIONAL: Greenwood usa los modelos de Angel Coin hasta que existan los suyos (Model "<X>" + Breakables "<X>Pile" + ícono).
-- PLANTILLA DE MONEDA: todas comparten la misma forma (moneda gruesa con borde y una huella de mascota en el centro);
-- cada mundo cambia color y detalles propios (Greenwood: oro con hojas y bellota; Nexus: blanco perla con halo y alitas).
-- Modelos en ReplicatedStorage.PetNexusAssets.Currency/<Model> e íconos en .Icons/<Icon> (generados con el mismo prompt base).
Config.Currencies = {
	Greenwood = { Name = "Coins", Short = "Coins", Model = "Coin", Icon = "Coin", Color = Color3.fromRGB(255, 214, 90) },
	Nexus = { Name = "Angel Coins", Short = "Angel", Model = "AngelCoin", Icon = "AngelCoin", Color = Color3.fromRGB(255, 236, 170) },
}
function Config.CurrencyOf(dim)
	return Config.Currencies[dim] or Config.Currencies.Nexus
end

-- Máquinas / servicios que aparecen como íconos en las tarjetas del menú de TP.
-- Features sin entrada aquí (Rebirth, PotionShrine, Vehicle) marcan dónde van en el mapa pero no muestran ícono.
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
	BaseMultiplier = 1,     -- base de la stat Essence (x1); la suben Essence Master y el gamepass Double Essence
}

---------------------------------------------------------------- stats (cálculo en Stats.luau)
-- Regla (cada factor es 1 + la SUMA de los bonus de esa fuente; las fuentes se multiplican entre sí):
--   final = Base x (1 + mejora) x (1 + encantamientos de las mascotas EQUIPADAS) x (1 + rebirths) x (1 + rango)
--                x (1 + gamepasses) x (1 + pociones activas)
-- El bonus de encantamiento de cada mascota se multiplica por su variante y por su nivel (ver PetLevels).
-- Ejemplo: Double Coins (+100%) y VIP (+100%) son la misma fuente: x3; con Rebirth 1 (+100%): x6.
-- MaxEquipped es aparte (entero): Config.MaxEquipped + mejora PetsEquipped + rebirths + gamepasses.
Config.StatDefs = {
	Coins      = { Base = 1 },                       -- monedas al romper (la mejora Coins es por dimensión; el resto, universal)
	Diamonds   = { Base = 1 },                       -- diamantes que se ganan
	Essence    = { Base = Config.Meditation.BaseMultiplier }, -- Esencia de la Zona de Meditación
	Luck       = { Base = 1 },                       -- suerte al abrir huevos (ver LuckMinRarity)
	WalkSpeed  = { Base = Config.BaseWalkSpeed },    -- studs/s del jugador
	PetSpeed   = { Base = 1 },                       -- velocidad de las mascotas (el servidor no la usa: queda para el cliente)
	BreakSpeed = { Base = 1 },                       -- multiplica el daño por segundo a los rompibles (Haste)
	HatchSpeed = { Base = 1 },                       -- divide Config.HatchCooldown
	XP         = { Base = 1 },                       -- multiplica la XP que ganan las mascotas (Double XP)
}

-- Suerte al abrir huevos: cada mascota con rareza de Order >= LuckMinRarity multiplica su peso por Luck; las demás quedan
-- igual; luego se renormaliza: P(i) = w'(i) / suma(w'). Con Luck = 1 no cambia nada.
-- La tarjeta del huevo sigue mostrando las probabilidades base.
Config.LuckMinRarity = 3 -- Rare o superior

---------------------------------------------------------------- niveles de mascota (XP)
-- Al romper algo, CADA mascota equipada de cada jugador que hizo daño gana Breakables[tipo].XP x stat XP (no se divide).
-- Nivel L da +L x BonusPerLevel al poder y al bonus de encantamiento de esa mascota (nivel 50 = +50%).
-- Las mascotas nacen en StartLevel. XP para subir del nivel L al L+1 = floor(XPBase x XPGrowth^(L - 1)).
-- PROVISIONAL: la curva (del 1 al 50 son ~107.000 XP).
Config.PetLevels = {
	StartLevel = 1,
	MaxLevel = 50,
	BonusPerLevel = 0.01,
	XPBase = 50,
	XPGrowth = 1.12,
}

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
-- y el precio se escala con Config.UpgradePriceScale(dim). Las globales se compran en la máquina del mundo Dimension;
-- sin Dimension = el mundo inicial (Config.SpawnWorld(): hoy Nexus, Greenwood cuando esté construido).
-- Currency: "Dimension" (moneda del mundo de la máquina) o "Diamonds".
-- PROVISIONAL: todos los precios. Diamonds, PetsEquipped y AutoEnchant se pagan con diamantes (son de progreso global).
Config.Upgrades = {
	WalkSpeed = { Order = 1, Name = "Velocidad", Stat = "WalkSpeed", Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 500 }, { Bonus = 0.25, Price = 5000 }, { Bonus = 0.50, Price = 50000 }, { Bonus = 0.75, Price = 500000 },
	} },
	Coins = { Order = 2, Name = "Monedas", Stat = "Coins", PerDimension = true, Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 1000 }, { Bonus = 0.25, Price = 10000 }, { Bonus = 0.50, Price = 100000 }, { Bonus = 0.75, Price = 1000000 },
	} },
	Diamonds = { Order = 3, Name = "Diamantes", Stat = "Diamonds", Currency = "Diamonds", Levels = {
		{ Bonus = 0.10, Price = 50 }, { Bonus = 0.25, Price = 250 }, { Bonus = 0.50, Price = 1000 }, { Bonus = 0.75, Price = 5000 },
	} },
	Luck = { Order = 4, Name = "Suerte", Stat = "Luck", Currency = "Dimension", Levels = {
		{ Bonus = 0.10, Price = 2000 }, { Bonus = 0.25, Price = 20000 }, { Bonus = 0.50, Price = 200000 }, { Bonus = 0.75, Price = 2000000 },
	} },
	PetsEquipped = { Order = 5, Name = "Mascotas equipadas", Stat = "MaxEquipped", Currency = "Diamonds", Levels = {
		{ Bonus = 1, Price = 2500 },
	} },
	AutoEnchant = { Order = 6, Name = "Auto Enchant", Unlock = true, Currency = "Diamonds", Levels = {
		{ Price = 1000 },
	} },
}

---------------------------------------------------------------- rebirths (uno por mundo, en su área Area)
-- Requisito: tener desbloqueada el área Area de ese mundo y haber hecho los rebirths anteriores (Number en orden).
-- Sin costo. Reinicia SOLO la moneda de ese mundo y sus áreas (vuelve al área 1); con el gamepass Rebirth+ no reinicia nada.
-- Bonus: por stat (0.5 = +50%, se suma con los demás rebirths) y MaxEquipped = mascotas extra. Unlocks.Rank = abre el rango.
-- Se valida cerca de una Part con tag "RebirthStatue" y atributo Dimension (a menos de RebirthRange studs).
Config.Rebirths = {
	Greenwood = { Number = 1, Area = 10, Bonus = { Coins = 1.0, Diamonds = 0.5, Luck = 0.5, MaxEquipped = 1 }, Unlocks = { Rank = true } },
	Nexus     = { Number = 2, Area = 10, Bonus = {}, Unlocks = {} }, -- PROVISIONAL: beneficios del Rebirth 2 sin definir
}
Config.RebirthRange = 30 -- PROVISIONAL
Config.RebirthAscension = 3 -- segundos que dura la animación de ascensión del cliente antes del teleport del servidor
Config.RebirthGrace = 6 -- segundos en que el anticheat no castiga el vuelo de la ascensión

---------------------------------------------------------------- rango (se desbloquea con un rebirth que tenga Unlocks.Rank)
-- 10 rangos en orden, pagados con DIAMANTES (o con el Developer Product RankSkip<n>, ver Products).
-- Bonus = bonus TOTAL del rango sobre las stats de Ranks.Stats (no se suman entre rangos).
Config.Ranks = {
	Stats = { "Coins", "Diamonds" },
	Levels = {
		{ Bonus = 0.05, Cost = 100 },   { Bonus = 0.10, Cost = 250 },   { Bonus = 0.15, Cost = 500 },
		{ Bonus = 0.20, Cost = 1000 },  { Bonus = 0.30, Cost = 2000 },  { Bonus = 0.40, Cost = 4000 },
		{ Bonus = 0.55, Cost = 7500 },  { Bonus = 0.70, Cost = 12500 }, { Bonus = 0.85, Cost = 20000 },
		{ Bonus = 1.00, Cost = 30000 },
	}, -- PROVISIONAL: Cost (diamantes)
}

---------------------------------------------------------------- gamepasses
-- Id = 0: desactivado (nadie lo tiene). Poner el Id real del Creator Dashboard. Price es informativo (Robux).
-- Bonus: por stat (se suma con los otros gamepasses) y MaxEquipped = mascotas extra.
-- VipAccess: entra a la zona VIP (Parts "VipBarrier" sin colisión para el dueño; región "VipZone" saca a los demás).
-- KeepOnRebirth: el rebirth da los beneficios sin reiniciar nada.
Config.GamePasses = {
	VIP             = { Id = 0, Price = 249, Name = "VIP",               Bonus = { Coins = 1, Diamonds = 1 }, VipAccess = true },
	DoubleCoins     = { Id = 0, Price = 199, Name = "Double Coins",      Bonus = { Coins = 1 } },
	DoubleDiamonds  = { Id = 0, Price = 249, Name = "Double Diamonds",   Bonus = { Diamonds = 1 } },
	GoodLuck        = { Id = 0, Price = 249, Name = "Good Luck",         Bonus = { Luck = 1 } },
	InsaneLuck      = { Id = 0, Price = 499, Name = "Insane Luck",       Bonus = { Luck = 1.5 } },
	RebirthPlus     = { Id = 0, Price = 599, Name = "Rebirth+",          Bonus = {}, KeepOnRebirth = true },
	PremiumPetEquip = { Id = 0, Price = 399, Name = "Premium Pet Equip", Bonus = { MaxEquipped = 2 } },
	DeluxePetEquip  = { Id = 0, Price = 799, Name = "Deluxe Pet Equip",  Bonus = { MaxEquipped = 4 } },
	DoubleEssence   = { Id = 0, Price = 199, Name = "Double Essence",    Bonus = { Essence = 1 } },
	DoubleXP        = { Id = 0, Price = 149, Name = "Double XP",         Bonus = { XP = 1 } },
}

---------------------------------------------------------------- pociones
-- Cada poción activa suma Bonus a su Stat mientras le quede tiempo. Usar otra del mismo tipo suma Duration.
-- PROVISIONAL: el tiempo solo corre mientras el jugador está conectado (igual que la recarga de la meditación).
Config.Potions = {
	Duration = 1800, -- 30 min por poción
	Types = {
		Luck       = { Order = 1, Name = "Poción de Suerte",       Stat = "Luck",       Bonus = 1 },
		Coins      = { Order = 2, Name = "Poción de Monedas",      Stat = "Coins",      Bonus = 1 },
		Diamonds   = { Order = 3, Name = "Poción de Diamantes",    Stat = "Diamonds",   Bonus = 1 },
		HatchSpeed = { Order = 4, Name = "Poción de Hatch Speed",  Stat = "HatchSpeed", Bonus = 1 },
	},
}

-- Pociones gratis (área 18 de Greenwood): 1 de cada tipo cerca de una Part con tag "PotionShrine".
-- Cooldown en tiempo REAL (os.time: corre también desconectado). Saltable con el producto FreePotionSkip, máx. por día UTC.
Config.FreePotions = { Amount = 1, Cooldown = 3 * 3600, SkipsPerDay = 3, Range = 25 } -- PROVISIONAL: Range

---------------------------------------------------------------- Developer Products
-- Id = 0: sin configurar (no se puede ofrecer). Poner el Id real del Creator Dashboard. Price es informativo (Robux).
-- Kind:
--   Potions        Potions = { [tipo] = cantidad } al inventario
--   RankSkip       da el rango Rank sin diamantes (solo si es el siguiente; si no, compensa con su costo en diamantes)
--   CoinPack       Amount x escala del progreso en el mundo actual (Config.PackScale), en la moneda de ese mundo
--   DiamondPack    Amount x escala del progreso (lineal, más suave)
--   FreePotionSkip reinicia el cooldown de las pociones gratis (máx. FreePotions.SkipsPerDay por día)
-- PROVISIONAL: precios y cantidades de los paquetes de monedas y diamantes.
Config.Products = {
	Potion_Luck_1 = { Id = 0, Price = 9,  Kind = "Potions", Potions = { Luck = 1 } },
	Potion_Luck_3 = { Id = 0, Price = 24, Kind = "Potions", Potions = { Luck = 3 } },
	Potion_Luck_5 = { Id = 0, Price = 36, Kind = "Potions", Potions = { Luck = 5 } },
	Potion_Luck_10 = { Id = 0, Price = 63, Kind = "Potions", Potions = { Luck = 10 } },
	Potion_Coins_1 = { Id = 0, Price = 9,  Kind = "Potions", Potions = { Coins = 1 } },
	Potion_Coins_3 = { Id = 0, Price = 24, Kind = "Potions", Potions = { Coins = 3 } },
	Potion_Coins_5 = { Id = 0, Price = 36, Kind = "Potions", Potions = { Coins = 5 } },
	Potion_Coins_10 = { Id = 0, Price = 63, Kind = "Potions", Potions = { Coins = 10 } },
	Potion_Diamonds_1 = { Id = 0, Price = 9,  Kind = "Potions", Potions = { Diamonds = 1 } },
	Potion_Diamonds_3 = { Id = 0, Price = 24, Kind = "Potions", Potions = { Diamonds = 3 } },
	Potion_Diamonds_5 = { Id = 0, Price = 36, Kind = "Potions", Potions = { Diamonds = 5 } },
	Potion_Diamonds_10 = { Id = 0, Price = 63, Kind = "Potions", Potions = { Diamonds = 10 } },
	Potion_HatchSpeed_1 = { Id = 0, Price = 9,  Kind = "Potions", Potions = { HatchSpeed = 1 } },
	Potion_HatchSpeed_3 = { Id = 0, Price = 24, Kind = "Potions", Potions = { HatchSpeed = 3 } },
	Potion_HatchSpeed_5 = { Id = 0, Price = 36, Kind = "Potions", Potions = { HatchSpeed = 5 } },
	Potion_HatchSpeed_10 = { Id = 0, Price = 63, Kind = "Potions", Potions = { HatchSpeed = 10 } },
	PotionBundle_10 = { Id = 0, Price = 180, Kind = "Potions", Potions = { Luck = 10, Coins = 10, Diamonds = 10, HatchSpeed = 10 } },
	PotionBundle_25 = { Id = 0, Price = 315, Kind = "Potions", Potions = { Luck = 25, Coins = 25, Diamonds = 25, HatchSpeed = 25 } },
	RankSkip1 = { Id = 0, Price = 19,  Kind = "RankSkip", Rank = 1 },
	RankSkip2 = { Id = 0, Price = 49,  Kind = "RankSkip", Rank = 2 },
	RankSkip3 = { Id = 0, Price = 79,  Kind = "RankSkip", Rank = 3 },
	RankSkip4 = { Id = 0, Price = 99,  Kind = "RankSkip", Rank = 4 },
	RankSkip5 = { Id = 0, Price = 149, Kind = "RankSkip", Rank = 5 },
	RankSkip6 = { Id = 0, Price = 199, Kind = "RankSkip", Rank = 6 },
	RankSkip7 = { Id = 0, Price = 249, Kind = "RankSkip", Rank = 7 },
	RankSkip8 = { Id = 0, Price = 299, Kind = "RankSkip", Rank = 8 },
	RankSkip9 = { Id = 0, Price = 349, Kind = "RankSkip", Rank = 9 },
	RankSkip10 = { Id = 0, Price = 399, Kind = "RankSkip", Rank = 10 },
	CoinPack1 = { Id = 0, Price = 25,  Kind = "CoinPack", Amount = 1000 },
	CoinPack2 = { Id = 0, Price = 59,  Kind = "CoinPack", Amount = 3500 },
	CoinPack3 = { Id = 0, Price = 99,  Kind = "CoinPack", Amount = 10000 }, -- 10.000 en el área 1, ~906.000 en el área 10
	CoinPack4 = { Id = 0, Price = 249, Kind = "CoinPack", Amount = 30000 },
	CoinPack5 = { Id = 0, Price = 499, Kind = "CoinPack", Amount = 75000 },
	DiamondPack1 = { Id = 0, Price = 25,  Kind = "DiamondPack", Amount = 100 },
	DiamondPack2 = { Id = 0, Price = 59,  Kind = "DiamondPack", Amount = 300 },
	DiamondPack3 = { Id = 0, Price = 99,  Kind = "DiamondPack", Amount = 600 },
	DiamondPack4 = { Id = 0, Price = 249, Kind = "DiamondPack", Amount = 1800 },
	DiamondPack5 = { Id = 0, Price = 499, Kind = "DiamondPack", Amount = 4500 },
	FreePotionSkip = { Id = 0, Price = 19, Kind = "FreePotionSkip" },
}

-- Escala de los paquetes según el área más alta desbloqueada del mundo actual (area >= 1).
-- Monedas: Config.ZoneMultiplier (la misma curva que las recompensas); diamantes: lineal, +DiamondPerArea por área.
Config.PackScale = { DiamondPerArea = 0.25 } -- PROVISIONAL
Config.ReceiptHistory = 200 -- PurchaseId recordados por jugador para no entregar dos veces

---------------------------------------------------------------- mundos
-- Orden de mundos (menú de TP). Solo los que están en Config.Dimensions son jugables.
Config.DimensionList = {
	{ Id = "Greenwood",  Display = "Greenwood",  Color = Color3.fromRGB(120, 200, 95),  Lobby = "Maple Square",   Vehicle = "Hot Air Balloon" },
	{ Id = "Nexus",      Display = "Nexus",      Color = Color3.fromRGB(130, 210, 255), Lobby = "Nexus Plaza",    Vehicle = "Nexus Airship" },
	{ Id = "Eden",       Display = "Eden",       Color = Color3.fromRGB(120, 220, 110), Lobby = "Eden Sanctuary", Vehicle = "Campana de buceo" },
	{ Id = "Atlantis",   Display = "Atlantis",   Color = Color3.fromRGB(90, 190, 255),  Lobby = "Atlantis Dome",  Vehicle = "Burbuja de chicle" },
	{ Id = "Candyverse", Display = "Candyverse", Color = Color3.fromRGB(255, 140, 210), Lobby = "Candy Plaza",    Vehicle = "Candy Express" },
	{ Id = "NeonCity",   Display = "Neon City",  Color = Color3.fromRGB(170, 100, 255), Lobby = "Neon Hub",       Vehicle = "Arcade gigante" },
	{ Id = "Glitch",     Display = "Glitch",     Color = Color3.fromRGB(80, 240, 190),  Lobby = "Glitch Lobby" },
}

-- Mundo donde empiezan los jugadores nuevos. Mientras no tenga áreas construidas (AreasBuilt = 0) se usa el primer mundo
-- construido por Order (hoy Nexus), así nadie aparece en el vacío: ver Config.SpawnWorld().
-- Para pasar a Greenwood: construir su mapa, subir Dimensions.Greenwood.AreasBuilt y mover los SpawnLocation a Maple Square.
Config.StartWorld = "Greenwood"

local function C(r, g, b) return Color3.fromRGB(r, g, b) end

-- Mundos jugables. Areas[i] = { Name, Plot (color de la parcela), Features = {ids de máquinas / puntos del mapa} }
-- EconomyOrder: posición del mundo en la curva de precios (ver GlobalIndex). Si falta, se usa Order.
-- Trazado (ver "trazado de los mundos"): Origin = centro del área 1, Forward = dirección de avance de las áreas 1..TurnArea.
Config.Dimensions = {
	Greenwood = {
		Order = 1,
		EconomyOrder = 1,
		Origin = Vector3.new(3000, 0, 200), -- PROVISIONAL: lejos de Nexus (el mapa aún no existe)
		Forward = Vector3.new(0, 0, 1),
		LobbyCenter = Vector3.new(3000, 0, 40),
		ZoneCount = 20,
		AreasBuilt = 0, -- el mapa de Greenwood aún no existe
		ZoneLength = 140,
		ZoneWidth = 126,
		PlotWidth = 96,
		PlotLength = 104,
		LobbyFeatures = { "Shop" },
		NextWorld = { Dim = "Nexus", Essence = 100 }, -- Hot Air Balloon en Balloon Field. PROVISIONAL: costo en Esencia
		Areas = {
			{ Name = "Maple Street",    Plot = C(150, 220, 120) },
			{ Name = "Oak Park",        Plot = C(130, 200, 110) },
			{ Name = "Pine Woods",      Plot = C(110, 170, 110) },
			{ Name = "Market Row",      Plot = C(230, 200, 150), Features = { "FreeGift" } },
			{ Name = "Willow Pond",     Plot = C(140, 210, 190) },
			{ Name = "Brick Lane",      Plot = C(210, 150, 130) },
			{ Name = "Birch Forest",    Plot = C(200, 220, 170) },
			{ Name = "Garden Homes",    Plot = C(170, 230, 140), Features = { "Golden" } },
			{ Name = "Old Mill",        Plot = C(200, 180, 140) },
			{ Name = "Golden Square",   Plot = C(250, 220, 120), Features = { "Rebirth" } },
			{ Name = "Downtown",        Plot = C(190, 190, 210) },
			{ Name = "Deep Woods",      Plot = C(90, 150, 100) },
			{ Name = "Campground",      Plot = C(190, 170, 120) },
			{ Name = "School Yard",     Plot = C(230, 190, 150) },
			{ Name = "Riverside",       Plot = C(130, 200, 230) },
			{ Name = "Station Street",  Plot = C(200, 190, 200), Features = { "Rainbow" } },
			{ Name = "Autumn Grove",    Plot = C(240, 160, 90) },
			{ Name = "Lakeside Cabins", Plot = C(150, 200, 220), Features = { "PotionShrine" } },
			{ Name = "Hilltop",         Plot = C(170, 210, 130) },
			{ Name = "Balloon Field",   Plot = C(250, 200, 200), Features = { "Meditation", "Vehicle" } },
		},
	},
	Nexus = {
		Order = 2,
		-- PROVISIONAL: sigue en la curva del mundo 1 (EconomyOrder = 1) para que Nexus funcione igual que hoy.
		-- Con EconomyOrder = 2 (Order real) sus precios se multiplicarían por ~376.000 (1,9^20) y la vida/recompensa
		-- de los rompibles por ~22.400 (1,65^20): las mascotas actuales de Nexus (poder 1-150) no podrían romper nada.
		-- Subirlo a 2 junto con el rebalanceo de huevos/mascotas de Nexus cuando Greenwood esté construido
		-- (y reconstruir las puertas, que muestran el precio horneado).
		EconomyOrder = 1,
		SeedOrder = 1, -- semilla de decoración de WorldBuilder: fija para que Nexus se vea igual al reconstruirlo (antes Order era 1)
		Origin = Vector3.new(0, 0, 200), -- centro del área 1
		Forward = Vector3.new(0, 0, 1),
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
			{ Name = "Sun Temple",       Plot = C(255, 210, 120), Features = { "Meditation", "Rebirth" } },
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

function Config.IsWorldBuilt(dim)
	local d = Config.Dimensions[dim]
	return d ~= nil and (d.AreasBuilt or 0) > 0
end

-- Mundos jugables ordenados por Order
function Config.WorldsByOrder()
	local list = {}
	for id in pairs(Config.Dimensions) do table.insert(list, id) end
	table.sort(list, function(a, b) return Config.Dimensions[a].Order < Config.Dimensions[b].Order end)
	return list
end

-- Mundo donde empieza (y se desbloquea por defecto) un jugador: StartWorld si ya tiene mapa; si no, el primero construido
function Config.SpawnWorld()
	if Config.IsWorldBuilt(Config.StartWorld) then return Config.StartWorld end
	for _, id in ipairs(Config.WorldsByOrder()) do
		if Config.IsWorldBuilt(id) then return id end
	end
	return Config.StartWorld
end

-- Índice global del área (mundo con EconomyOrder 2, área 1 = 21): define precio y multiplicador
function Config.GlobalIndex(dim, i)
	local d = Config.Dimensions[dim]
	local order = d and (d.EconomyOrder or d.Order) or 1
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
-- XP (PROVISIONAL): la que gana cada mascota equipada de cada jugador que le hizo daño (ver PetLevels).
Config.Breakables = {
	Coins      = { HP = 6,   Reward = 3,   Weight = 65, DiamondChance = 0.02, Diamonds = 1,  XP = 1 },
	Chest      = { HP = 45,  Reward = 28,  Weight = 28, DiamondChance = 0.15, Diamonds = 2,  XP = 6 },
	GiantChest = { HP = 300, Reward = 220, Weight = 7,  DiamondChance = 1,    Diamonds = 10, XP = 30 },
}
Config.BreakablesPerZone = 22
-- Modelos de rompibles por mundo (ReplicatedStorage.PetNexusAssets.Breakables). Sin entrada: <Moneda>Pile / AngelGift / HeavenChest.
Config.BreakableModels = {
	Greenwood = { Coins = "CoinPile", Chest = "WoodGift", GiantChest = "WoodChest" },
}

---------------------------------------------------------------- trazado de los mundos
-- Áreas 1..TurnArea en línea recta hacia Forward. El área TurnArea es una esquina más grande: el camino gira 90° a la
-- DERECHA y las áreas siguientes siguen rectas en esa dirección. Todo en el plano horizontal (Y = Origin.Y).
-- Ejes de un área: "adelante" = hacia donde se camina, "derecha" = adelante x arriba (mirando +Z, la derecha es -X).
--   Área recta: rectángulo de 2 x HalfWidth (camino + islas laterales) por ZoneLength, centrado en su centro.
--   Esquina: su centro es el punto de giro (misma posición que tendría en línea recta). Va desde la puerta
--   (ZoneLength/2 atrás) hasta CornerFront adelante, y desde CornerLeft a la izquierda hasta HalfWidth a la derecha,
--   donde empieza la siguiente área. Lo que queda adelante y a la izquierda del camino es la plaza (estatua de Rebirth).
-- Cada mundo puede sobrescribir estos valores en su entrada de Dimensions.
Config.Layout = {
	HalfWidth = 130,
	TurnArea = 10,
	CornerFront = 190, -- PROVISIONAL
	CornerLeft = 190,  -- PROVISIONAL
}
Config.GateBuyRange = 60 -- PROVISIONAL: distancia máxima (horizontal) a la puerta para comprar el área

local UP = Vector3.new(0, 1, 0)

local function layoutValue(d, key)
	local v = d[key]
	if v == nil then v = Config.Layout[key] end
	return v
end

-- Dirección de avance y derecha (vectores unitarios) del área i
function Config.AreaDirections(dim, i)
	local d = Config.Dimensions[dim]
	local f = d.Forward or Vector3.new(0, 0, 1)
	if i > layoutValue(d, "TurnArea") then f = f:Cross(UP) end
	return f, f:Cross(UP)
end

-- Centro del área i (Vector3). En la esquina es el punto de giro.
function Config.ZoneCenter(dim, i)
	local d = Config.Dimensions[dim]
	local L = d.ZoneLength
	local f0 = d.Forward or Vector3.new(0, 0, 1)
	local turn = layoutValue(d, "TurnArea")
	if i <= turn then
		return d.Origin + f0 * ((i - 1) * L)
	end
	local corner = d.Origin + f0 * ((turn - 1) * L)
	return corner + f0:Cross(UP) * (layoutValue(d, "HalfWidth") + L / 2 + (i - turn - 1) * L)
end

local function frame(pos, forward)
	return CFrame.fromMatrix(pos, forward:Cross(UP), UP, -forward)
end

-- CFrame del área i: posición = centro, LookVector = dirección de avance
function Config.AreaCFrame(dim, i)
	local f = Config.AreaDirections(dim, i)
	return frame(Config.ZoneCenter(dim, i), f)
end

-- Rectángulo del área i (camino + islas laterales): { CFrame (centro del rectángulo, orientado como el área),
-- Width (a lo ancho, eje derecha), Length (a lo largo, eje adelante) }
function Config.AreaRect(dim, i)
	local d = Config.Dimensions[dim]
	local L = d.ZoneLength
	local hw = layoutValue(d, "HalfWidth")
	local c = Config.ZoneCenter(dim, i)
	local f, r = Config.AreaDirections(dim, i)
	if i ~= layoutValue(d, "TurnArea") then
		return { CFrame = frame(c, f), Width = 2 * hw, Length = L }
	end
	local front, left = layoutValue(d, "CornerFront"), layoutValue(d, "CornerLeft")
	local center = c + f * ((front - L / 2) / 2) + r * ((hw - left) / 2)
	return { CFrame = frame(center, f), Width = hw + left, Length = front + L / 2 }
end

-- ¿pos está dentro del área i? (solo X/Z; a lo largo es [atrás, adelante) para que las áreas no se pisen)
function Config.PointInArea(dim, i, pos)
	local rect = Config.AreaRect(dim, i)
	local cf = rect.CFrame
	local rel = Vector3.new(pos.X, cf.Position.Y, pos.Z) - cf.Position
	local along = rel:Dot(cf.LookVector)
	local across = rel:Dot(cf.RightVector)
	return math.abs(across) <= rect.Width / 2 and along >= -rect.Length / 2 and along < rect.Length / 2
end

function Config.ZoneFromPosition(dim, pos)
	local d = Config.Dimensions[dim]
	if not d then return nil end
	for i = 1, d.ZoneCount do
		if Config.PointInArea(dim, i, pos) then return i end
	end
	return nil
end

-- Puerta del área i (en el borde de entrada). LookVector = hacia los jugadores que llegan, igual que las puertas que arma
-- WorldBuilder (su cara Front, con el precio, mira al que viene del área anterior).
function Config.GateCFrame(dim, i)
	local d = Config.Dimensions[dim]
	local f = Config.AreaDirections(dim, i)
	return frame(Config.ZoneCenter(dim, i) - f * (d.ZoneLength / 2), -f)
end

-- Punto de llegada al teletransportarse a un área (en el camino, justo antes de la parcela)
function Config.ZoneEntry(dim, i)
	local d = Config.Dimensions[dim]
	local f = Config.AreaDirections(dim, i)
	return Config.ZoneCenter(dim, i) - f * (d.PlotLength / 2 + 7)
end

-- Igual que ZoneEntry pero mirando hacia adelante en la dirección del área
function Config.ZoneEntryCFrame(dim, i)
	local f = Config.AreaDirections(dim, i)
	return frame(Config.ZoneEntry(dim, i), f)
end

-- Spawn del lobby (mirando hacia el área 1)
function Config.LobbySpawn(dim)
	local d = Config.Dimensions[dim]
	return d.LobbyCenter - (d.Forward or Vector3.new(0, 0, 1)) * 30
end

function Config.LobbySpawnCFrame(dim)
	local d = Config.Dimensions[dim]
	return frame(Config.LobbySpawn(dim), d.Forward or Vector3.new(0, 0, 1))
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
