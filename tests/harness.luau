-- Utilidades de tests (Lune). Carga los módulos reales de src/ con un entorno falso (script/require/game)
-- para que el código del juego no necesite cambios. Correr desde la raíz del repo: lune run tests/run
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local H = {}

local function load(path, env)
	local fn = luau.load(fs.readFile(path), { debugName = path, environment = env })
	return fn()
end

-- Copia nueva de los módulos en cada llamada (un test puede modificar Config sin afectar a otros)
function H.modules()
	local mods = {}
	local env = {
		script = { Parent = { Config = "Config", Stats = "Stats", Economy = "Economy" } },
		require = function(key)
			return assert(mods[key], "módulo no cargado: " .. tostring(key))
		end,
		Color3 = roblox.Color3,
		Vector3 = roblox.Vector3,
	}
	mods.Config = load("src/shared/Config.luau", env)
	mods.Stats = load("src/shared/Stats.luau", env)
	mods.Economy = load("src/shared/Economy.luau", env)
	mods.DataService = load("src/server/DataService.luau", {
		game = { GetService = function() return { GetDataStore = function() error("sin DataStore en tests") end } end },
		warn = function() end,
	})
	return mods
end

-- Generador con seed (Park-Miller). Misma interfaz que Random: NextNumber() en [0, 1) o NextNumber(min, max).
function H.rng(seed)
	local state = seed % 2147483647
	if state <= 0 then state += 2147483646 end
	local r = {}
	function r:NextNumber(min, max)
		state = (state * 16807) % 2147483647
		local x = (state - 1) / 2147483646
		if min then return min + x * (max - min) end
		return x
	end
	return r
end

-- Generador que devuelve una secuencia fija (se repite)
function H.seq(values)
	local i = 0
	return {
		NextNumber = function()
			i = i % #values + 1
			return values[i]
		end,
	}
end

-- Datos de jugador nuevos (los default de DataService) con mascotas opcionales
function H.data(mods, pets)
	local d = mods.DataService.Default()
	for _, p in ipairs(pets or {}) do
		table.insert(d.Pets, {
			Id = p.Id or ("pet" .. (#d.Pets + 1)), Name = p.Name, Equipped = p.Equipped ~= false,
			Variant = p.Variant or "Normal", Enchant = p.Enchant,
		})
	end
	return d
end

---------------------------------------------------------------- aserciones
H.passed, H.failed = 0, 0
local current = "?"

function H.describe(name) current = name end

function H.test(name, fn)
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		H.passed += 1
	else
		H.failed += 1
		print(string.format("FALLA  %s > %s\n%s", current, name, tostring(err)))
	end
end

local function fmt(v)
	return type(v) == "string" and string.format("%q", v) or tostring(v)
end

function H.eq(actual, expected, msg)
	if actual ~= expected then
		error(string.format("%sesperado %s, obtenido %s", msg and (msg .. ": ") or "", fmt(expected), fmt(actual)), 2)
	end
end

function H.near(actual, expected, eps, msg)
	if type(actual) ~= "number" or math.abs(actual - expected) > (eps or 1e-9) then
		error(string.format("%sesperado ~%s (±%s), obtenido %s", msg and (msg .. ": ") or "", fmt(expected), fmt(eps or 1e-9), fmt(actual)), 2)
	end
end

function H.ok(v, msg)
	if not v then error(msg or "se esperaba verdadero", 2) end
end

return H
