-- Pet Nexus: servidor principal (todo lo importante se decide aquí = anticheat)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Config = require(ReplicatedStorage.PetNexus.Config)
local DataService = require(ServerScriptService.DataService)
local Remotes = ReplicatedStorage.PetNexus.Remotes

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

local function petPower(name)
	local p = Config.Pets[name]
	return p and p.Power or 0
end

local function equipBest(data)
	table.sort(data.Pets, function(a, b) return petPower(a.Name) > petPower(b.Name) end)
	for i, pet in ipairs(data.Pets) do
		pet.Equipped = i <= Config.MaxEquipped
	end
end

local function getPower(player)
	local data = DataService.Get(player)
	if not data then return 0 end
	local total = 0
	for _, pet in ipairs(data.Pets) do
		if pet.Equipped then total += petPower(pet.Name) end
	end
	return total * (1 + data.Rebirths * 0.5)
end

local function addPet(data, name)
	table.insert(data.Pets, { Id = HttpService:GenerateGUID(false), Name = name, Equipped = false })
	equipBest(data)
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
		Uid = uid, Model = model, Dim = dim, Zone = zone,
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
			local reward = math.max(1, math.floor(b.Reward * (dmg / total) * (1 + data.Rebirths * 0.5)))
			addCur(data, b.Dim, reward)
			Remotes.Damage:FireClient(player, "break", b.Position, reward, b.Dim)
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
			if b then
				damage(b, player, getPower(player) * 2 * step)
			end
		end
	end
end)

---------------------------------------------------------------- huevos
local function rollEgg(eggId, data)
	local egg = Config.Eggs[eggId]
	data.Pity[eggId] = (data.Pity[eggId] or 0) + 1
	local pool = egg.Pets
	local forced = data.Pity[eggId] >= Config.PityThreshold
	if forced then
		pool = {}
		for _, e in ipairs(egg.Pets) do
			if Config.Rarities[Config.Pets[e[1]].Rarity].Order >= 3 then table.insert(pool, e) end
		end
	end
	local total = 0
	for _, e in ipairs(pool) do total += e[2] end
	local r = rng:NextNumber(0, total)
	local pick = pool[#pool][1]
	for _, e in ipairs(pool) do
		r -= e[2]
		if r <= 0 then pick = e[1] break end
	end
	if Config.Rarities[Config.Pets[pick].Rarity].Order >= 3 then
		data.Pity[eggId] = 0
	end
	return pick, forced
end

local function hookEgg(eggPart)
	local prompt = eggPart:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function(player)
		local data = DataService.Get(player)
		local st = state[player]
		if not data or not st then return end
		if os.clock() - (st.LastHatch or 0) < 0.8 then return end
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
			notify(player, "La tienda abre muy pronto", Color3.fromRGB(255, 190, 230))
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
		sync(player)
	end)
	sync(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end

Players.PlayerRemoving:Connect(function(player)
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
	dbg.OnInvoke = function(cmd, player, value)
		local data = DataService.Get(player)
		if not data then return "sin datos" end
		if cmd == "coins" then data.Currency.Nexus = value
		elseif cmd == "unlock" then data.Unlocked.Nexus = value
		elseif cmd == "teleport" then teleport(player, value)
		elseif cmd == "get" then return HttpService:JSONEncode(data) end
		sync(player)
		return "ok"
	end
	dbg.Parent = game:GetService("ServerStorage")
end
