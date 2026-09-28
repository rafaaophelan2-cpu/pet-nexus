-- Pet Nexus: guardado de datos (DataStore) con sesión en memoria y bloqueo de sesión.
--
-- Bloqueo de sesión (evita duplicar mascotas o compras si la partida se abre en dos servidores):
--   El registro guardado es la tabla de datos del jugador más el campo SessionLock = { JobId, Session, Time }.
--   - Load toma el lock con UpdateAsync (lectura y escritura atómicas). Si otro servidor lo tiene, reintenta cada
--     Config.Save.LockRetryDelay; el lock se considera abandonado si no se renovó en LockExpire segundos, o tras
--     esperar LockWaitMax. Si la carga falla, la sesión nunca se guarda (no pisa los datos reales).
--   - Save solo escribe si el lock sigue siendo de esta sesión (y lo renueva). Si otro servidor lo tomó, la sesión
--     queda perdida: no se vuelve a guardar y se avisa con DataService.OnSessionLost(player).
--   - Release guarda por última vez y quita el lock. Después de eso ningún guardado de esta sesión escribe.
--   Los registros viejos (sin SessionLock) cargan igual: el formato de los datos no cambia.
--
-- Cada petición respeta el presupuesto de DataStore (GetRequestBudgetForRequestType) y reintenta ante errores con
-- espera creciente (RetryBase, x2, hasta RetryMax).
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.PetNexus.Config)

local STORE_NAME = "PetNexus_v2" -- v2: Nexus pasa a ser el mundo 1 (datos de v1 no se usan). Se mantiene: los datos migran solos.
local LOCK_FIELD = "SessionLock"
local SAVE = Config.Save

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
	end)
	if not ok then warn("[PetNexus] DataStore no disponible:", err) end
end

-- Id de este servidor (en Studio game.JobId es "": se usa uno único por ejecución)
local JOB_ID = (type(game.JobId) == "string" and game.JobId ~= "") and game.JobId or ("local-" .. HttpService:GenerateGUID(false))

local DataService = {}
DataService.JobId = JOB_ID
DataService.LockField = LOCK_FIELD
-- Se llama (en otro hilo) cuando otro servidor tomó la partida de un jugador conectado aquí. La asigna el servidor.
DataService.OnSessionLost = nil

-- [player] = { Player, Key, Id, Data, Failed, Lost, Releasing, Saving }
local sessions = {}
local activeIds = {} -- [Id] = true: sesiones con lock tomado en este servidor (aún no liberado)
local loading = 0    -- cargas en curso (BindToClose las espera)

local function defaultData()
	return {
		Currency = {}, -- moneda propia de cada mundo ([dim] = cantidad; Nexus = Angel Coins, Greenwood = Coins)
		Diamonds = 0, -- moneda global
		-- Pets[i] = { Id, Name, Equipped, Variant = "Normal"|"Golden"|"Rainbow"|"Void", Enchant = { Id, Level } o nil,
		--            Level, XP (XP acumulada dentro del nivel actual), Locked = true o nil (no se puede borrar) }
		Pets = {},
		Teams = {}, -- ["<slot>"] = { Name, PetIds = {ids} } (ver Config.Teams)
		Items = {}, -- [itemId] = cantidad (ver Config.Items)
		Unlocked = {}, -- [dim] = área más alta desbloqueada; el mundo inicial se agrega al cargar (ver Reconcile)
		Essence = 0, -- no tradeable (ver Config.Meditation)
		-- segundos meditados en el ciclo / segundos de recarga restantes / fracción de Esencia pendiente (multiplicador) /
		-- saltos de recarga comprados que se usan solos en la próxima recarga (EssenceCooldownSkip)
		Meditation = { Progress = 0, Cooldown = 0, Carry = 0, SkipCredits = 0 },
		Upgrades = {}, -- [id] = nivel; las PerDimension: [id] = { [dim] = nivel } (ver Config.Upgrades)
		WorldsPaid = {}, -- mundos cuyo vehículo ya se pagó con Esencia
		Pity = {},
		RebirthsDone = {}, -- [dim] = true: rebirth de ese mundo hecho (ver Config.Rebirths)
		Rank = 0, -- 0 = sin rango (ver Config.Ranks)
		Passes = {}, -- [key] = true: gamepasses del jugador (el servidor lo actualiza al entrar y al comprar)
		Potions = {}, -- inventario: [tipo] = cantidad
		PotionTime = {}, -- [tipo] = segundos que le quedan a la poción activa (solo bajan con el jugador conectado)
		FreePotions = { NextClaim = 0, SkipDay = 0, SkipsUsed = 0 }, -- NextClaim en os.time(); SkipDay = día UTC
		Receipts = {}, -- PurchaseId ya entregados (los últimos Config.ReceiptHistory)
		TotalHatched = 0,
	}
end

-- Rellena lo que falte (también dentro de tablas anidadas) sin pisar lo que ya existe
local function fill(target, defaults)
	for k, v in pairs(defaults) do
		if target[k] == nil then
			target[k] = v
		elseif type(v) == "table" and type(target[k]) == "table" then
			fill(target[k], v)
		end
	end
end

-- Migra partidas guardadas a la forma actual (idempotente: se puede aplicar varias veces).
-- opts (los pasa el servidor desde Config; todos opcionales):
--   StartWorld   mundo que siempre queda desbloqueado (área 1 como mínimo)
--   RebirthOrder lista de mundos por número de rebirth, para migrar el contador viejo data.Rebirths
--   StartLevel   nivel con el que quedan las mascotas que aún no tienen nivel
function DataService.Reconcile(data, opts)
	opts = opts or {}
	data[LOCK_FIELD] = nil -- el lock vive solo en el registro guardado, nunca en los datos de la sesión
	-- sistema viejo de rebirths (un número que daba +50% de poder y monedas): los primeros N rebirths nuevos quedan hechos
	-- (sin reiniciar nada)
	local oldRebirths = data.Rebirths
	data.Rebirths = nil
	fill(data, defaultData())
	if type(oldRebirths) == "number" and oldRebirths > 0 then
		for i, dim in ipairs(opts.RebirthOrder or {}) do
			if i <= oldRebirths then data.RebirthsDone[dim] = true end
		end
	end
	if opts.StartWorld then
		data.Unlocked[opts.StartWorld] = math.max(data.Unlocked[opts.StartWorld] or 0, 1)
	end
	for _, pet in ipairs(data.Pets) do
		if pet.Variant == nil then pet.Variant = "Normal" end -- partidas previas a las variantes
		if type(pet.Enchant) ~= "table" then pet.Enchant = nil end
		if type(pet.Level) ~= "number" then pet.Level = opts.StartLevel or 1 end -- partidas previas a los niveles
		if type(pet.XP) ~= "number" then pet.XP = 0 end
		if pet.Locked ~= true then pet.Locked = nil end
	end
	for key, team in pairs(data.Teams) do
		if type(team) ~= "table" or type(team.PetIds) ~= "table" then
			data.Teams[key] = nil
		elseif type(team.Name) ~= "string" then
			team.Name = "Equipo " .. tostring(key)
		end
	end
	for id, n in pairs(data.Items) do
		if type(n) ~= "number" or n < 1 then data.Items[id] = nil end
	end
	return data
end
DataService.Default = defaultData

---------------------------------------------------------------- lock
-- ¿Esta sesión puede tomar el lock guardado? (función pura, se prueba sola)
-- ctx = { JobId, Now = os.time(), Active = { [Session] = true } (sesiones vivas de este servidor), Waited = segundos esperando }
-- Devuelve true y el motivo: "free" (sin lock), "own" (lock de este servidor de una sesión que ya no existe),
-- "stale" (sin renovar hace LockExpire), "abandoned" (se esperó LockWaitMax). false = otro lo tiene.
function DataService.CanTakeLock(lock, ctx)
	if type(lock) ~= "table" then return true, "free" end
	if lock.JobId == ctx.JobId and not (ctx.Active or {})[lock.Session] then return true, "own" end
	if type(lock.Time) ~= "number" or ctx.Now - lock.Time >= SAVE.LockExpire then return true, "stale" end
	if (ctx.Waited or 0) >= SAVE.LockWaitMax then return true, "abandoned" end
	return false
end

---------------------------------------------------------------- peticiones
local function waitForBudget()
	local waited = 0
	while waited < SAVE.BudgetWait do
		local ok, budget = pcall(function()
			return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
		end)
		if not ok or type(budget) ~= "number" or budget >= 1 then return end
		waited += task.wait(1)
	end
end

-- UpdateAsync con presupuesto y reintentos (espera creciente). El transform puede correr más de una vez: solo debe
-- decidir con lo que recibe. Devuelve true si la petición terminó sin error (aunque el transform haya cancelado).
local function update(key, transform, action)
	local delay = SAVE.RetryBase
	for attempt = 1, SAVE.Retries do
		waitForBudget()
		local ok, err = pcall(function()
			store:UpdateAsync(key, transform)
		end)
		if ok then return true end
		warn(string.format("[PetNexus] Error %s datos (intento %d/%d): %s", action, attempt, SAVE.Retries, tostring(err)))
		if attempt < SAVE.Retries then
			task.wait(delay)
			delay = math.min(delay * 2, SAVE.RetryMax)
		end
	end
	return false
end

local function newLock(sess)
	return { JobId = JOB_ID, Session = sess.Id, Time = os.time() }
end

-- Guarda la sesión. release = true: último guardado, quita el lock.
-- Devuelve true si quedó guardado. "lost" si otro servidor tiene el lock (la sesión ya no guarda más).
local function save(sess, release)
	if not store or sess.Failed or sess.Lost then return false end
	sess.Saving += 1
	local status
	local ok = update(sess.Key, function(old)
		status = nil
		-- un guardado normal que llega después de empezar el Release no escribe (el Release guarda lo último)
		if sess.Releasing and not release then
			status = "closing"
			return nil
		end
		local lock = type(old) == "table" and old[LOCK_FIELD] or nil
		if type(lock) ~= "table" or lock.Session ~= sess.Id or lock.JobId ~= JOB_ID then
			status = "lost"
			return nil
		end
		local record = table.clone(sess.Data)
		record[LOCK_FIELD] = not release and newLock(sess) or nil
		status = "saved"
		return record
	end, "guardando")
	sess.Saving -= 1
	if ok and status == "lost" and not sess.Lost then
		sess.Lost = true
		activeIds[sess.Id] = nil
		warn("[PetNexus] Otro servidor abrió la partida de " .. sess.Player.Name .. ": esta sesión ya no se guarda")
		if DataService.OnSessionLost and not sess.Releasing then task.spawn(DataService.OnSessionLost, sess.Player) end
	end
	return ok and status == "saved"
end

---------------------------------------------------------------- API
-- Carga (y bloquea) la partida. Devuelve los datos, o nil si el jugador salió mientras cargaba.
-- Si no se pudo cargar devuelve datos nuevos que NUNCA se guardan (IsLoaded = false).
function DataService.Load(player, opts)
	local sess = {
		Player = player, Key = "p_" .. player.UserId, Id = HttpService:GenerateGUID(false),
		Failed = false, Lost = false, Releasing = false, Saving = 0,
	}
	loading += 1
	local record, failed, acquired = nil, false, false
	if store then
		local waited = 0
		while player.Parent do
			local status, loaded
			local ok = update(sess.Key, function(old)
				status, loaded = nil, nil
				if old ~= nil and type(old) ~= "table" then
					status = "corrupt"
					return nil
				end
				local lock = old and old[LOCK_FIELD]
				local free, reason = DataService.CanTakeLock(lock, { JobId = JOB_ID, Now = os.time(), Active = activeIds, Waited = waited })
				if not free then
					status = "locked"
					return nil
				end
				local rec = old or {}
				rec[LOCK_FIELD] = newLock(sess)
				status, loaded = reason, old
				return rec
			end, "cargando")
			if not ok or status == "corrupt" then
				failed = true
				break
			end
			if status ~= "locked" then
				acquired = true
				activeIds[sess.Id] = true
				record = loaded
				if status == "stale" or status == "abandoned" then
					warn("[PetNexus] Lock " .. (status == "stale" and "vencido" or "abandonado") .. " de " .. player.Name .. ": se toma la partida")
				end
				break
			end
			waited += task.wait(SAVE.LockRetryDelay)
		end
	end
	loading -= 1
	sess.Failed = failed
	sess.Data = DataService.Reconcile(record or defaultData(), opts)
	if failed then warn("[PetNexus] No se pudieron cargar los datos de " .. player.Name .. ": la sesión no se guardará") end
	if not player.Parent then
		-- salió mientras cargaba: se suelta el lock enseguida (sin cambios que guardar)
		if acquired then
			sess.Releasing = true
			save(sess, true)
			activeIds[sess.Id] = nil
		end
		return nil
	end
	sessions[player] = sess
	return sess.Data
end

function DataService.Get(player)
	local sess = sessions[player]
	return sess and sess.Data
end

-- true si los datos del jugador se cargaron bien y la sesión sigue siendo dueña de la partida
-- (se pueden entregar compras y guardar)
function DataService.IsLoaded(player)
	local sess = sessions[player]
	return sess ~= nil and not sess.Failed and not sess.Lost
end

-- Guarda y devuelve true si quedó guardado
function DataService.Save(player)
	local sess = sessions[player]
	if not sess or sess.Releasing then return false end
	return save(sess, false)
end

-- Último guardado del jugador (al salir): guarda, quita el lock y cierra la sesión. Llamarla dos veces no hace nada.
function DataService.Release(player)
	local sess = sessions[player]
	if not sess or sess.Releasing then return false end
	sess.Releasing = true
	local ok = save(sess, true)
	activeIds[sess.Id] = nil
	if sessions[player] == sess then sessions[player] = nil end
	return ok
end

-- Autoguardado: guarda las sesiones activas (salta las que ya están guardando o cerrando). Renueva los locks.
function DataService.SaveAll()
	for _, sess in pairs(table.clone(sessions)) do
		if not sess.Releasing and sess.Saving == 0 then save(sess, false) end
	end
end

-- BindToClose: libera todas las sesiones en paralelo y espera hasta 'timeout' segundos a que terminen
-- (también las cargas en curso, que sueltan su lock al ver que el jugador ya no está).
function DataService.CloseAll(timeout)
	for player in pairs(table.clone(sessions)) do
		task.spawn(DataService.Release, player)
	end
	local waited = 0
	while (next(sessions) ~= nil or loading > 0) and waited < (timeout or SAVE.CloseTimeout) do
		waited += task.wait(0.5)
	end
	return next(sessions) == nil and loading == 0
end

-- Solo para pruebas (PetNexusDebug): escribe un lock de otro servidor, como si la partida se hubiera abierto en otro lado
function DataService.DebugStealLock(player)
	local sess = sessions[player]
	if not sess or not store then return false end
	return update(sess.Key, function(old)
		if type(old) ~= "table" then return nil end
		old[LOCK_FIELD] = { JobId = "debug-otro-servidor", Session = "debug", Time = os.time() }
		return old
	end, "guardando")
end

return DataService
