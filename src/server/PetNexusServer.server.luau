-- Pet Nexus: servidor principal (todo lo importante se decide aquí = anticheat)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local MarketplaceService = game:GetService("MarketplaceService")
local TextService = game:GetService("TextService")

local Config = require(ReplicatedStorage.PetNexus.Config)
local Stats = require(ReplicatedStorage.PetNexus.Stats)
local Economy = require(ReplicatedStorage.PetNexus.Economy)
local Progression = require(ReplicatedStorage.PetNexus.Progression)
local Purchases = require(ReplicatedStorage.PetNexus.Purchases)
local Inventory = require(ReplicatedStorage.PetNexus.Inventory)
local Gifts = require(ReplicatedStorage.PetNexus.Gifts)
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

-- Remotes de progresión (ver la sección "rebirth, rango, pociones y compras" para argumentos)
local PetLevelUpRemote = remote("PetLevelUp")

local rng = Random.new()
local state = {} -- [player] = { Target, LastHatch, LastTeleport, LastPos, GraceUntil, Ascending, Playtime, Last<remote> }
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

-- Stats, poder y equipamiento: ver Stats.luau / Economy.luau / Inventory.luau. El jugador controla su equipo:
-- el servidor solo desequipa si hay más equipadas que MaxEquipped (Inventory.ClampEquipped).
local function getPower(player)
	local data = DataService.Get(player)
	if not data then return 0 end
	return Stats.Power(data)
end

-- Única forma de dar una mascota (respeta el límite de inventario). Devuelve ok, mascota o código de error.
local function addPet(data, name)
	return Inventory.AddPet(data, HttpService:GenerateGUID(false), name)
end

-- Velocidad de caminar = stat WalkSpeed (base + mejora)
local function applyWalkSpeed(player)
	local data = DataService.Get(player)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if data and hum then hum.WalkSpeed = Stats.Get(data, "WalkSpeed") end
end

-- target: Vector3 (mira a +Z, como antes) o CFrame (usa su orientación: Config.ZoneEntryCFrame / LobbySpawnCFrame)
local function teleport(player, target)
	local char = player.Character
	if not char then return end
	if state[player] then state[player].LastTeleport = os.clock() end
	local cf = typeof(target) == "CFrame" and target or CFrame.lookAt(target, target + Vector3.new(0, 0, 1))
	char:PivotTo(cf + Vector3.new(0, 4, 0))
end

-- ¿El jugador está a menos de 'range' studs (en horizontal, desde el borde) de alguna instancia con ese tag?
-- dim: si se da, la instancia tiene que tener el atributo Dimension igual a dim.
local function nearTagged(player, tag, range, dim)
	local hrp = getHRP(player)
	if not hrp then return false end
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if not dim or inst:GetAttribute("Dimension") == dim then
			local pos, size
			if inst:IsA("BasePart") then
				pos, size = inst.Position, inst.Size
			elseif inst:IsA("Model") then
				local cf, sz = inst:GetBoundingBox()
				pos, size = cf.Position, sz
			end
			if pos then
				local flat = Vector3.new(hrp.Position.X - pos.X, 0, hrp.Position.Z - pos.Z).Magnitude
				if flat - math.max(size.X, size.Z) / 2 <= range then return true end
			end
		end
	end
	return false
end

-- ¿La posición está dentro del volumen de una Part? (para regiones como la zona VIP)
local function insidePart(part, pos)
	local rel = part.CFrame:PointToObjectSpace(pos)
	local half = part.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y and math.abs(rel.Z) <= half.Z
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
	-- dentro de la parcela, orientada como el área (las áreas después de la esquina están giradas)
	local pos = Config.AreaCFrame(dim, zone):PointToWorldSpace(Vector3.new(
		rng:NextNumber(-d.PlotWidth / 2 + 5, d.PlotWidth / 2 - 5), 0.9, rng:NextNumber(-d.PlotLength / 2 + 5, d.PlotLength / 2 - 5)))

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
			-- XP fija para cada mascota equipada (el equipo no cambia solo: lo decide el jugador)
			local _, leveled = Progression.GrantBreakXP(data, b.Kind)
			if #leveled > 0 then
				PetLevelUpRemote:FireClient(player, leveled)
			end
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
		if Inventory.IsFull(data) then
			return notify(player, "Inventario lleno (" .. #data.Pets .. "/" .. Inventory.MaxPets(data)
				.. "): borra mascotas o amplía el inventario", Color3.fromRGB(255, 120, 120))
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
-- ¿El jugador está cerca de la puerta del área? Se mide contra la puerta real del mapa (tag AreaGate con atributos
-- Dimension/Zone) y, si no hay ninguna, contra la posición de Config.GateCFrame.
local function nearGate(player, dim, zone)
	local hrp = getHRP(player)
	if not hrp then return false end
	local gatePos = Config.GateCFrame(dim, zone).Position
	for _, wall in ipairs(CollectionService:GetTagged("AreaGate")) do
		if wall:GetAttribute("Dimension") == dim and wall:GetAttribute("Zone") == zone and wall:IsA("BasePart") then
			gatePos = wall.Position
			break
		end
	end
	local flat = Vector3.new(hrp.Position.X - gatePos.X, 0, hrp.Position.Z - gatePos.Z)
	return flat.Magnitude <= Config.GateBuyRange
end

local function buyArea(player, dim, zone)
	local data = DataService.Get(player)
	local st = state[player]
	local d = typeof(dim) == "string" and Config.Dimensions[dim]
	if not data or not st or not d or typeof(zone) ~= "number" or zone ~= math.floor(zone) or zone < 2 or zone > d.ZoneCount then return end
	if os.clock() - (st.LastBuy or 0) < 0.4 then return end
	st.LastBuy = os.clock()
	local current = data.Unlocked[dim] or 0
	if current >= zone then return end
	if not nearGate(player, dim, zone) then
		return notify(player, "Acércate a la puerta para comprar el área", Color3.fromRGB(255, 200, 90))
	end
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
		teleport(player, Config.LobbySpawnCFrame(dest))
		return notify(player, Config.WorldInfo(dest).Lobby, Color3.fromRGB(150, 225, 255))
	end
	if not canUseZone(player, dest, zone) then
		return notify(player, "Esa área aún está bloqueada", Color3.fromRGB(255, 120, 120))
	end
	st.LastTpReq = os.clock()
	teleport(player, Config.ZoneEntryCFrame(dest, zone)) -- mirando hacia adelante según la dirección del área
end)

---------------------------------------------------------------- anticheat básico
-- 1) No puedes estar en un área que no desbloqueaste (ni en un mundo al que no llegaste)
-- 2) Movimiento imposible (teletransporte / speed hack) -> te regresa
-- 3) Zona VIP (Parts con tag "VipZone"): los que no tienen VIP salen al lobby
-- Durante la ventana de gracia (ascensión del rebirth) no se castiga nada.
local function hasVipAccess(data)
	for key, def in pairs(Config.GamePasses) do
		if def.VipAccess and Stats.HasPass(data, key) then return true end
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local st, data, hrp = state[player], DataService.Get(player), getHRP(player)
			if st and data and hrp then
				local pos = hrp.Position
				local recentTp = os.clock() - (st.LastTeleport or 0) < 2
				if st.GraceUntil and os.clock() < st.GraceUntil then
					st.LastPos = nil
				elseif st.LastPos and not recentTp and (pos - st.LastPos).Magnitude > 110 then
					teleport(player, st.LastPos)
					warn("[PetNexus][AC] Movimiento imposible:", player.Name)
				else
					local moved = false
					for dim in pairs(Config.Dimensions) do
						local zone = Config.ZoneFromPosition(dim, pos)
						if zone and zone > (data.Unlocked[dim] or 0) then
							if (data.Unlocked[dim] or 0) < 1 then
								teleport(player, Config.LobbySpawnCFrame(Progression.CurrentWorld(data, nil)))
							else
								teleport(player, Config.AreaCFrame(dim, data.Unlocked[dim]))
							end
							moved = true
							warn("[PetNexus][AC] Zona bloqueada:", player.Name)
						end
					end
					if not moved and not hasVipAccess(data) then
						for _, zonePart in ipairs(CollectionService:GetTagged("VipZone")) do
							if zonePart:IsA("BasePart") and insidePart(zonePart, pos) then
								local dim = zonePart:GetAttribute("Dimension")
								teleport(player, Config.LobbySpawnCFrame(Config.Dimensions[dim] and dim or Progression.CurrentWorld(data, pos)))
								notify(player, "Zona solo para VIP", Color3.fromRGB(255, 200, 90))
								moved = true
								break
							end
						end
					end
					st.LastPos = not moved and hrp.Position or nil
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

-- Recorta la recarga de la meditación y avisa. Hook para las misiones (aún no existen): una misión cumplida llamará
-- cutMeditationCooldown(player, Config.Meditation.MissionCooldownCut). Devuelve los segundos recortados.
local function cutMeditationCooldown(player, seconds)
	local data = DataService.Get(player)
	if not data then return 0 end
	local cut = Economy.ReduceMeditationCooldown(data, seconds)
	if cut > 0 then
		player:SetAttribute("MeditationCooldown", math.ceil(data.Meditation.Cooldown))
		if data.Meditation.Cooldown <= 0 then
			notify(player, "La Zona de Meditación está lista otra vez", Color3.fromRGB(215, 175, 255))
		end
	end
	return cut
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
						if (m.SkipCredits or 0) > 0 then
							-- salto de recarga comprado cuando no había recarga: se usa ahora
							m.SkipCredits -= 1
							notify(player, "¡Tope de Esencia! Usaste tu salto de recarga: la meditación sigue lista", Color3.fromRGB(215, 175, 255))
						else
							m.Cooldown = Med.Cooldown
							notify(player, "¡Tope de Esencia! La meditación se recarga en " .. math.floor(Med.Cooldown / 60) .. " min de juego", Color3.fromRGB(215, 175, 255))
						end
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
	Inventory.ClampEquipped(data)
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
	Inventory.PruneTeams(data) -- las mascotas consumidas salen de los teams
	VariantResultRemote:FireClient(player, res.Id, variant)
	notify(player, Config.PetName(res.Name) .. " ahora es " .. variant, Color3.fromRGB(255, 225, 120))
	sync(player)
end)

---------------------------------------------------------------- rebirth, rango, pociones y compras (solo lógica)
-- La UI (estatua, ventana de rango, tienda premium, inventario de pociones) se arma en Studio y usa estos remotes.
-- Cliente -> servidor:
--   Rebirth(dim)            cerca de una Part con tag "RebirthStatue" y atributo Dimension = dim
--   BuyRank(rank)           rank = el siguiente rango (se paga con diamantes)
--   UsePotion(tipo)         "Luck" | "Coins" | "Diamonds" | "HatchSpeed"
--   ClaimFreePotions()      cerca de una Part con tag "PotionShrine"
--   PromptProduct(key)      abre la compra de un Developer Product (clave de Config.Products) si se puede ofrecer
--   PromptGamePass(key)     abre la compra de un gamepass (clave de Config.GamePasses)
-- Servidor -> cliente:
--   RebirthResult(dim, { Number, Kept, Ascension })  animación de ascensión; el servidor teletransporta al terminar
--   RankResult(rank)
--   PetLevelUp({ { PetId, Level }, ... })
--   PotionUsed(tipo, segundosRestantes) / PotionEnded(tipo)
--   FreePotionsClaimed(pociones, proximoReclamo)       proximoReclamo en os.time()
--   ProductGranted(key, info)                          info según Kind (ver Purchases.Grant)
--   GamePassGranted(key)
local RebirthRemote = remote("Rebirth")
local BuyRankRemote = remote("BuyRank")
local UsePotionRemote = remote("UsePotion")
local ClaimFreePotionsRemote = remote("ClaimFreePotions")
local PromptProductRemote = remote("PromptProduct")
local PromptGamePassRemote = remote("PromptGamePass")
local RebirthResultRemote = remote("RebirthResult")
local RankResultRemote = remote("RankResult")
local PotionUsedRemote = remote("PotionUsed")
local PotionEndedRemote = remote("PotionEnded")
local FreePotionsClaimedRemote = remote("FreePotionsClaimed")
local ProductGrantedRemote = remote("ProductGranted")
local GamePassGrantedRemote = remote("GamePassGranted")

local GREEN = Color3.fromRGB(150, 235, 160)

local function waitText(seconds)
	local m = math.ceil(seconds / 60)
	if m < 60 then return m .. " min" end
	return math.floor(m / 60) .. " h " .. (m % 60) .. " min"
end

-- Rebirth
local REBIRTH_ERR = {
	dim = "Este mundo no tiene rebirth",
	done = "Ya hiciste el rebirth de este mundo",
}

RebirthRemote.OnServerEvent:Connect(function(player, dim)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(dim) ~= "string" then return end
	if st.Ascending or rateLimited(st, "LastRebirth", Config.RateLimits.Rebirth) then return end
	local ok, err, extra = Progression.CanRebirth(data, dim)
	if not ok then
		if err == "area" then
			return notify(player, "Desbloquea " .. Config.AreaName(dim, extra) .. " para hacer rebirth", RED)
		elseif err == "order" then
			return notify(player, "Primero haz el rebirth de " .. (Config.WorldInfo(extra) and Config.WorldInfo(extra).Display or extra), RED)
		end
		return notify(player, REBIRTH_ERR[err] or "No puedes hacer rebirth", RED)
	end
	if not nearTagged(player, "RebirthStatue", Config.RebirthRange, dim) then
		return notify(player, "Acércate a la estatua de Rebirth", GOLD)
	end
	local _, info = Progression.Rebirth(data, dim)
	info.Ascension = Config.RebirthAscension
	-- ventana de gracia: el cliente hace volar al personaje y sus áreas se acaban de reiniciar
	st.GraceUntil = os.clock() + Config.RebirthGrace
	st.Ascending = true
	Inventory.ClampEquipped(data)
	RebirthResultRemote:FireClient(player, dim, info)
	sync(player)
	task.spawn(DataService.Save, player)
	task.delay(Config.RebirthAscension, function()
		st.Ascending = nil
		if player.Parent then
			teleport(player, Config.LobbySpawnCFrame(dim))
			st.LastPos = nil
		end
	end)
end)

-- Rango (con diamantes)
local RANK_ERR = {
	locked = "El rango se desbloquea con el primer rebirth",
	owned = "Ya tienes ese rango",
	max = "Ya tienes el rango máximo",
	order = "Compra primero el rango anterior",
}

BuyRankRemote.OnServerEvent:Connect(function(player, rank)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(rank) ~= "number" then return end
	if rateLimited(st, "LastRank", Config.RateLimits.Rank) then return end
	local ok, err, extra = Progression.BuyRank(data, rank)
	if not ok then
		if err == "funds" then return missing(player, extra, "Diamonds") end
		if RANK_ERR[err] then notify(player, RANK_ERR[err], RED) end
		return
	end
	RankResultRemote:FireClient(player, rank)
	notify(player, "Rango " .. rank .. " desbloqueado", GREEN)
	sync(player)
end)

-- Pociones: el tiempo solo corre con el jugador conectado (este bucle solo ve jugadores conectados)
UsePotionRemote.OnServerEvent:Connect(function(player, potionType)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(potionType) ~= "string" then return end
	if rateLimited(st, "LastPotion", Config.RateLimits.Potion) then return end
	local ok, res = Purchases.UsePotion(data, potionType)
	if not ok then
		if res == "none" then notify(player, "No tienes esa poción", RED) end
		return
	end
	PotionUsedRemote:FireClient(player, potionType, res)
	notify(player, Config.Potions.Types[potionType].Name .. ": " .. waitText(res), GREEN)
	sync(player)
end)

task.spawn(function()
	while true do
		local dt = math.min(task.wait(1), 3)
		for _, player in ipairs(Players:GetPlayers()) do
			local data = DataService.Get(player)
			if data then
				local ended = Purchases.TickPotions(data, dt)
				for _, potionType in ipairs(ended) do
					PotionEndedRemote:FireClient(player, potionType)
					notify(player, Config.Potions.Types[potionType].Name .. " terminó", GOLD)
				end
				if #ended > 0 then sync(player) end
			end
		end
	end
end)

-- Pociones gratis (cooldown en tiempo real: os.time)
ClaimFreePotionsRemote.OnServerEvent:Connect(function(player)
	local st, data = state[player], DataService.Get(player)
	if not st or not data then return end
	if rateLimited(st, "LastFreePotions", Config.RateLimits.FreePotions) then return end
	if not nearTagged(player, "PotionShrine", Config.FreePotions.Range) then
		return notify(player, "Acércate al santuario de pociones", GOLD)
	end
	local ok, res, extra = Purchases.ClaimFreePotions(data, os.time())
	if not ok then
		return notify(player, "Pociones gratis otra vez en " .. waitText(extra), GOLD)
	end
	FreePotionsClaimedRemote:FireClient(player, res, data.FreePotions.NextClaim)
	notify(player, "Recibiste pociones gratis", GREEN)
	sync(player)
end)

-- Gamepasses: se revisan al entrar (cacheado en data.Passes) y al comprar dentro del juego. Id = 0: desactivado.
local passById = {}
for key, def in pairs(Config.GamePasses) do
	if def.Id > 0 then passById[def.Id] = key end
end

local function afterStatsChange(player, data)
	Inventory.ClampEquipped(data) -- si se perdió un gamepass de mascotas equipadas
	applyWalkSpeed(player)
	sync(player)
end

local function refreshPasses(player, data)
	for key, def in pairs(Config.GamePasses) do
		if def.Id > 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, player.UserId, def.Id)
			if ok then
				data.Passes[key] = owns or nil
			else
				warn("[PetNexus] No se pudo revisar el gamepass " .. key .. ": se usa lo guardado")
			end
		else
			data.Passes[key] = nil
		end
	end
	if player.Parent then afterStatsChange(player, data) end
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local key = passById[passId]
	local data = DataService.Get(player)
	if not purchased or not key or not data then return end
	data.Passes[key] = true
	GamePassGrantedRemote:FireClient(player, key)
	notify(player, "Gamepass activado: " .. Config.GamePasses[key].Name, GREEN)
	afterStatsChange(player, data)
end)

PromptGamePassRemote.OnServerEvent:Connect(function(player, key)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(key) ~= "string" then return end
	if rateLimited(st, "LastPrompt", Config.RateLimits.Prompt) then return end
	local def = Config.GamePasses[key]
	if not def or def.Id <= 0 then return notify(player, "Todavía no está a la venta", GOLD) end
	if Stats.HasPass(data, key) then return notify(player, "Ya tienes " .. def.Name, GOLD) end
	MarketplaceService:PromptGamePassPurchase(player, def.Id)
end)

-- Developer Products
local PROMPT_ERR = {
	unavailable = "Todavía no está a la venta",
	locked = "Aún no puedes comprar esto",
	rank = "Ese no es tu siguiente rango",
	ready = "Ya puedes reclamar tus pociones gratis",
	limit = "Ya usaste los saltos de hoy",
	nocooldown = "La Zona de Meditación no se está recargando",
}

local function purchaseContext(player, data)
	local hrp = getHRP(player)
	return { Dim = Progression.CurrentWorld(data, hrp and hrp.Position), Now = os.time() }
end

PromptProductRemote.OnServerEvent:Connect(function(player, key)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(key) ~= "string" then return end
	if rateLimited(st, "LastPrompt", Config.RateLimits.Prompt) then return end
	local ok, err = Purchases.CanOffer(data, key, purchaseContext(player, data))
	if not ok then
		if PROMPT_ERR[err] then notify(player, PROMPT_ERR[err], GOLD) end
		return
	end
	MarketplaceService:PromptProductPurchase(player, Config.Products[key].Id)
end)

-- ProcessReceipt: nunca entrega dos veces el mismo PurchaseId (queda en data.Receipts), no entrega si los datos no
-- cargaron, y solo confirma a Roblox cuando quedó guardado (si el guardado falla, Roblox reintenta y el PurchaseId
-- ya registrado evita la doble entrega). En Studio sin DataStore se confirma igual.
MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player or not DataService.IsLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = DataService.Get(player)
	local ok, status, key, info = pcall(Purchases.ProcessReceipt, data, receipt, purchaseContext(player, data))
	if not ok then
		warn("[PetNexus] Error entregando la compra " .. tostring(receipt.ProductId) .. ":", status)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "unknown" then
		warn("[PetNexus] Developer Product sin configurar en Config.Products:", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if status == "granted" then
		ProductGrantedRemote:FireClient(player, key, info)
		if info.Kind == "RankSkip" and info.Result == "rank" then
			RankResultRemote:FireClient(player, info.Rank)
			notify(player, "Rango " .. info.Rank .. " desbloqueado", GREEN)
		elseif info.Kind == "RankSkip" then
			notify(player, "Recibiste " .. Config.FormatNumber(info.Diamonds) .. " Diamantes", GREEN)
		elseif info.Kind == "EssenceSkip" then
			player:SetAttribute("MeditationCooldown", math.ceil(data.Meditation.Cooldown))
			notify(player, info.Result == "skipped" and "La Zona de Meditación está lista otra vez"
				or "Salto de recarga guardado: se usará en tu próxima recarga", GREEN)
		else
			notify(player, "Compra entregada", GREEN)
		end
		sync(player)
	end
	if DataService.Save(player) or RunService:IsStudio() then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

---------------------------------------------------------------- inventario, teams, items y regalos (solo lógica)
-- La UI (pestañas Pets / Items / Potions / Teams) se arma en Studio: el cliente puede usar Inventory.View(data) y
-- Gifts.Chances(itemId, data, dim) con los datos de DataSync. Los errores llegan como Notify.
-- Cliente -> servidor:
--   EquipPet(petId) / UnequipPet(petId)
--   EquipBest()
--   DeletePets({ petIds })              borrado en bulk: salta las bloqueadas y nunca deja menos de Config.Inventory.MinPets
--   SetPetLocked(petId, locked)         locked = true | false (una bloqueada no se puede borrar)
--   SaveTeam(slot, name, petIds)        petIds = nil: guarda el equipo actual; name = nil: conserva el nombre del slot
--   ApplyTeam(slot)                     equipa ese team (omite y avisa las mascotas que ya no existen)
--   RenameTeam(slot, name) / DeleteTeam(slot)
--   ClaimPlaytimeGift(n)                n = 1..12, cuando se cumplió su tiempo en esta sesión; queda como item
--   OpenGift(itemId)                    abre un regalo del inventario (Config.Items con Type = "Gift")
--   Salto de la recarga de la meditación: PromptProduct("EssenceCooldownSkip")
-- Servidor -> cliente:
--   InventoryResult(action, info)       action = "equip" | "unequip" | "equipbest" | "delete" | "lock"
--                                        delete: info = { Deleted = {ids}, Locked = n, Missing = n }
--   TeamResult(action, slot, info)      action = "save" | "apply" | "rename" | "delete"
--                                        apply: info = { Equipped, Missing, Skipped }
--   PlaytimeGiftClaimed(n, itemId)
--   GiftOpened(itemId, rewards)         rewards = { { Kind, Amount, Dim?, Potion?, Item? }, ... }
-- Atributos del jugador: PlaytimeSeconds (segundos jugados en la sesión, cada 1 s) y PlaytimeGiftsClaimed ("1,2,5");
-- el cliente arma el estado de los regalos con Gifts.StatusFrom(segundos, Gifts.ParseClaimed(texto)).
local EquipPetRemote = remote("EquipPet")
local UnequipPetRemote = remote("UnequipPet")
local EquipBestRemote = remote("EquipBest")
local DeletePetsRemote = remote("DeletePets")
local SetPetLockedRemote = remote("SetPetLocked")
local SaveTeamRemote = remote("SaveTeam")
local ApplyTeamRemote = remote("ApplyTeam")
local RenameTeamRemote = remote("RenameTeam")
local DeleteTeamRemote = remote("DeleteTeam")
local ClaimPlaytimeGiftRemote = remote("ClaimPlaytimeGift")
local OpenGiftRemote = remote("OpenGift")
local InventoryResultRemote = remote("InventoryResult")
local TeamResultRemote = remote("TeamResult")
local PlaytimeGiftClaimedRemote = remote("PlaytimeGiftClaimed")
local GiftOpenedRemote = remote("GiftOpened")

local function plural(n, one, many)
	return n .. " " .. (n == 1 and one or many)
end

-- Mascotas
local PET_ERR = {
	pet = "Esa mascota no existe",
	equipped = "Esa mascota ya está equipada",
	unequipped = "Esa mascota no está equipada",
}

EquipPetRemote.OnServerEvent:Connect(function(player, petId)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not validPetId(petId) then return end
	if rateLimited(st, "LastEquip", Config.RateLimits.Equip) then return end
	local ok, err, extra = Inventory.Equip(data, petId)
	if not ok then
		if err == "slots" then return notify(player, "Ya tienes " .. extra .. "/" .. extra .. " mascotas equipadas", GOLD) end
		return notify(player, PET_ERR[err] or "No se pudo equipar", RED)
	end
	InventoryResultRemote:FireClient(player, "equip", { PetId = petId })
	sync(player)
end)

UnequipPetRemote.OnServerEvent:Connect(function(player, petId)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not validPetId(petId) then return end
	if rateLimited(st, "LastEquip", Config.RateLimits.Equip) then return end
	local ok, err = Inventory.Unequip(data, petId)
	if not ok then return notify(player, PET_ERR[err] or "No se pudo desequipar", RED) end
	InventoryResultRemote:FireClient(player, "unequip", { PetId = petId })
	sync(player)
end)

EquipBestRemote.OnServerEvent:Connect(function(player)
	local st, data = state[player], DataService.Get(player)
	if not st or not data then return end
	if rateLimited(st, "LastEquipBest", Config.RateLimits.EquipBest) then return end
	local n = Inventory.EquipBest(data)
	InventoryResultRemote:FireClient(player, "equipbest", { Equipped = n })
	sync(player)
end)

DeletePetsRemote.OnServerEvent:Connect(function(player, petIds)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(petIds) ~= "table" then return end
	if rateLimited(st, "LastDeletePets", Config.RateLimits.DeletePets) then return end
	local ok, res, extra = Inventory.DeletePets(data, petIds)
	if not ok then
		if res == "min" then return notify(player, "Tienes que conservar al menos " .. plural(extra, "mascota", "mascotas"), RED) end
		if res == "none" and extra.Locked > 0 then return notify(player, "Las mascotas bloqueadas no se pueden borrar", GOLD) end
		if res == "none" then return notify(player, "Esas mascotas no existen", RED) end
		return
	end
	-- un auto enchant sobre una mascota borrada se detiene solo (pet_missing)
	local text = "Borraste " .. plural(#res.Deleted, "mascota", "mascotas")
	if res.Locked > 0 then text ..= " (" .. plural(res.Locked, "bloqueada no se borró", "bloqueadas no se borraron") .. ")" end
	notify(player, text, GREEN)
	InventoryResultRemote:FireClient(player, "delete", res)
	sync(player)
end)

SetPetLockedRemote.OnServerEvent:Connect(function(player, petId, locked)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not validPetId(petId) or typeof(locked) ~= "boolean" then return end
	if rateLimited(st, "LastPetLock", Config.RateLimits.PetLock) then return end
	local ok, err = Inventory.SetLocked(data, petId, locked)
	if not ok then return notify(player, PET_ERR[err] or "No se pudo bloquear", RED) end
	InventoryResultRemote:FireClient(player, "lock", { PetId = petId, Locked = locked })
	sync(player)
end)

-- Teams
local TEAM_ERR = {
	slot = "Ese slot de equipo no existe",
	name = "Nombre inválido: de 1 a " .. Config.Teams.NameMax .. " caracteres",
	filter = "No se pudo revisar el nombre, intenta de nuevo",
	pets = "Lista de mascotas inválida",
	pet = "Alguna de esas mascotas no existe",
	empty = "Ese equipo está vacío",
}

local function teamError(player, err, extra)
	if err == "size" then return notify(player, "Un equipo puede tener hasta " .. plural(extra, "mascota", "mascotas"), RED) end
	if err == "missing" then return notify(player, "Las mascotas de ese equipo ya no existen", RED) end
	notify(player, TEAM_ERR[err] or "No se pudo guardar el equipo", RED)
end

-- Filtra un texto escrito por el jugador con el filtro de Roblox (solo lo ve él). nil si el filtro falló.
local function filterText(player, text)
	local ok, result = pcall(function()
		return TextService:FilterStringAsync(text, player.UserId):GetNonChatStringForUserAsync(player.UserId)
	end)
	if not ok or typeof(result) ~= "string" then return nil end
	return result
end

-- Limpia y filtra el nombre de un team (nil = sin nombre). Devuelve ok, nombre o código de error.
local function teamName(player, name)
	if name == nil then return true, nil end
	local clean = Inventory.CleanTeamName(name)
	if not clean then return false, "name" end
	local filtered = filterText(player, clean)
	if not filtered then return false, "filter" end
	return true, filtered
end

SaveTeamRemote.OnServerEvent:Connect(function(player, slot, name, petIds)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(slot) ~= "number" then return end
	if (name ~= nil and typeof(name) ~= "string") or (petIds ~= nil and typeof(petIds) ~= "table") then return end
	if rateLimited(st, "LastTeam", Config.RateLimits.Team) then return end
	if not Inventory.ValidSlot(slot) then return teamError(player, "slot") end
	local okName, clean = teamName(player, name)
	if not okName then return teamError(player, clean) end
	data = DataService.Get(player) -- el filtro espera: el jugador pudo salir
	if not data then return end
	local ok, team, extra = Inventory.SaveTeam(data, slot, clean, petIds)
	if not ok then return teamError(player, team, extra) end
	TeamResultRemote:FireClient(player, "save", slot, team)
	notify(player, "Equipo guardado: " .. team.Name, GREEN)
	sync(player)
end)

ApplyTeamRemote.OnServerEvent:Connect(function(player, slot)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(slot) ~= "number" then return end
	if rateLimited(st, "LastApplyTeam", Config.RateLimits.ApplyTeam) then return end
	local ok, res, extra = Inventory.ApplyTeam(data, slot)
	if not ok then return teamError(player, res, extra) end
	local text = "Equipo aplicado: " .. plural(res.Equipped, "mascota", "mascotas")
	if res.Missing > 0 then text ..= "; " .. plural(res.Missing, "ya no existe y se omitió", "ya no existen y se omitieron") end
	if res.Skipped > 0 then text ..= "; " .. plural(res.Skipped, "no entra", "no entran") .. " en tu equipo" end
	notify(player, text, (res.Missing > 0 or res.Skipped > 0) and GOLD or GREEN)
	TeamResultRemote:FireClient(player, "apply", slot, res)
	sync(player)
end)

RenameTeamRemote.OnServerEvent:Connect(function(player, slot, name)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(slot) ~= "number" or typeof(name) ~= "string" then return end
	if rateLimited(st, "LastTeam", Config.RateLimits.Team) then return end
	if not Inventory.GetTeam(data, slot) then return teamError(player, Inventory.ValidSlot(slot) and "empty" or "slot") end
	local okName, clean = teamName(player, name)
	if not okName then return teamError(player, clean) end
	data = DataService.Get(player)
	if not data then return end
	local ok, err = Inventory.RenameTeam(data, slot, clean)
	if not ok then return teamError(player, err) end
	TeamResultRemote:FireClient(player, "rename", slot, { Name = clean })
	sync(player)
end)

DeleteTeamRemote.OnServerEvent:Connect(function(player, slot)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(slot) ~= "number" then return end
	if rateLimited(st, "LastTeam", Config.RateLimits.Team) then return end
	local ok, err = Inventory.DeleteTeam(data, slot)
	if not ok then return teamError(player, err) end
	TeamResultRemote:FireClient(player, "delete", slot, nil)
	notify(player, "Equipo borrado", GREEN)
	sync(player)
end)

-- Regalos por tiempo jugado (la sesión vive en state[player].Playtime: se reinicia al salir del juego)
local function itemName(itemId)
	local def = Config.Items[itemId]
	return def and def.Name or tostring(itemId)
end

local function rewardText(r)
	if r.Kind == "Coins" then return "+" .. Config.FormatNumber(r.Amount) .. " " .. curName(r.Dim) end
	if r.Kind == "Diamonds" then return "+" .. Config.FormatNumber(r.Amount) .. " Diamantes" end
	if r.Kind == "Potion" then return "+" .. r.Amount .. " " .. Config.Potions.Types[r.Potion].Name end
	return "+" .. r.Amount .. " " .. itemName(r.Item)
end

local function updatePlaytime(player, st)
	player:SetAttribute("PlaytimeSeconds", math.floor(Gifts.Elapsed(st.Playtime, os.clock())))
	player:SetAttribute("PlaytimeGiftsClaimed", Gifts.ClaimedText(st.Playtime))
end

ClaimPlaytimeGiftRemote.OnServerEvent:Connect(function(player, n)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or not st.Playtime or typeof(n) ~= "number" then return end
	if rateLimited(st, "LastPlaytimeGift", Config.RateLimits.PlaytimeGift) then return end
	local ok, res, extra = Gifts.Claim(st.Playtime, data, n, os.clock())
	if not ok then
		if res == "wait" then return notify(player, "Ese regalo estará listo en " .. waitText(extra), GOLD) end
		if res == "claimed" then return notify(player, "Ya reclamaste ese regalo", GOLD) end
		return
	end
	updatePlaytime(player, st)
	st.PlaytimeReady = Gifts.ReadyCount(st.Playtime, os.clock())
	PlaytimeGiftClaimedRemote:FireClient(player, n, res)
	notify(player, "Recibiste: " .. itemName(res), GREEN)
	sync(player)
end)

OpenGiftRemote.OnServerEvent:Connect(function(player, itemId)
	local st, data = state[player], DataService.Get(player)
	if not st or not data or typeof(itemId) ~= "string" then return end
	if rateLimited(st, "LastOpenGift", Config.RateLimits.OpenGift) then return end
	local ok, res = Gifts.Open(data, itemId, rng, purchaseContext(player, data))
	if not ok then
		if res == "none" then notify(player, "No tienes ese regalo", RED) end
		return
	end
	local parts = {}
	for _, r in ipairs(res) do table.insert(parts, rewardText(r)) end
	GiftOpenedRemote:FireClient(player, itemId, res)
	notify(player, itemName(itemId) .. ": " .. table.concat(parts, ", "), GREEN)
	sync(player)
end)

-- Cada segundo: atributos para la UI y aviso cuando un regalo queda listo
task.spawn(function()
	while true do
		task.wait(1)
		local now = os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			local st = state[player]
			if st and st.Playtime and DataService.Get(player) then
				updatePlaytime(player, st)
				local ready = Gifts.ReadyCount(st.Playtime, now)
				if ready > (st.PlaytimeReady or 0) then
					notify(player, "Tienes un regalo por tiempo jugado listo para reclamar", GREEN)
				end
				st.PlaytimeReady = ready
			end
		end
	end
end)

---------------------------------------------------------------- jugadores
-- Opciones de migración de datos (ver DataService.Reconcile)
local rebirthOrder = {}
for dim in pairs(Config.Rebirths) do table.insert(rebirthOrder, dim) end
table.sort(rebirthOrder, function(a, b) return Config.Rebirths[a].Number < Config.Rebirths[b].Number end)
local LOAD_OPTS = { StartWorld = Config.SpawnWorld(), RebirthOrder = rebirthOrder, StartLevel = Config.PetLevels.StartLevel }

-- Otro servidor abrió la partida (el lock ya no es de esta sesión): se saca al jugador para que no juegue sin guardar
DataService.OnSessionLost = function(player)
	if player.Parent then player:Kick("Tu partida se abrió en otro servidor. Vuelve a entrar para seguir jugando.") end
end

local function onPlayerAdded(player)
	-- el tiempo de los regalos cuenta desde que entra (sesión nueva cada vez: no se guarda)
	state[player] = { Playtime = Gifts.NewSession(os.clock()) }
	local data = DataService.Load(player, LOAD_OPTS)
	if not data or not player.Parent then return end -- salió mientras cargaba
	if not DataService.IsLoaded(player) then
		notify(player, "No se pudieron cargar tus datos: esta sesión no se guardará. Vuelve a entrar más tarde", RED)
	end
	if #data.Pets == 0 then
		addPet(data, "Sprout")
	else
		Inventory.ClampEquipped(data)
		Inventory.PruneTeams(data)
	end
	player.CharacterAdded:Connect(function()
		local st = state[player]
		if not st then return end
		st.LastTeleport = os.clock()
		st.LastPos = nil
		task.wait(0.5)
		applyWalkSpeed(player)
		sync(player)
	end)
	applyWalkSpeed(player)
	sync(player)
	task.spawn(refreshPasses, player, data) -- gamepasses reales (puede tardar: se sincroniza de nuevo al terminar)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

Players.PlayerRemoving:Connect(function(player)
	autoJobs[player] = nil -- corta el auto enchant (el bucle ve que su trabajo ya no es el actual)
	DataService.Release(player)
	state[player] = nil
	for _, b in pairs(breakables) do b.DamageBy[player] = nil end
end)

-- Autoguardado (también renueva el lock de sesión de cada jugador)
task.spawn(function()
	while true do
		task.wait(Config.Save.AutoSaveInterval)
		DataService.SaveAll()
	end
end)

-- Al cerrar el servidor: guarda y libera a todos en paralelo (Roblox espera hasta 30 s)
game:BindToClose(function()
	DataService.CloseAll(Config.Save.CloseTimeout)
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
		-- coins / unlock: número (Nexus) o { Dim = "Greenwood", Value = n }
		if cmd == "coins" then
			if typeof(value) == "table" then data.Currency[value.Dim] = value.Value else data.Currency.Nexus = value end
		elseif cmd == "unlock" then
			if typeof(value) == "table" then data.Unlocked[value.Dim] = value.Value else data.Unlocked.Nexus = value end
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
		elseif cmd == "rebirth" then -- value = "Greenwood": marca el rebirth como hecho (sin requisitos ni reinicio)
			if not Config.Rebirths[value] then return "mundo sin rebirth" end
			data.RebirthsDone[value] = true
		elseif cmd == "unrebirth" then -- value = "Greenwood": deshace el rebirth
			data.RebirthsDone[value] = nil
		elseif cmd == "rank" then -- value = 0..10
			if typeof(value) ~= "number" or value < 0 or value > #Config.Ranks.Levels then return "rango inválido" end
			data.Rank = math.floor(value)
		elseif cmd == "xp" then -- value = { Pet = índice o Id, XP = 500 }: suma XP y sube niveles
			local pet = debugPet(data, value.Pet)
			if not pet then return "mascota inválida" end
			Progression.AddPetXP(pet, value.XP or 0)
		elseif cmd == "level" then -- value = { Pet = índice o Id, Level = 50 }
			local pet = debugPet(data, value.Pet)
			if not pet or typeof(value.Level) ~= "number" then return "mascota o nivel inválido" end
			pet.Level = math.clamp(math.floor(value.Level), 1, Config.PetLevels.MaxLevel)
			pet.XP = 0
		elseif cmd == "potions" then -- value = { Luck = 5, Coins = 2, ... } al inventario
			Purchases.AddPotions(data, value)
		elseif cmd == "potiontime" then -- value = { Luck = 60 }: segundos restantes de la poción activa
			for id, t in pairs(value) do
				if Config.Potions.Types[id] then data.PotionTime[id] = t end
			end
		elseif cmd == "pass" then -- value = { Key = "VIP", Owned = true }: simula ser dueño (se borra al volver a entrar)
			if not Config.GamePasses[value.Key] then return "gamepass inválido" end
			data.Passes[value.Key] = value.Owned ~= false or nil
		elseif cmd == "freepotions" then -- reinicia el cooldown y los saltos del día de las pociones gratis
			data.FreePotions.NextClaim = 0
			data.FreePotions.SkipsUsed = 0
		elseif cmd == "fillpets" then -- value = número o { Name = "Sprout", Count = n }; sin cantidad: hasta llenar el inventario
			local name = typeof(value) == "table" and value.Name or "Sprout"
			local count = typeof(value) == "number" and value or (typeof(value) == "table" and value.Count) or Inventory.Space(data)
			for _ = 1, count do
				if not addPet(data, name) then break end
			end
		elseif cmd == "item" then -- value = { Id = "GiftSmall", Count = 3 }
			if typeof(value) ~= "table" or not Inventory.AddItem(data, value.Id, value.Count or 1) then return "item inválido" end
		elseif cmd == "gifts" then -- value = cantidad de cada regalo (1 por defecto)
			for id, def in pairs(Config.Items) do
				if def.Type == "Gift" then Inventory.AddItem(data, id, value or 1) end
			end
		elseif cmd == "playtime" then -- value = segundos para adelantar el tiempo de los regalos de esta sesión
			local st = state[player]
			if not st or not st.Playtime or typeof(value) ~= "number" then return "valor inválido" end
			st.Playtime.Offset += value
			updatePlaytime(player, st)
		elseif cmd == "lockstolen" then -- simula que otro servidor tomó la partida: el próximo guardado la da por perdida
			return DataService.DebugStealLock(player) and "ok" or "sin DataStore"
		elseif cmd == "missioncut" then -- value = segundos a recortar de la recarga (por defecto, lo de una misión)
			cutMeditationCooldown(player, value or Config.Meditation.MissionCooldownCut)
		elseif cmd == "equipbest" then Inventory.EquipBest(data)
		elseif cmd == "get" then return HttpService:JSONEncode(data) end
		Inventory.ClampEquipped(data)
		applyWalkSpeed(player)
		sync(player)
		return "ok"
	end
	dbg.Parent = game:GetService("ServerStorage")
end
