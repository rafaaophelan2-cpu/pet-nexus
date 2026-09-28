-- Guardado a prueba de fallos (DataService): lock de sesión, lock abandonado, reintentos, presupuesto y fallo al cargar.
-- Un DataStore falso en memoria compartido por dos "servidores" (dos copias de DataService con distinto JobId) y un
-- reloj simulado: task.wait avanza el reloj al instante y corre los "hooks" (lo que hace otro servidor mientras tanto).
local H = require("./harness")
local serde = require("@lune/serde")
local M = H.modules()
local SAVE = M.Config.Save
local OPTS = { StartWorld = "Nexus" }

local T0 = 1790000000
local clock = { now = 0, hooks = {} }

local fakeTask = {
	wait = function(t)
		t = t or 0.03
		clock.now += t
		local hooks = clock.hooks
		clock.hooks = {}
		for _, fn in ipairs(hooks) do fn() end
		return t
	end,
	spawn = function(fn, ...) fn(...) end,
}
local fakeOs = setmetatable({
	time = function() return T0 + math.floor(clock.now) end,
	clock = function() return clock.now end,
}, { __index = os })

-- DataStore en memoria: failNext = cuántas peticiones fallan; failAll = todas; budget = número o función;
-- before = función que corre al empezar la próxima petición (simula algo que pasa mientras la petición viaja)
local function newStore()
	local store = { saved = {}, failNext = 0, failAll = false, writes = 0, calls = 0, budget = 100 }
	local function copy(v) return v ~= nil and serde.decode("json", serde.encode("json", v)) or nil end
	function store:UpdateAsync(key, fn)
		self.calls += 1
		if self.before then
			local f = self.before
			self.before = nil
			f()
		end
		if self.failAll then error("DataStore caído") end
		if self.failNext > 0 then
			self.failNext -= 1
			error("502: error simulado")
		end
		local result = fn(copy(self.saved[key]))
		if result == nil then return nil end
		self.saved[key] = copy(result)
		self.writes += 1
		return copy(result)
	end
	return store
end

local function server(jobId, store, warns)
	return H.loadDataService(M, {
		DataStoreService = {
			GetDataStore = function() return store end,
			GetRequestBudgetForRequestType = function()
				return type(store.budget) == "function" and store.budget() or store.budget
			end,
		},
	}, {
		JobId = jobId, task = fakeTask, os = fakeOs,
		warn = function(...) if warns then table.insert(warns, table.concat({ ... }, " ")) end end,
	})
end

local function newPlayer(userId)
	return { UserId = userId, Name = "Jugador" .. userId, Parent = "Players" }
end

local function now() return T0 + math.floor(clock.now) end

local function hasWarning(warns, text)
	for _, w in ipairs(warns) do
		if string.find(w, text, 1, true) then return true end
	end
	return false
end

H.describe("Guardado: lock de sesión")

H.test("CanTakeLock: libre, propio huérfano, vencido, abandonado u ocupado", function()
	local A = server("A", newStore())
	local ctx = { JobId = "A", Now = 1000, Active = { viva = true }, Waited = 0 }
	H.eq(select(2, A.CanTakeLock(nil, ctx)), "free")
	H.eq(A.CanTakeLock({ JobId = "B", Session = "x", Time = 1000 }, ctx), false)
	H.eq(A.CanTakeLock({ JobId = "B", Session = "x", Time = 1000 - SAVE.LockExpire + 1 }, ctx), false)
	H.eq(select(2, A.CanTakeLock({ JobId = "B", Session = "x", Time = 1000 - SAVE.LockExpire }, ctx)), "stale")
	H.eq(select(2, A.CanTakeLock({ JobId = "A", Session = "muerta", Time = 1000 }, ctx)), "own")
	H.eq(A.CanTakeLock({ JobId = "A", Session = "viva", Time = 1000 }, ctx), false, "sesión viva de este mismo servidor")
	H.eq(select(2, A.CanTakeLock({ JobId = "B", Session = "x" }, ctx)), "stale", "lock sin hora = roto")
	ctx.Waited = SAVE.LockWaitMax
	H.eq(select(2, A.CanTakeLock({ JobId = "B", Session = "x", Time = 1000 }, ctx)), "abandoned")
end)

H.test("valores de Config coherentes", function()
	H.ok(SAVE.LockExpire >= 3 * SAVE.AutoSaveInterval, "un servidor vivo renueva el lock varias veces antes de que venza")
	local retries, delay = 0, SAVE.RetryBase
	for _ = 1, SAVE.Retries - 1 do
		retries += delay
		delay = math.min(delay * 2, SAVE.RetryMax)
	end
	H.ok(SAVE.LockWaitMax > retries, "el último guardado de otro servidor (con todos sus reintentos) termina antes del abandono")
	H.ok(SAVE.CloseTimeout < 30, "Roblox corta BindToClose a los 30 s")
end)

H.test("jugador nuevo: carga, toma el lock, guarda y al salir lo suelta", function()
	local store = newStore()
	local A = server("A", store)
	local p = newPlayer(1)
	local data = A.Load(p, OPTS)
	H.ok(data)
	H.eq(A.IsLoaded(p), true)
	local lock = store.saved.p_1.SessionLock
	H.eq(lock.JobId, "A")
	H.ok(lock.Session and lock.Time == now())
	H.eq(data.SessionLock, nil, "el lock no está en los datos de la sesión")
	data.Diamonds = 55
	H.eq(A.Save(p), true)
	H.eq(store.saved.p_1.Diamonds, 55)
	H.eq(store.saved.p_1.SessionLock.JobId, "A")
	H.eq(A.Release(p), true)
	H.eq(store.saved.p_1.SessionLock, nil, "lock liberado")
	H.eq(store.saved.p_1.Diamonds, 55)
	H.eq(A.Get(p), nil)
	H.eq(A.Release(p), false, "dos veces no hace nada")
	H.eq(A.Save(p), false)
end)

H.test("compatible con partidas guardadas antes del lock (store PetNexus_v2)", function()
	local store = newStore()
	local A = server("A", store)
	store.saved.p_2 = {
		Currency = { Nexus = 500 }, Diamonds = 9, Unlocked = { Nexus = 3 }, Receipts = { "r1" },
		Pets = { { Id = "a", Name = "Owl", Equipped = true, Variant = "Golden" } },
	}
	local p = newPlayer(2)
	local d = A.Load(p, OPTS)
	H.eq(d.Currency.Nexus, 500)
	H.eq(d.Pets[1].Variant, "Golden")
	H.eq(d.Receipts[1], "r1")
	H.eq(d.Unlocked.Nexus, 3)
	H.eq(store.saved.p_2.Currency.Nexus, 500, "tomar el lock no cambia los datos guardados")
	H.eq(store.saved.p_2.SessionLock.JobId, "A")
	A.Release(p)
	H.eq(store.saved.p_2.SessionLock, nil)
	H.eq(store.saved.p_2.Diamonds, 9)
end)

H.test("otro servidor no carga mientras la partida está abierta: espera y carga lo último guardado", function()
	local store = newStore()
	local A, B = server("A", store), server("B", store)
	local pA = newPlayer(3)
	local dA = A.Load(pA, OPTS)
	dA.Diamonds = 77
	local pB = newPlayer(3) -- el mismo usuario entra a B antes de que A termine de guardar
	local t0 = clock.now
	clock.hooks = { function() A.Release(pA) end } -- mientras B espera, A guarda y suelta
	local dB = B.Load(pB, OPTS)
	H.eq(dB.Diamonds, 77, "B cargó lo que A guardó al salir")
	H.eq(store.saved.p_3.SessionLock.JobId, "B")
	local waited = clock.now - t0
	H.ok(waited >= SAVE.LockRetryDelay and waited < SAVE.LockWaitMax, "esperó un reintento, no hasta el abandono: " .. waited)
	B.Release(pB)
end)

H.test("en el mismo servidor, una sesión viva del mismo jugador también se espera", function()
	local store = newStore()
	local A = server("A", store)
	local old = newPlayer(4)
	A.Load(old, OPTS).Diamonds = 8
	local again = newPlayer(4) -- volvió a entrar al mismo servidor antes de que termine el Release anterior
	local t0 = clock.now
	clock.hooks = { function() A.Release(old) end }
	H.eq(A.Load(again, OPTS).Diamonds, 8)
	H.ok(clock.now - t0 >= SAVE.LockRetryDelay)
	A.Release(again)
end)

H.test("lock abandonado: tras LockWaitMax se toma y el servidor viejo ya no guarda (no duplica)", function()
	local store = newStore()
	local warns = {}
	local A, B = server("A", store), server("B", store, warns)
	local lost = {}
	A.OnSessionLost = function(p) table.insert(lost, p) end
	local pA = newPlayer(5)
	local dA = A.Load(pA, OPTS)
	table.insert(dA.Pets, { Id = "x", Name = "Owl", Equipped = true, Variant = "Normal", Level = 1, XP = 0 })
	H.eq(A.Save(pA), true)
	local pB = newPlayer(5)
	local t0 = clock.now
	local dB = B.Load(pB, OPTS)
	H.ok(clock.now - t0 >= SAVE.LockWaitMax, "esperó LockWaitMax")
	H.ok(hasWarning(warns, "abandonado"))
	H.eq(#dB.Pets, 1)
	H.eq(store.saved.p_5.SessionLock.JobId, "B")
	-- A sigue con la sesión en memoria (servidor colgado) e intenta guardar una mascota más: no escribe
	table.insert(dA.Pets, { Id = "dup", Name = "Owl", Equipped = false, Variant = "Normal", Level = 1, XP = 0 })
	H.eq(A.Save(pA), false)
	H.eq(#store.saved.p_5.Pets, 1, "no duplicó")
	H.eq(A.IsLoaded(pA), false, "la sesión de A quedó perdida")
	H.eq(#lost, 1)
	H.eq(lost[1], pA)
	H.eq(A.Save(pA), false, "ni lo vuelve a intentar")
	H.eq(A.Release(pA), false)
	H.eq(store.saved.p_5.SessionLock.JobId, "B", "el Release de A no suelta el lock de B")
	dB.Diamonds = 5
	H.eq(B.Save(pB), true)
	H.eq(#lost, 1, "perder la sesión avisa una sola vez")
end)

H.test("lock vencido (servidor caído) o huérfano de este servidor: se toma sin esperar", function()
	local store = newStore()
	local A, B = server("A", store), server("B", store)
	store.saved.p_6 = { Diamonds = 3, SessionLock = { JobId = "Z", Session = "s", Time = now() - SAVE.LockExpire } }
	local t0 = clock.now
	H.eq(B.Load(newPlayer(6), OPTS).Diamonds, 3)
	H.eq(clock.now, t0, "sin esperas")
	store.saved.p_7 = { Diamonds = 4, SessionLock = { JobId = "A", Session = "vieja", Time = now() } }
	H.eq(A.Load(newPlayer(7), OPTS).Diamonds, 4)
	H.eq(clock.now, t0, "sin esperas")
end)

H.test("el autoguardado renueva el lock", function()
	local store = newStore()
	local A = server("A", store)
	local p = newPlayer(8)
	A.Load(p, OPTS)
	local t = store.saved.p_8.SessionLock.Time
	fakeTask.wait(SAVE.AutoSaveInterval)
	A.SaveAll()
	H.eq(store.saved.p_8.SessionLock.Time, t + SAVE.AutoSaveInterval)
	A.Release(p)
end)

H.test("un guardado que llega después de empezar el Release no vuelve a poner el lock", function()
	local store = newStore()
	local A = server("A", store)
	local p = newPlayer(9)
	local d = A.Load(p, OPTS)
	d.Diamonds = 21
	-- el autoguardado sale, pero antes de que el DataStore lo procese el jugador se va
	store.before = function() A.Release(p) end
	H.eq(A.Save(p), false)
	H.eq(store.saved.p_9.SessionLock, nil)
	H.eq(store.saved.p_9.Diamonds, 21, "el Release guardó lo último")
end)

H.test("si el jugador se va mientras espera el lock, no toma nada; si se va al cargar, lo suelta", function()
	local store = newStore()
	local A, B = server("A", store), server("B", store)
	local pA = newPlayer(10)
	A.Load(pA, OPTS)
	local pB = newPlayer(10)
	clock.hooks = { function() pB.Parent = nil end }
	H.eq(B.Load(pB, OPTS), nil)
	H.eq(store.saved.p_10.SessionLock.JobId, "A", "no tocó el lock de A")
	H.eq(B.Get(pB), nil)
	A.Release(pA)
	local p = newPlayer(11)
	store.before = function() p.Parent = nil end
	H.eq(A.Load(p, OPTS), nil)
	H.eq(store.saved.p_11.SessionLock, nil, "soltó el lock enseguida")
	H.eq(A.Get(p), nil)
end)

H.describe("Guardado: errores y límites")

H.test("reintentos con espera creciente ante errores", function()
	local store = newStore()
	local warns = {}
	local A = server("A", store, warns)
	local p = newPlayer(12)
	store.failNext = 3
	local t0 = clock.now
	A.Load(p, OPTS)
	H.eq(A.IsLoaded(p), true)
	H.eq(clock.now - t0, 1 + 2 + 4, "espera 1, 2 y 4 s")
	H.ok(hasWarning(warns, "Error cargando datos (intento 1/"))
	store.failNext = 2
	t0 = clock.now
	A.Get(p).Diamonds = 6
	H.eq(A.Save(p), true)
	H.eq(clock.now - t0, 1 + 2)
	H.eq(store.saved.p_12.Diamonds, 6)
	H.ok(hasWarning(warns, "Error guardando datos"))
	-- si fallan todos los intentos no se guarda, pero la sesión sigue (el próximo guardado reintenta)
	store.failNext = SAVE.Retries
	local calls = store.calls
	H.eq(A.Save(p), false)
	H.eq(store.calls - calls, SAVE.Retries)
	H.eq(A.IsLoaded(p), true)
	H.eq(A.Save(p), true)
	A.Release(p)
end)

H.test("si la carga falla, la sesión nunca se guarda (no pisa los datos reales)", function()
	local store = newStore()
	local warns = {}
	local A = server("A", store, warns)
	store.saved.p_13 = { Diamonds = 999 }
	store.failAll = true
	local p = newPlayer(13)
	local d = A.Load(p, OPTS)
	H.ok(d, "se juega con datos nuevos")
	H.eq(A.IsLoaded(p), false)
	H.eq(d.Diamonds, 0)
	H.ok(hasWarning(warns, "No se pudieron cargar"))
	store.failAll = false
	d.Diamonds = 1
	local writes = store.writes
	H.eq(A.Save(p), false)
	A.SaveAll()
	H.eq(A.Release(p), false)
	H.eq(store.writes, writes, "ninguna escritura")
	H.eq(store.saved.p_13.Diamonds, 999)
	H.eq(store.saved.p_13.SessionLock, nil)
end)

H.test("un registro corrupto no se pisa", function()
	local store = newStore()
	local A = server("A", store)
	store.saved.p_14 = "basura"
	local p = newPlayer(14)
	A.Load(p, OPTS)
	H.eq(A.IsLoaded(p), false)
	A.Release(p)
	H.eq(store.saved.p_14, "basura")
end)

H.test("respeta el presupuesto de peticiones del DataStore", function()
	local store = newStore()
	local A = server("A", store)
	local p = newPlayer(15)
	A.Load(p, OPTS)
	local t0 = clock.now
	store.budget = function() return clock.now - t0 >= 3 and 10 or 0 end
	H.eq(A.Save(p), true)
	H.eq(clock.now - t0, 3, "esperó a que hubiera presupuesto")
	store.budget = 0 -- nunca se recupera: espera BudgetWait y lo intenta igual
	t0 = clock.now
	H.eq(A.Save(p), true)
	H.eq(clock.now - t0, SAVE.BudgetWait)
	store.budget = 100
	A.Release(p)
end)

H.test("CloseAll (BindToClose) guarda y suelta a todos", function()
	local store = newStore()
	local A = server("A", store)
	local players = { newPlayer(21), newPlayer(22), newPlayer(23) }
	for i, p in ipairs(players) do A.Load(p, OPTS).Diamonds = i end
	H.eq(A.CloseAll(5), true)
	for i, p in ipairs(players) do
		local rec = store.saved["p_" .. p.UserId]
		H.eq(rec.Diamonds, i)
		H.eq(rec.SessionLock, nil)
		H.eq(A.Get(p), nil)
	end
end)

return H
