-- Pet Nexus: servidor principal (todo lo importante se decide aquí = anticheat)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.PetNexus.Config)
local Stats = require(ReplicatedStorage.PetNexus.Stats)
local Economy = require(ReplicatedStorage.PetNexus.Economy)
local DataService = require(ServerScriptService.DataService)
local Remotes = ReplicatedStorage.PetNexus.Remotes

-- Remotes nuevos: si no existen en Studio se crean aquí (la UI los busca con Remotes:WaitForChild(nombre))
local function remote(name, className)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className or "RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local rng = Random.new()
local state = {} -- [player] = { Target, LastHatch, LastTeleport, LastPos }
local breakables = {} -- [uid] = {...}
local breakableFolder = workspace:WaitForChild("Breakables")
local world = workspace:WaitForChild("World")

---------------------------------------------------------------- utilidades
local function getHRP(player)
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

local function notify(player, text, color)
	Remotes.Notify:FireClient(player, text, color)
end

local function sync(player)
	local data = DataService.Get(player)
	if not data then return end
	Remotes.DataSync:FireClient(player, data)
end

-- Moneda propia de cada mundo
local function getCur(data, dim) return data.Currency[dim] or 0 end
local function addCur(data, dim, amount) data.Currency[dim] = (data.Currency[dim] or 0) + amount end
local function curName(dim) return Config.CurrencyOf(dim).Name end

-- Stats, poder y equipamiento: ver Stats.luau / Economy.luau (poder real con variante, máximo según mejoras)
local equipBest = Economy.EquipBest

local function getPower(player)
	local data = DataService.Get(player)
	if not data then return 0 end
	return Stats.Power(data)
end

local function addPet(data, name)
	table.insert(data.Pets, Economy.NewPet(HttpService:GenerateGUID(false), name))
	equipBest(data)
end

-- Velocidad de caminar = stat WalkSpeed (base + mejora)
local function applyWalkSpeed(player)
	local data = DataService.Get(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if data and hum then hum.WalkSpeed = Stats.Get(data, "WalkSpeed") end
end

local function teleport(player, position)
	local char = player.Character
	if not char then return end
	if state[player] then state[player].LastTeleport = os.clock() end
	local p = position + Vector3.new(0, 4, 0)
	char:PivotTo(CFrame.lookAt(p, p + Vector3.new(0, 0, 1))) -- mirando hacia adelante (+Z, hacia las áreas)
end

---------------------------------------------------------------- rompibles
local kindPool = {}
for name, k in pairs(Config.Breakables) do
	for _ = 1, k.Weight do table.insert(kindPool, name) end
end

local function mk(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

-- Rompibles con modelos 3D de la biblioteca (PetNexusAssets): montoncito de monedas del mundo, regalo alado, cofre celestial
local Assets = ReplicatedStorage:WaitForChild("PetNexusAssets")

local function place(model, cf, scale)
	local m = model:Clone()
	if scale and scale ~= 1 then m:ScaleTo(scale) end
	m:PivotTo(cf)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false end
	end
	return m
end

local function buildVisual(model, kind, pos, dim)
	local yaw = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	if kind == "Coins" then
		local pile = Assets.Breakables:FindFirstChild(Config.CurrencyOf(dim).Model .. "Pile")
		local m = place(pile, yaw, rng:NextNumber(1, 1.25))
		m.Parent = model
		local _, sz = m:GetBoundingBox()
		return sz + Vector3.new(0.4, 0.6, 0.4)
	end
	if kind == "Chest" then
		local m = place(Assets.Breakables.AngelGift, yaw, 1.1)
		m.Parent = model
		local _, sz = m:GetBoundingBox()
		return sz + Vector3.new(0.4, 0.4, 0.4)
	else
		local m = place(Assets.Breakables.HeavenChest, yaw, 1.45)
		m.Parent = model
		local pe = Instance.new("ParticleEmitter"); pe.Rate = 8; pe.Lifetime = NumberRange.new(1, 1.8); pe.Speed = NumberRange.new(1, 2.5)
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 245, 190)); pe.LightEmission = 1; pe.Size = NumberSequence.new(0.45, 0)
		pe.SpreadAngle = Vector2.new(60, 60)
		pe.Parent = m.PrimaryPart
		local _, sz = m:GetBoundingBox()
		return sz + Vector3.new(0.4, 0.4, 0.4)
	end
end

local function mk(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end

local spawnBreakable -- forward

local function createBreakable(dim, zone)
	local kindName = kindPool[rng:NextInteger(1, #kindPool)]
	local kind = Config.Breakables[kindName]
	local mult = Config.ZoneMultiplier(dim, zone)
	local d = Config.Dimensions[dim]
	local c = Config.ZoneCenter(dim, zone)
	local pos = c + Vector3.new(rng:NextNumber(-d.PlotWidth / 2 + 5, d.PlotWidth / 2 - 5), 0.9, rng:NextNumber(-d.PlotLength / 2 + 5, d.PlotLength / 2 - 5))

	local uid = HttpService:GenerateGUID(false)
	local model = Instance.new("Model")
	model.Name = uid
	local size = buildVisual(model, kindName, pos, dim)
	local hitbox = mk(model, { Name = "Hitbox", Size = size, Position = pos + Vector3.new(0, size.Y / 2, 0), Transparency = 1, CanQuery = true })
	model.PrimaryPart = hitbox
	model:SetAttribute("Uid", uid)
	model:SetAttribute("Kind", kindName)

	local maxHp = kind.HP * mult
	model:SetAttribute("HP", maxHp)
	model:SetAttribute("MaxHP", maxHp)

	-- la barra de vida la dibuja el cliente leyendo estos atributos
	model:SetAttribute("Reward", kind.Reward * mult)
	model:SetAttribute("Dim", dim)

	local zoneFolder = breakableFolder:FindFirstChild(dim .. "_" .. zone)
	if not zoneFolder then
		zoneFolder = Instance.new("Folder"); zoneFolder.Name = dim .. "_" .. zone; zoneFolder.Parent = breakableFolder
	end
	model.Parent = zoneFolder

	breakables[uid] = {
		Uid = uid, Model = model, Dim = dim, Zone = zone, Kind = kindName,
		HP = maxHp, MaxHP = maxHp, Reward = kind.Reward * mult,
		Position = hitbox.Position, DamageBy = {}, Broken = false,
	}
end

spawnBreakable = function(dim, zone, delay)
	task.delay(delay or 0, function() createBreakable(dim, zone) end)
end

local function breakIt(b)
	b.Broken = true
	breakables[b.Uid] = nil
	local total = 0
	for _, dmg in pairs(b.DamageBy) do total += dmg end
	for player, dmg in pairs(b.DamageBy) do
		local data = player.Parent and DataService.Get(player)
		if data then
			local reward = math.max(1, math.floor(b.Reward * (dmg / total) * Stats.Get(data, "Coins", b.Dim)))
			addCur(data, b.Dim, reward)
			local diamonds = Economy.RollDiamondDrop(rng, b.Kind)
			if diamonds > 0 then diamonds = Economy.AddDiamonds(data, diamonds) end
			-- 5º argumento: diamantes ganados (0 si no salieron) para la UI futura
			Remotes.Damage:FireClient(player, "break", b.Position, reward, b.Dim, diamonds)
			Remotes.DataSync:FireClient(player, data)
		end
	end
	b.Model:Destroy()
	spawnBreakable(b.Dim, b.Zone, rng:NextNumber(2, 5))
end

local function damage(b, player, amount)
	if b.Broken then return end
	b.HP -= amount
	b.DamageBy[player] = (b.DamageBy[player] or 0) + amount
	if b.HP <= 0 then
		breakIt(b)
	else
		b.Model:SetAttribute("HP", b.HP)
	end
end

local function canUseZone(player, dim, zone)
	local data = DataService.Get(player)
	return data and (data.Unlocked[dim] or 0) >= zone
end

local function validTarget(player, b, hrp)
	return b and not b.Broken
		and (hrp.Position - b.Position).Magnitude <= Config.TargetRange
		and canUseZone(player, b.Dim, b.Zone)
end

local function findNearest(player, hrp)
	local best, bestDist = nil, Config.TargetRange
	for _, b in pairs(breakables) do
		local dist = (hrp.Position - b.Position).Magnitude
		if dist < bestDist and canUseZone(player, b.Dim, b.Zone) then
			best, bestDist = b, dist
		end
	end
	return best
end

for dim, d in pairs(Config.Dimensions) do
	for zone = 1, d.AreasBuilt do
		for _ = 1, Config.BreakablesPerZone do createBreakable(dim, zone) end
	end
end

-- El jugador puede elegir objetivo haciendo clic (validado en el servidor)
Remotes.SetTarget.OnServerEvent:Connect(function(player, uid)
	local st = state[player]
	if not st or typeof(uid) ~= "string" then return end
	if os.clock() - (st.LastTargetReq or 0) < 0.15 then return end
	st.LastTargetReq = os.clock()
	local hrp = getHRP(player)
	local b = breakables[uid]
	if hrp and validTarget(player, b, hrp) then
		st.Target = uid
		player:SetAttribute("Target", uid)
	end
end)

-- Bucle de daño (servidor autoritativo)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < Config.DamageTick then return end
	local step = acc
	acc = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local st = state[player]
		local hrp = getHRP(player)
		if st and hrp then
			local b = st.Target and breakables[st.Target]
			if not validTarget(player, b, hrp) then
				b = findNearest(player, hrp)
				st.Target = b and b.Uid or nil
				player:SetAttribute("Target", st.Target or "")
			end
			local data = DataService.Get(player)
			if b and data then
				damage(b, player, getPower(player) * 2 * step * Stats.Get(data, "BreakSpeed"))
			end
		end
	end
end)

---------------------------------------------------------------- huevos
-- Tirada con pity y suerte (Economy.RollEgg / Stats.LuckWeights)
local function rollEgg(eggId, data)
	return Economy.RollEgg(rng, eggId, data, Stats.Get(data, "Luck"))
end

local function hookEgg(eggPart)
	local prompt = eggPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function(player)
		local data = DataService.Get(player)
		local st = state[player]
		if not data or not st then return end
		if os.clock() - (st.LastHatch or 0) < Config.HatchCooldown / Stats.Get(data, "HatchSpeed") then return end
		st.LastHatch = os.clock()
		local eggId = eggPart:GetAttribute("EggId")
		local egg = Config.Eggs[eggId]
		if not egg then return end
		if not canUseZone(player, egg.Dimension, egg.Zone) then
			return notify(player, "Desbloquea " .. Config.AreaName(egg.Dimension, egg.Zone) .. " primero", Color3.fromRGB(255, 120, 120))
		end
		if #data.Pets >= Config.MaxInventory then
			return notify(player, "¡Inventario lleno!", Color3.fromRGB(255, 120, 120))
		end
		if getCur(data, egg.Dimension) < egg.Price then
			return notify(player, "Te faltan " .. Config.FormatNumber(egg.Price - getCur(data, egg.Dimension)) .. " " .. curName(egg.Dimension), Color3.fromRGB(255, 200, 90))
		end
		addCur(data, egg.Dimension, -egg.Price)
		data.TotalHatched += 1
		local petName, forced = rollEgg(eggId, data)
		addPet(data, petName)
		Remotes.HatchResult:FireClient(player, eggId, petName, forced)
		sync(player)
	end)
end

for _, egg in ipairs(CollectionService:GetTagged("Egg")) do hookEgg(egg) end

---------------------------------------------------------------- áreas (compra)
local function buyArea(player, dim, zone)
	local data = DataService.Get(player)
	local st = state[player]
	local d = Config.Dimensions[dim]
	if not data or not st or not d or typeof(zone) ~= "number" or zone ~= math.floor(zone) or zone < 2 or zone > d.ZoneCount then return end
	if os.clock() - (st.LastBuy or 0) < 0.4 then return end
	st.LastBuy = os.clock()
	local current = data.Unlocked[dim] or 0
	if current >= zone then return end
	if zone > d.AreasBuilt then
		return notify(player, Config.AreaName(dim, zone) .. " llega en el próximo update", Color3.fromRGB(255, 225, 120))
	end
	if current < zone - 1 then
		return notify(player, "Desbloquea " .. Config.AreaName(dim, zone - 1) .. " primero", Color3.fromRGB(255, 120, 120))
	end
	local price = Config.ZonePrice(dim, zone)
	if getCur(data, dim) < price then
		return notify(player, "Te faltan " .. Config.FormatNumber(price - getCur(data, dim)) .. " " .. curName(dim), Color3.fromRGB(255, 200, 90))
	end
	addCur(data, dim, -price)
	data.Unlocked[dim] = zone
	Remotes.AreaUnlocked:FireClient(player, dim, zone)
	sync(player)
end

Remotes.BuyArea.OnServerEvent:Connect(function(player, dim, zone)
	if typeof(dim) ~= "string" then return end
	buyArea(player, dim, zone)
end)

local function hookGate(wall)
	local prompt = wall:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function(player)
		buyArea(player, wall:GetAttribute("Dimension"), wall:GetAttribute("Zone"))
	end)
end
for _, wall in ipairs(CollectionService:GetTagged("AreaGate")) do hookGate(wall) end

-- Tienda del lobby (por ahora solo aviso)
for _, counter in ipairs(CollectionService:GetTagged("ShopCounter")) do
	local pp = counter:FindFirstChildOfClass("ProximityPrompt")
	if pp then
		pp.Triggered:Connect(function(player)
			if counter:GetAttribute("ShopKind") == "Premium" then
				notify(player, "La Premium Shop abre muy pronto", Color3.fromRGB(255, 225, 140))
			else
				notify(player, "La tienda abre muy pronto", Color3.fromRGB(255, 190, 230))
			end
		end)
	end
end

---------------------------------------------------------------- teletransporte
-- Botón de TP: (mundo, 0) = lobby del mundo; (mundo, área). Todo se valida aquí y pasa por teleport().
-- El viaje entre mundos por vehículo (requiere Esencia) se implementa cuando exista el área 20.
Remotes.Teleport.OnServerEvent:Connect(function(player, dest, zone)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(dest) ~= "string" or typeof(zone) ~= "number" then return end
	local d = Config.Dimensions[dest]
	if not d or zone ~= math.floor(zone) or zone < 0 or zone > d.ZoneCount then return end
	if (data.Unlocked[dest] or 0) < 1 then
		return notify(player, "Aún no llegas a ese mundo", Color3.fromRGB(255, 120, 120))
	end
	if os.clock() - (st.LastTpReq or 0) < Config.TeleportCooldown then
		return notify(player, "Espera un momento para teletransportarte", Color3.fromRGB(255, 200, 90))
	end
	if zone == 0 then
		st.LastTpReq = os.clock()
		teleport(player, Config.LobbySpawn(dest))
		return notify(player, Config.WorldInfo(dest).Lobby, Color3.fromRGB(150, 225, 255))
	end
	if not canUseZone(player, dest, zone) then
		return notify(player, "Esa área aún está bloqueada", Color3.fromRGB(255, 120, 120))
	end
	st.LastTpReq = os.clock()
	teleport(player, Config.ZoneEntry(dest, zone))
end)

---------------------------------------------------------------- anticheat básico
-- 1) No puedes estar en una pasarela que no desbloqueaste
-- 2) Movimiento imposible (teletransporte / speed hack) -> te regresa
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local st, data, hrp = state[player], DataService.Get(player), getHRP(player)
			if st and data and hrp then
				local pos = hrp.Position
				local recentTp = os.clock() - (st.LastTeleport or 0) < 2
				if st.LastPos and not recentTp and (pos - st.LastPos).Magnitude > 110 then
					teleport(player, st.LastPos)
					warn("[PetNexus][AC] Movimiento imposible:", player.Name)
				else
					for dim in pairs(Config.Dimensions) do
						local zone = Config.ZoneFromPosition(dim, pos)
						if zone and zone > (data.Unlocked[dim] or 0) then
							local allowed = math.max(1, data.Unlocked[dim] or 1)
							teleport(player, Config.ZoneCenter(dim, allowed))
							warn("[PetNexus][AC] Zona bloqueada:", player.Name)
						end
					end
					st.LastPos = hrp.Position
				end
			end
		end
	end
end)

---------------------------------------------------------------- meditación (Esencia AFK)
-- Zona = Part con tag "MeditationZone" (volumen invisible). Atributos opcionales Dimension/Zone: área que hay que tener desbloqueada.
-- El servidor comprueba la posición: dentro se gana 1 Esencia cada SecondsPerEssence hasta el tope del ciclo; al llegar empieza
-- la recarga, guardada como segundos restantes, así que solo baja mientras el jugador está conectado.
-- Este bucle es el único que otorga Esencia (no hay remote que la toque, no es tradeable).
-- El cliente lee el estado de los atributos Meditating / MeditationProgress / MeditationCooldown del jugador.
local Med = Config.Meditation
local medZones = {}
local function addMedZone(p)
	if p:IsA("BasePart") then medZones[p] = true end
end
for _, p in ipairs(CollectionService:GetTagged("MeditationZone")) do addMedZone(p) end
CollectionService:GetInstanceAddedSignal("MeditationZone"):Connect(addMedZone)
CollectionService:GetInstanceRemovedSignal("MeditationZone"):Connect(function(p) medZones[p] = nil end)

local function inMeditationZone(player)
	local hrp = getHRP(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum or hum.Health <= 0 then return false end
	for zone in pairs(medZones) do
		local rel = zone.CFrame:PointToObjectSpace(hrp.Position)
		local half = zone.Size / 2
		if math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z then
			local dim, z = zone:GetAttribute("Dimension"), zone:GetAttribute("Zone")
			if not dim or not z or canUseZone(player, dim, z) then return true end
		end
	end
	return false
end

-- Multiplicador de Esencia del jugador = stat Essence (base Config.Meditation.BaseMultiplier + Essence Master equipados)
local function essenceMultiplier(player, data)
	return Stats.Get(data, "Essence")
end

task.spawn(function()
	local capSeconds = Med.Cap * Med.SecondsPerEssence
	while true do
		local dt = math.min(task.wait(1), 3)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataService.Get(player)
			if data then
				local m = data.Meditation
				local inside = inMeditationZone(player)
				local mult = essenceMultiplier(player, data)
				if m.Cooldown > 0 then
					m.Cooldown = math.max(0, m.Cooldown - dt)
					if m.Cooldown == 0 then
						notify(player, "La Zona de Meditación está lista otra vez", Color3.fromRGB(215, 175, 255))
					end
				elseif inside then
					local before = math.floor(m.Progress / Med.SecondsPerEssence)
					m.Progress = math.min(capSeconds, m.Progress + dt)
					local gained = math.floor(m.Progress / Med.SecondsPerEssence) - before
					if m.Progress >= capSeconds then
						m.Progress = 0
						m.Cooldown = Med.Cooldown
						notify(player, "¡Tope de Esencia! La meditación se recarga en " .. math.floor(Med.Cooldown / 60) .. " min de juego", Color3.fromRGB(215, 175, 255))
					end
					if gained > 0 and Economy.GrantEssence(data, gained, mult) > 0 then
						sync(player)
					end
				end
				player:SetAttribute("Meditating", inside)
				player:SetAttribute("MeditationProgress", math.floor(m.Progress))
				player:SetAttribute("MeditationCooldown", math.ceil(m.Cooldown))
				player:SetAttribute("EssenceMultiplier", mult)
			end
		end
	end
end)

---------------------------------------------------------------- encantamientos, mejoras y variantes (solo lógica)
-- La UI (mesa de encantamientos, máquinas) se arma en Studio y usa estos remotes. Los errores llegan como Notify.
-- Cliente -> servidor:
--   EnchantPet(petId)                              una tirada manual (Config.EnchantCost diamantes)
--   StartAutoEnchant(petId, enchantId, minLevel)   requiere la mejora AutoEnchant; minLevel opcional (1)
--   StopAutoEnchant()
--   BuyUpgrade(upgradeId, level, dim)              level = siguiente nivel; dim solo en mejoras PerDimension (Coins)
--   ConvertVariant(petIds, variant, dim)           petIds = lista de Id (el primero se conserva); dim = mundo de la máquina
-- Servidor -> cliente:
--   EnchantResult({ PetId, Id, Level, Tier, Auto })
--   AutoEnchantStatus(status, { PetId, Target, MinLevel, Rolls, Enchant })
--       status = "started" | "target" | "no_funds" | "cancelled" | "pet_missing"
--   UpgradeResult(upgradeId, level, dim)           dim = nil en las mejoras globales
--   VariantResult(petId, variant)
local EnchantPetRemote = remote("EnchantPet")
local StartAutoEnchantRemote = remote("StartAutoEnchant")
local StopAutoEnchantRemote = remote("StopAutoEnchant")
local BuyUpgradeRemote = remote("BuyUpgrade")
local ConvertVariantRemote = remote("ConvertVariant")
local EnchantResultRemote = remote("EnchantResult")
local AutoEnchantStatusRemote = remote("AutoEnchantStatus")
local UpgradeResultRemote = remote("UpgradeResult")
local VariantResultRemote = remote("VariantResult")

local RED = Color3.fromRGB(255, 120, 120)
local GOLD = Color3.fromRGB(255, 200, 90)
local ENCHANT_COLOR = Color3.fromRGB(200, 170, 255)

local function currencyLabel(currency, dim)
	return currency == "Diamonds" and "Diamantes" or curName(dim)
end

local function missing(player, amount, currency, dim)
	notify(player, "Te faltan " .. Config.FormatNumber(amount) .. " " .. currencyLabel(currency, dim), GOLD)
end

-- true si la petición llegó antes del intervalo (se ignora)
local function rateLimited(st, key, interval)
	local now = os.clock()
	if now - (st[key] or 0) < interval then return true end
	st[key] = now
	return false
end

local function validPetId(v)
	return typeof(v) == "string" and #v > 0 and #v <= 64
end

-- Encantamiento manual
local autoJobs = {} -- [player] = { PetId, Target, MinLevel, Rolls, Last } (uno por jugador, no se guarda)

EnchantPetRemote.OnServerEvent:Connect(function(player, petId)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not validPetId(petId) then return end
	if rateLimited(st, "LastEnchant", Config.RateLimits.Enchant) then return end
	if autoJobs[player] then
		return notify(player, "Detén el auto enchant antes de encantar a mano", GOLD)
	end
	local ok, res, extra = Economy.EnchantPet(data, petId, rng)
	if not ok then
		if res == "funds" then return missing(player, extra, "Diamonds") end
		return notify(player, "Esa mascota no existe", RED)
	end
	EnchantResultRemote:FireClient(player, { PetId = petId, Id = res.Id, Level = res.Level, Tier = extra, Auto = false })
	notify(player, "Encantamiento: " .. Config.EnchantLabel(res.Id, res.Level), ENCHANT_COLOR)
	sync(player)
end)

-- Auto enchant: tira cada Config.AutoEnchant.Interval cobrando cada tirada hasta que sale el objetivo,
-- se acaban los diamantes, el jugador cancela, la mascota deja de existir o el jugador sale
local AUTO_STOP_TEXT = {
	target = "Auto enchant: conseguiste %s en %d tiradas",
	no_funds = "Auto enchant detenido: no te alcanzan los diamantes",
	cancelled = "Auto enchant cancelado",
	pet_missing = "Auto enchant detenido: la mascota ya no existe",
}

local function stopAuto(player, status)
	local job = autoJobs[player]
	if not job then return end
	autoJobs[player] = nil
	if not player.Parent then return end
	AutoEnchantStatusRemote:FireClient(player, status, { PetId = job.PetId, Target = job.Target, MinLevel = job.MinLevel, Rolls = job.Rolls, Enchant = job.Last })
	local text = AUTO_STOP_TEXT[status]
	if status == "target" then text = string.format(text, Config.EnchantLabel(job.Last.Id, job.Last.Level), job.Rolls) end
	notify(player, text, status == "target" and ENCHANT_COLOR or GOLD)
end

local function runAuto(player, job)
	while autoJobs[player] == job do
		task.wait(Config.AutoEnchant.Interval)
		if autoJobs[player] ~= job then return end
		local data = player.Parent and DataService.Get(player)
		if not data then
			autoJobs[player] = nil
			return
		end
		local ok, res, extra = Economy.EnchantPet(data, job.PetId, rng)
		if not ok then
			return stopAuto(player, res == "funds" and "no_funds" or "pet_missing")
		end
		job.Rolls += 1
		job.Last = { Id = res.Id, Level = res.Level }
		EnchantResultRemote:FireClient(player, { PetId = job.PetId, Id = res.Id, Level = res.Level, Tier = extra, Auto = true })
		sync(player)
		if Economy.MatchesTarget(res, job.Target, job.MinLevel) then
			return stopAuto(player, "target")
		end
	end
end

StartAutoEnchantRemote.OnServerEvent:Connect(function(player, petId, enchantId, minLevel)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not validPetId(petId) or typeof(enchantId) ~= "string" then return end
	if rateLimited(st, "LastAutoEnchant", Config.RateLimits.AutoEnchant) then return end
	local def = Config.Enchants[enchantId]
	if not def then return end
	if minLevel == nil then minLevel = 1 end
	if typeof(minLevel) ~= "number" or minLevel ~= math.floor(minLevel) or minLevel < 1 or minLevel > #def.Levels then return end
	if not Stats.HasUpgrade(data, "AutoEnchant") then
		return notify(player, "Necesitas la mejora Auto Enchant", GOLD)
	end
	if autoJobs[player] then
		return notify(player, "Ya tienes un auto enchant activo", GOLD)
	end
	local pet = Economy.FindPet(data, petId)
	if not pet then return notify(player, "Esa mascota no existe", RED) end
	if Economy.MatchesTarget(pet.Enchant, enchantId, minLevel) then
		return notify(player, "Esa mascota ya tiene " .. Config.EnchantLabel(pet.Enchant.Id, pet.Enchant.Level), GOLD)
	end
	if (data.Diamonds or 0) < Config.EnchantCost then
		return missing(player, Config.EnchantCost - (data.Diamonds or 0), "Diamonds")
	end
	local job = { PetId = petId, Target = enchantId, MinLevel = minLevel, Rolls = 0 }
	autoJobs[player] = job
	AutoEnchantStatusRemote:FireClient(player, "started", { PetId = petId, Target = enchantId, MinLevel = minLevel, Rolls = 0 })
	task.spawn(runAuto, player, job)
end)

StopAutoEnchantRemote.OnServerEvent:Connect(function(player)
	stopAuto(player, "cancelled")
end)

-- Máquina de mejoras
local UPGRADE_ERR = {
	dim = "Ese mundo no está disponible",
	owned = "Ya tienes ese nivel",
	max = "Esa mejora ya está al máximo",
	order = "Compra primero el nivel anterior",
}

BuyUpgradeRemote.OnServerEvent:Connect(function(player, upgradeId, level, dim)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(upgradeId) ~= "string" or typeof(level) ~= "number" then return end
	if dim ~= nil and typeof(dim) ~= "string" then return end
	if rateLimited(st, "LastUpgrade", Config.RateLimits.Upgrade) then return end
	local ok, err, extra = Economy.BuyUpgrade(data, upgradeId, level, dim)
	if not ok then
		if err == "funds" then
			local _, currency, curDim = Economy.UpgradeCost(upgradeId, level, dim)
			return missing(player, extra, currency, curDim)
		end
		if UPGRADE_ERR[err] then notify(player, UPGRADE_ERR[err], RED) end
		return
	end
	local def = Config.Upgrades[upgradeId]
	equipBest(data) -- PetsEquipped cambia cuántas se equipan
	applyWalkSpeed(player)
	UpgradeResultRemote:FireClient(player, upgradeId, level, def.PerDimension and dim or nil)
	notify(player, "Mejora comprada: " .. (def.Name or upgradeId) .. " nivel " .. level, Color3.fromRGB(150, 235, 160))
	sync(player)
end)

-- Máquinas de variantes (Golden / Rainbow / Void)
local VARIANT_ERR = {
	machine = "Esa máquina no está en este mundo",
	locked = "Desbloquea primero el área de la máquina",
	pet = "Alguna de esas mascotas no existe",
	mismatch = "Las mascotas tienen que ser iguales",
}

ConvertVariantRemote.OnServerEvent:Connect(function(player, petIds, variant, dim)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(petIds) ~= "table" or typeof(variant) ~= "string" or typeof(dim) ~= "string" then return end
	if rateLimited(st, "LastConvert", Config.RateLimits.Variant) then return end
	local recipe = Config.VariantRecipes[variant]
	if not recipe then return end
	local ok, res, extra = Economy.ConvertVariant(data, petIds, variant, dim)
	if not ok then
		if res == "funds" then return missing(player, extra, recipe.Currency, dim) end
		if res == "count" or res == "from" then
			return notify(player, "Necesitas " .. recipe.Pets .. " mascotas iguales " .. recipe.From, RED)
		end
		if VARIANT_ERR[res] then notify(player, VARIANT_ERR[res], RED) end
		return
	end
	equipBest(data)
	VariantResultRemote:FireClient(player, res.Id, variant)
	notify(player, Config.PetName(res.Name) .. " ahora es " .. variant, Color3.fromRGB(255, 225, 120))
	sync(player)
end)

---------------------------------------------------------------- jugadores
local function onPlayerAdded(player)
	state[player] = {}
	local data = DataService.Load(player)
	if #data.Pets == 0 then
		addPet(data, "Sprout")
	else
		equipBest(data)
	end
	player.CharacterAdded:Connect(function()
		state[player].LastTeleport = os.clock()
		state[player].LastPos = nil
		task.wait(0.5)
		applyWalkSpeed(player)
		sync(player)
	end)
	applyWalkSpeed(player)
	sync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

Players.PlayerRemoving:Connect(function(player)
	autoJobs[player] = nil -- corta el auto enchant (el bucle ve que su trabajo ya no es el actual)
	DataService.Release(player)
	state[player] = nil
	for _, b in pairs(breakables) do b.DamageBy[player] = nil end
end)

task.spawn(function()
	while true do
		task.wait(120)
		DataService.SaveAll()
	end
end)

game:BindToClose(function()
	DataService.SaveAll()
end)

---------------------------------------------------------------- herramientas de prueba (solo Studio)
if RunService:IsStudio() then
	local dbg = Instance.new("BindableFunction")
	dbg.Name = "PetNexusDebug"
	-- mascota por índice en data.Pets (1 = la más fuerte) o por Id
	local function debugPet(data, ref)
		if typeof(ref) == "number" then return data.Pets[ref] end
		return Economy.FindPet(data, ref)
	end
	dbg.OnInvoke = function(cmd, player, value)
		local data = DataService.Get(player)
		if not data then return "sin datos" end
		if cmd == "coins" then data.Currency.Nexus = value
		elseif cmd == "unlock" then data.Unlocked.Nexus = value
		elseif cmd == "essence" then data.Essence = value
		elseif cmd == "medprogress" then data.Meditation.Progress = value -- segundos meditados en el ciclo
		elseif cmd == "medcooldown" then data.Meditation.Cooldown = value -- segundos de recarga restantes
		elseif cmd == "teleport" then teleport(player, value)
		elseif cmd == "diamonds" then data.Diamonds += value -- suma directa, sin multiplicador (negativo para quitar)
		elseif cmd == "variant" then -- value = { Pet = índice o Id, Variant = "Golden" }
			local pet = debugPet(data, value.Pet)
			if not pet or not Config.PetVariants[value.Variant] then return "mascota o variante inválida" end
			pet.Variant = value.Variant
		elseif cmd == "enchant" then -- value = { Pet = índice o Id, Id = "Coins", Level = 5 }; sin Id = quitar
			local pet = debugPet(data, value.Pet)
			if not pet then return "mascota inválida" end
			local def = value.Id and Config.Enchants[value.Id]
			if value.Id == nil then pet.Enchant = nil
			elseif def and def.Levels[value.Level] then pet.Enchant = { Id = value.Id, Level = value.Level }
			else return "encantamiento o nivel inválido" end
		elseif cmd == "upgrade" then -- value = { Id = "Coins", Level = 2, Dim = "Nexus" } (Dim solo en PerDimension); Level 0 = quitar
			local def = Config.Upgrades[value.Id]
			if not def or typeof(value.Level) ~= "number" or value.Level < 0 or value.Level > #def.Levels then return "mejora o nivel inválido" end
			if def.PerDimension then
				if typeof(data.Upgrades[value.Id]) ~= "table" then data.Upgrades[value.Id] = {} end
				data.Upgrades[value.Id][value.Dim or "Nexus"] = value.Level
			else
				data.Upgrades[value.Id] = value.Level
			end
		elseif cmd == "stats" then -- value = dimensión para Coins (por defecto Nexus)
			return HttpService:JSONEncode(Stats.Compute(data, value or "Nexus"))
		elseif cmd == "get" then return HttpService:JSONEncode(data) end
		equipBest(data)
		applyWalkSpeed(player)
		sync(player)
		return "ok"
	end
	dbg.Parent = game:GetService("ServerStorage")
end
