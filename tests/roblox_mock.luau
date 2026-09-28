-- Simulación mínima de Roblox para correr el script real del servidor en Lune (tests de humo, sin Studio).
-- Incluye: instancias con hijos/atributos, señales, reloj simulado (task.wait / os.clock / os.time), servicios,
-- RemoteEvents que registran lo enviado, DataStore en memoria y MarketplaceService.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Vector3, CFrame = roblox.Vector3, roblox.CFrame

local Mock = {}

---------------------------------------------------------------- reloj y tareas
local now = 0
local BASE_TIME = 1790000000
local sleeping = {}

local function resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then error(debug.traceback(co, tostring(err)), 0) end
end

local task = {}
function task.spawn(fn, ...)
	local co = type(fn) == "thread" and fn or coroutine.create(fn)
	resume(co, ...)
	return co
end
task.defer = task.spawn
function task.wait(t)
	local co = coroutine.running()
	table.insert(sleeping, { co = co, wake = now + (t or 0.03), start = now })
	return coroutine.yield()
end
function task.delay(t, fn, ...)
	local args = table.pack(...)
	return task.spawn(function()
		task.wait(t)
		fn(table.unpack(args, 1, args.n))
	end)
end
Mock.task = task

local heartbeat -- señal, se crea con los servicios

-- Avanza el reloj simulado 'seconds' en pasos de 'step' (Heartbeat y tareas dormidas se despiertan en orden)
function Mock.advance(seconds, step)
	step = step or 0.1
	local target = now + seconds
	while now < target - 1e-9 do
		local dt = math.min(step, target - now)
		now += dt
		heartbeat:Fire(dt)
		local due = {}
		for i = #sleeping, 1, -1 do
			if sleeping[i].wake <= now + 1e-9 then
				table.insert(due, table.remove(sleeping, i))
			end
		end
		table.sort(due, function(a, b) return a.wake < b.wake end)
		for _, s in ipairs(due) do resume(s.co, now - s.start) end
	end
end

local fakeOs = setmetatable({
	clock = function() return now end,
	time = function() return BASE_TIME + math.floor(now) end,
}, { __index = os })

---------------------------------------------------------------- señales
local function Signal()
	local s = { handlers = {} }
	function s:Connect(fn)
		local h = { fn = fn }
		table.insert(self.handlers, h)
		return { Disconnect = function() h.fn = nil end }
	end
	function s:Once(fn)
		local conn
		conn = self:Connect(function(...) conn.Disconnect(); fn(...) end)
		return conn
	end
	function s:Fire(...)
		for _, h in ipairs(table.clone(self.handlers)) do
			if h.fn then task.spawn(h.fn, ...) end
		end
	end
	return s
end
Mock.Signal = Signal

---------------------------------------------------------------- instancias
local Inst = {}
local tags = {}
local tagAdded, tagRemoved = {}, {}

local BASEPART = { Part = true, MeshPart = true, WedgePart = true }
local SIGNAL_PROPS = { OnServerEvent = true, AncestryChanged = true, Triggered = true, CharacterAdded = true, Destroying = true }

local function newInstance(className, name)
	local self = setmetatable({}, Inst)
	rawset(self, "_p", { ClassName = className, Name = name or className, _children = {}, _attrs = {}, _attrSignals = {} })
	if BASEPART[className] then
		self._p.CFrame = CFrame.new()
		self._p.Size = Vector3.new(4, 1, 2)
	end
	return self
end

local methods = {}
Inst.__index = function(self, key)
	local p = rawget(self, "_p")
	if methods[key] then return methods[key] end
	if key == "Position" and p.CFrame then return p.CFrame.Position end
	if key == "Parent" then return p._parent end
	if SIGNAL_PROPS[key] then
		p[key] = p[key] or Signal()
		return p[key]
	end
	if p[key] ~= nil then return p[key] end
	for _, c in ipairs(p._children) do
		if c.Name == key then return c end
	end
	return nil
end
Inst.__newindex = function(self, key, value)
	local p = rawget(self, "_p")
	if key == "Parent" then
		local old = p._parent
		if old then
			local list = rawget(old, "_p")._children
			for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
		end
		p._parent = value
		if value then table.insert(rawget(value, "_p")._children, self) end
		if old and not value then
			for tag in pairs(p._tags or {}) do
				local list = tags[tag]
				for i, x in ipairs(list) do if x == self then table.remove(list, i) break end end
				if tagRemoved[tag] then tagRemoved[tag]:Fire(self) end
			end
		end
	elseif key == "Position" and p.CFrame then
		p.CFrame = p.CFrame + (value - p.CFrame.Position)
	else
		p[key] = value
	end
end
Inst.__tostring = function(self) return rawget(self, "_p").ClassName .. " " .. tostring(rawget(self, "_p").Name) end

function methods:IsA(class)
	local cn = self.ClassName
	return cn == class or class == "Instance" or (class == "BasePart" and BASEPART[cn] ~= nil)
end
function methods:GetChildren() return table.clone(rawget(self, "_p")._children) end
function methods:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in ipairs(rawget(i, "_p")._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name, recursive)
	for _, c in ipairs(recursive and self:GetDescendants() or self:GetChildren()) do
		if c.Name == name then return c end
	end
	return nil
end
function methods:WaitForChild(name)
	return assert(self:FindFirstChild(name), "WaitForChild sin hijo: " .. tostring(name))
end
function methods:FindFirstChildOfClass(cn)
	for _, c in ipairs(self:GetChildren()) do if c.ClassName == cn then return c end end
	return nil
end
function methods:FindFirstChildWhichIsA(cn)
	for _, c in ipairs(self:GetChildren()) do if c:IsA(cn) then return c end end
	return nil
end
function methods:SetAttribute(k, v)
	local p = rawget(self, "_p")
	local changed = p._attrs[k] ~= v
	p._attrs[k] = v
	if changed and p._attrSignals[k] then p._attrSignals[k]:Fire() end
end
function methods:GetAttribute(k) return rawget(self, "_p")._attrs[k] end
function methods:GetAttributeChangedSignal(k)
	local p = rawget(self, "_p")
	p._attrSignals[k] = p._attrSignals[k] or Signal()
	return p._attrSignals[k]
end
function methods:Destroy() self.Parent = nil end
function methods:ClearAllChildren() for _, c in ipairs(self:GetChildren()) do c:Destroy() end end
function methods:Clone()
	local p = rawget(self, "_p")
	local copy = newInstance(p.ClassName, p.Name)
	for k, v in pairs(p) do
		if k ~= "_children" and k ~= "_attrs" and k ~= "_parent" and k ~= "_attrSignals" and k ~= "_tags" and not SIGNAL_PROPS[k] then
			rawget(copy, "_p")[k] = v
		end
	end
	for k, v in pairs(p._attrs) do rawget(copy, "_p")._attrs[k] = v end
	for _, c in ipairs(p._children) do
		local cc = c:Clone()
		cc.Parent = copy
		if p.PrimaryPart == c then rawget(copy, "_p").PrimaryPart = cc end
	end
	return copy
end
function methods:ScaleTo() end
function methods:GetPivot()
	local p = rawget(self, "_p")
	if p.CFrame then return p.CFrame end
	if p.PrimaryPart then return p.PrimaryPart.CFrame end
	return p._pivot or CFrame.new()
end
function methods:PivotTo(cf)
	local p = rawget(self, "_p")
	if p.CFrame then p.CFrame = cf return end
	local hrp = self:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = cf end
	if p.PrimaryPart and p.PrimaryPart ~= hrp then p.PrimaryPart.CFrame = cf end
	p._pivot = cf
end
function methods:GetBoundingBox() return self:GetPivot(), Vector3.new(4, 4, 4) end
-- RemoteEvent / BindableFunction
function methods:FireClient(player, ...)
	Mock.sent[player] = Mock.sent[player] or {}
	table.insert(Mock.sent[player], { Remote = self.Name, Args = table.pack(...) })
end
function methods:FireAllClients(...) end
function methods:Invoke(...) return rawget(self, "_p").OnInvoke(...) end
function methods:InputHoldBegin() end
function methods:Kick(message)
	Mock.kicked[self] = message or ""
end

Mock.Instance = { new = function(cn, parent)
	local i = newInstance(cn)
	if parent then i.Parent = parent end
	return i
end }
Mock.sent = {}
Mock.kicked = {}

-- Eventos enviados a un jugador con ese nombre de remote
function Mock.events(player, remoteName)
	local out = {}
	for _, e in ipairs(Mock.sent[player] or {}) do
		if e.Remote == remoteName then table.insert(out, e.Args) end
	end
	return out
end
function Mock.clearEvents() Mock.sent = {} end

---------------------------------------------------------------- servicios
local function folder(name, parent)
	local f = newInstance("Folder", name)
	if parent then f.Parent = parent end
	return f
end

function Mock.build()
	heartbeat = Signal()
	local services = {}

	local CollectionService = newInstance("CollectionService")
	function CollectionService:GetTagged(tag) return table.clone(tags[tag] or {}) end
	function CollectionService:AddTag(inst, tag)
		tags[tag] = tags[tag] or {}
		table.insert(tags[tag], inst)
		local p = rawget(inst, "_p")
		p._tags = p._tags or {}
		p._tags[tag] = true
		if tagAdded[tag] then tagAdded[tag]:Fire(inst) end
	end
	function CollectionService:GetInstanceAddedSignal(tag) tagAdded[tag] = tagAdded[tag] or Signal() return tagAdded[tag] end
	function CollectionService:GetInstanceRemovedSignal(tag) tagRemoved[tag] = tagRemoved[tag] or Signal() return tagRemoved[tag] end
	services.CollectionService = CollectionService

	local Players = newInstance("Players")
	rawget(Players, "_p").PlayerAdded = Signal()
	rawget(Players, "_p").PlayerRemoving = Signal()
	function Players:GetPlayers()
		local out = {}
		for _, c in ipairs(self:GetChildren()) do if c.ClassName == "Player" then table.insert(out, c) end end
		return out
	end
	function Players:GetPlayerByUserId(id)
		for _, p in ipairs(self:GetPlayers()) do if p.UserId == id then return p end end
		return nil
	end
	services.Players = Players

	local RunService = newInstance("RunService")
	rawget(RunService, "_p").Heartbeat = heartbeat
	function RunService:IsStudio() return true end
	services.RunService = RunService

	local guid = 0
	local HttpService = newInstance("HttpService")
	function HttpService:GenerateGUID() guid += 1 return "guid-" .. guid end
	function HttpService:JSONEncode(v) return serde.encode("json", v) end
	services.HttpService = HttpService

	-- DataStore en memoria (Mock.store.fail = true simula errores; budget = presupuesto de peticiones).
	-- Como en Roblox, si el transform de UpdateAsync devuelve nil no se escribe nada.
	local store = { saved = {}, fail = false, saves = 0, budget = 100 }
	local function copy(v) return v and serde.decode("json", serde.encode("json", v)) or nil end
	function store:GetAsync(key)
		if self.fail then error("DataStore caído") end
		return copy(self.saved[key])
	end
	function store:UpdateAsync(key, fn)
		if self.fail then error("DataStore caído") end
		local result = fn(copy(self.saved[key]))
		if result == nil then return nil end
		self.saved[key] = copy(result)
		self.saves += 1
		return copy(result)
	end
	Mock.store = store
	local DataStoreService = newInstance("DataStoreService")
	function DataStoreService:GetDataStore() return store end
	function DataStoreService:GetRequestBudgetForRequestType() return store.budget end
	services.DataStoreService = DataStoreService

	-- Filtro de texto: Mock.textFilter(texto) decide el resultado (por defecto no cambia nada)
	local TextService = newInstance("TextService")
	function TextService:FilterStringAsync(text)
		local out = Mock.textFilter and Mock.textFilter(text) or text
		return { GetNonChatStringForUserAsync = function() return out end }
	end
	services.TextService = TextService

	local market = { owned = {}, prompts = {} }
	local MarketplaceService = newInstance("MarketplaceService")
	rawget(MarketplaceService, "_p").PromptGamePassPurchaseFinished = Signal()
	function MarketplaceService:UserOwnsGamePassAsync(userId, passId) return market.owned[passId] == true end
	function MarketplaceService:PromptProductPurchase(player, id) table.insert(market.prompts, { Kind = "Product", Id = id }) end
	function MarketplaceService:PromptGamePassPurchase(player, id) table.insert(market.prompts, { Kind = "GamePass", Id = id }) end
	Mock.market = market
	services.MarketplaceService = MarketplaceService

	local ReplicatedStorage = newInstance("ReplicatedStorage")
	local petNexus = folder("PetNexus", ReplicatedStorage)
	for _, n in ipairs({ "Config", "Icons", "Stats", "Economy", "Progression", "Purchases", "Inventory", "Gifts" }) do
		local ms = newInstance("ModuleScript", n)
		ms.Parent = petNexus
	end
	local remotes = folder("Remotes", petNexus)
	for _, n in ipairs({ "Notify", "DataSync", "Damage", "SetTarget", "HatchResult", "BuyArea", "AreaUnlocked", "Teleport" }) do
		local r = newInstance("RemoteEvent", n)
		r.Parent = remotes
	end
	local assets = folder("PetNexusAssets", ReplicatedStorage)
	local brk = folder("Breakables", assets)
	for _, n in ipairs({ "AngelCoinPile", "AngelGift", "HeavenChest" }) do
		local m = newInstance("Model", n)
		local pp = newInstance("Part", "Base")
		pp.Parent = m
		m.PrimaryPart = pp
		m.Parent = brk
	end
	services.ReplicatedStorage = ReplicatedStorage

	local ServerScriptService = newInstance("ServerScriptService")
	newInstance("ModuleScript", "DataService").Parent = ServerScriptService
	services.ServerScriptService = ServerScriptService
	services.ServerStorage = newInstance("ServerStorage")

	local workspace = newInstance("Workspace")
	folder("Breakables", workspace)
	folder("World", workspace)

	local closeFns = {}
	local game = newInstance("DataModel")
	rawget(game, "_p").JobId = "mock-servidor"
	function game:GetService(name) return assert(services[name], "servicio no simulado: " .. name) end
	function game:BindToClose(fn) table.insert(closeFns, fn) end
	-- Simula el cierre del servidor: corre las funciones de BindToClose (cada una en su hilo, como Roblox)
	function Mock.close()
		for _, fn in ipairs(closeFns) do task.spawn(fn) end
	end
	Mock.services = services
	Mock.workspace = workspace
	Mock.game = game
	return game
end

---------------------------------------------------------------- cargar módulos y el servidor
local Enum = setmetatable({}, { __index = function(_, k)
	return setmetatable({}, { __index = function(_, v) return k .. "." .. v end })
end })
Mock.Enum = Enum

local function newRandom(seed)
	local state = (seed or 1) % 2147483647
	if state <= 0 then state += 2147483646 end
	local r = {}
	function r:NextNumber(min, max)
		state = (state * 16807) % 2147483647
		local x = (state - 1) / 2147483646
		if min then return min + x * (max - min) end
		return x
	end
	function r:NextInteger(min, max) return min + math.floor(self:NextNumber() * (max - min + 1)) end
	return r
end

-- Carga el servidor completo. configure(Config) permite ajustar Config (Ids de productos, etc.) antes de arrancar.
function Mock.startServer(configure)
	local game = Mock.build()
	local rs = game:GetService("ReplicatedStorage")
	local modules = {}
	local env = {
		game = game, workspace = Mock.workspace, task = task, os = fakeOs, Enum = Enum,
		Instance = Mock.Instance, Random = { new = newRandom },
		Vector3 = Vector3, CFrame = CFrame, Color3 = roblox.Color3, Vector2 = roblox.Vector2,
		ColorSequence = roblox.ColorSequence, NumberSequence = roblox.NumberSequence, NumberRange = roblox.NumberRange,
		warn = function(...) table.insert(Mock.warnings, table.concat(table.pack(...), " ", 1, select("#", ...))) end,
		print = function() end,
	}
	Mock.warnings = {}
	env.require = function(ms)
		local m = modules[ms.Name]
		return assert(m, "require de módulo no cargado: " .. tostring(ms))
	end
	env.script = { Parent = rs.PetNexus }
	local function load(path, name)
		local fn = luau.load(fs.readFile(path), { debugName = path, environment = env })
		modules[name] = fn()
	end
	load("src/shared/Config.luau", "Config")
	if configure then configure(modules.Config) end
	load("src/shared/Stats.luau", "Stats")
	load("src/shared/Economy.luau", "Economy")
	load("src/shared/Progression.luau", "Progression")
	load("src/shared/Purchases.luau", "Purchases")
	load("src/shared/Inventory.luau", "Inventory")
	load("src/shared/Gifts.luau", "Gifts")
	load("src/server/DataService.luau", "DataService")
	Mock.modules = modules
	local server = luau.load(fs.readFile("src/server/PetNexusServer.server.luau"), { debugName = "PetNexusServer", environment = env })
	task.spawn(server)
	return modules
end

-- Crea un jugador con personaje en 'pos' y lo hace entrar
local nextUserId = 100
function Mock.addPlayer(pos)
	nextUserId += 1
	local services = Mock.services
	local player = newInstance("Player", "Jugador" .. nextUserId)
	local p = rawget(player, "_p")
	p.UserId = nextUserId
	local char = newInstance("Model", "Character")
	local hrp = newInstance("Part", "HumanoidRootPart")
	hrp.CFrame = CFrame.new(pos or Vector3.new(0, 3, 40))
	hrp.Parent = char
	local hum = newInstance("Humanoid", "Humanoid")
	hum.WalkSpeed = 16
	hum.Health = 100
	hum.Parent = char
	char.PrimaryPart = hrp
	p.Character = char
	player.Parent = services.Players
	rawget(services.Players, "_p").PlayerAdded:Fire(player)
	return player, hrp
end

function Mock.removePlayer(player)
	rawget(Mock.services.Players, "_p").PlayerRemoving:Fire(player)
	player.Parent = nil
end

-- Part con tag (y atributos) en una posición
function Mock.taggedPart(tag, pos, size, attrs)
	local part = newInstance("Part", tag)
	part.CFrame = CFrame.new(pos)
	part.Size = size or Vector3.new(4, 4, 4)
	for k, v in pairs(attrs or {}) do part:SetAttribute(k, v) end
	part.Parent = Mock.workspace
	Mock.services.CollectionService:AddTag(part, tag)
	return part
end

-- Dispara un RemoteEvent del cliente al servidor
function Mock.fire(player, remoteName, ...)
	local r = Mock.services.ReplicatedStorage.PetNexus.Remotes:FindFirstChild(remoteName)
	assert(r, "remote inexistente: " .. remoteName)
	r.OnServerEvent:Fire(player, ...)
end

function Mock.debug(cmd, player, value)
	return Mock.services.ServerStorage.PetNexusDebug:Invoke(cmd, player, value)
end

function Mock.now() return now end
function Mock.unixNow() return BASE_TIME + math.floor(now) end

return Mock
