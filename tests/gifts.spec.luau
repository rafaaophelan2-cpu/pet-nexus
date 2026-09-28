-- Regalos por tiempo jugado (Gifts.luau): horario, etapas, reclamo y apertura sin suerte
local H = require("./harness")
local M = H.modules()
local Config, Gifts, Inventory = M.Config, M.Gifts, M.Inventory

H.describe("Regalos por tiempo jugado")

H.test("12 regalos en 3 horas, uno cada 15 min; etapas 1-4 / 5-8 / 9-11 / 12", function()
	H.eq(Gifts.Count(), 12)
	H.eq(Gifts.Time(1), 15 * 60)
	H.eq(Gifts.Time(12), 3 * 3600)
	for n = 2, 12 do H.eq(Gifts.Time(n) - Gifts.Time(n - 1), 900) end
	local expected = { "GiftSmall", "GiftSmall", "GiftSmall", "GiftSmall", "GiftNormal", "GiftNormal", "GiftNormal", "GiftNormal",
		"GiftBig", "GiftBig", "GiftBig", "GiftGiant" }
	for n = 1, 12 do H.eq(Gifts.ItemFor(n), expected[n], "regalo " .. n) end
	H.eq(Gifts.ItemFor(13), nil)
	H.eq(Gifts.Time(0), nil)
	for n = 1, 12 do H.ok(Gifts.TableOf(Gifts.ItemFor(n)), "tabla del regalo " .. n) end
end)

H.test("reclamar: solo cuando se cumplió el tiempo de la sesión, y una vez", function()
	local d = H.data(M)
	local s = Gifts.NewSession(1000)
	local ok, err, left = Gifts.Claim(s, d, 1, 1000 + 899)
	H.eq(ok, false); H.eq(err, "wait"); H.eq(left, 1)
	local ok2, item = Gifts.Claim(s, d, 1, 1000 + 900)
	H.eq(ok2, true); H.eq(item, "GiftSmall")
	H.eq(Inventory.ItemCount(d, "GiftSmall"), 1, "queda como item")
	H.eq(select(2, Gifts.Claim(s, d, 1, 5000)), "claimed")
	H.eq(select(2, Gifts.Claim(s, d, 13, 99999)), "gift")
	H.eq(select(2, Gifts.Claim(s, d, 1.5, 99999)), "gift")
	H.eq(select(2, Gifts.Claim(s, d, "1", 99999)), "gift")
	-- el 12 (Gigante) pide 3 h seguidas; no hace falta reclamar en orden
	H.eq(select(2, Gifts.Claim(s, d, 12, 1000 + 3 * 3600 - 1)), "wait")
	H.eq(Gifts.Claim(s, d, 12, 1000 + 3 * 3600), true)
	H.eq(Inventory.ItemCount(d, "GiftGiant"), 1)
end)

H.test("estado para la UI; una sesión nueva empieza de cero", function()
	local d = H.data(M)
	local s = Gifts.NewSession(0)
	Gifts.Claim(s, d, 1, 1000)
	local st = Gifts.Status(s, 1850)
	H.eq(st.Seconds, 1850)
	H.eq(st.Gifts[1].Claimed, true); H.eq(st.Gifts[1].Ready, false)
	H.eq(st.Gifts[2].Ready, true)
	H.eq(st.Gifts[3].Ready, false); H.eq(st.Gifts[3].Remaining, 850)
	H.eq(Gifts.ReadyCount(s, 1850), 1)
	H.eq(Gifts.ClaimedText(s), "1")
	local parsed = Gifts.ParseClaimed("1,5,12")
	H.ok(parsed[1] and parsed[5] and parsed[12])
	-- el cliente llega al mismo estado con los atributos del jugador
	local fromAttrs = Gifts.StatusFrom(1850, Gifts.ParseClaimed(Gifts.ClaimedText(s)))
	H.eq(fromAttrs.Gifts[2].Ready, true)
	H.eq(fromAttrs.Gifts[1].Claimed, true)
	-- al volver a entrar hay sesión nueva: tiempo y reclamados en cero
	local nueva = Gifts.NewSession(5000)
	H.eq(Gifts.Elapsed(nueva, 5000), 0)
	H.eq(Gifts.ReadyCount(nueva, 5000), 0)
	H.eq(Gifts.ClaimedText(nueva), "")
	nueva.Offset = 900 -- lo que hace el debug "playtime"
	H.eq(Gifts.ReadyCount(nueva, 5000), 1)
end)

H.describe("Apertura de regalos")

H.test("abrir consume el regalo y entrega exactamente lo que informa", function()
	local d = H.data(M)
	d.Unlocked.Nexus = 5
	Inventory.AddItem(d, "GiftGiant", 1)
	local ok, rewards = Gifts.Open(d, "GiftGiant", H.rng(7), { Dim = "Nexus" })
	H.eq(ok, true)
	H.eq(#rewards, Config.GiftTables.Giant.Rolls)
	H.eq(Inventory.ItemCount(d, "GiftGiant"), 0)
	local coins, diamonds, potions = 0, 0, 0
	for _, r in ipairs(rewards) do
		if r.Kind == "Coins" then coins += r.Amount; H.eq(r.Dim, "Nexus") end
		if r.Kind == "Diamonds" then diamonds += r.Amount end
		if r.Kind == "Potion" then potions += r.Amount end
	end
	H.eq(d.Currency.Nexus or 0, coins)
	H.eq(d.Diamonds, diamonds)
	local have = 0
	for _, n in pairs(d.Potions) do have += n end
	H.eq(have, potions)
	H.eq(select(2, Gifts.Open(d, "GiftGiant", H.rng(7), { Dim = "Nexus" })), "none")
	H.eq(select(2, Gifts.Open(d, "NoExiste", H.rng(7), {})), "item")
	H.eq(select(2, Gifts.Open(d, 5, H.rng(7), {})), "item")
end)

H.test("sin suerte: gamepasses, mejoras, encantamientos, pociones y rebirth no cambian la tirada ni las cantidades", function()
	local base = H.data(M)
	local boosted = H.data(M, {
		{ Name = "Owl", Enchant = { Id = "Luck", Level = 5 } }, { Name = "Fox", Enchant = { Id = "Coins", Level = 5 } },
		{ Name = "Bunny", Enchant = { Id = "Diamonds", Level = 5 } },
	})
	boosted.Passes = { GoodLuck = true, InsaneLuck = true, DoubleCoins = true, DoubleDiamonds = true, VIP = true }
	boosted.Upgrades = { Luck = 4, Coins = { Nexus = 4 }, Diamonds = 4 }
	boosted.PotionTime = { Luck = 999, Coins = 999, Diamonds = 999 }
	boosted.RebirthsDone = { Greenwood = true }
	H.ok(M.Stats.Get(boosted, "Luck") > 5 and M.Stats.Get(boosted, "Coins", "Nexus") > 5, "el jugador sí tiene suerte y multiplicadores")
	Inventory.AddItem(base, "GiftBig", 50)
	Inventory.AddItem(boosted, "GiftBig", 50)
	local rngA, rngB = H.rng(123), H.rng(123)
	for _ = 1, 50 do
		local _, ra = Gifts.Open(base, "GiftBig", rngA, { Dim = "Nexus" })
		local _, rb = Gifts.Open(boosted, "GiftBig", rngB, { Dim = "Nexus" })
		for i = 1, #ra do
			H.eq(ra[i].Kind, rb[i].Kind)
			H.eq(ra[i].Amount, rb[i].Amount)
			H.eq(ra[i].Potion, rb[i].Potion)
		end
	end
	H.eq(base.Diamonds, boosted.Diamonds, "diamantes exactos")
	H.eq(base.Currency.Nexus or 0, boosted.Currency.Nexus or 0)
end)

H.test("la frecuencia de cada premio coincide con su probabilidad", function()
	local d = H.data(M)
	local tbl = Config.GiftTables.Small
	local counts = {}
	local rng = H.rng(99)
	local N = 20000
	for _ = 1, N do
		local r = Gifts.Roll(rng, tbl)[1]
		counts[r] = (counts[r] or 0) + 1
	end
	for _, entry in ipairs(Gifts.Chances("GiftSmall").Rewards) do
		local def
		for _, r in ipairs(tbl.Rewards) do
			if r.Kind == entry.Kind and r.Potion == entry.Potion then def = r end
		end
		H.near((counts[def] or 0) / N, entry.Chance, 0.015, entry.Kind .. tostring(entry.Potion))
	end
	H.ok(d)
end)

H.test("probabilidades legibles por el cliente: suman 1 y las monedas se escalan con el progreso", function()
	for id, def in pairs(Config.Items) do
		if def.Type == "Gift" then
			local c = Gifts.Chances(id)
			local total = 0
			for _, r in ipairs(c.Rewards) do
				total += r.Chance
				H.ok(r.Amount > 0, id)
			end
			H.near(total, 1, 1e-9, id)
			H.ok(c.Rolls >= 1)
			for _, r in ipairs(Config.GiftTables[def.Gift].Rewards) do
				H.ok(({ Coins = true, Diamonds = true, Potion = true, Item = true })[r.Kind], id)
				if r.Kind == "Potion" then H.ok(Config.Potions.Types[r.Potion], id .. ": poción") end
			end
		end
	end
	H.eq(Gifts.Chances("NoExiste"), nil)
	H.near(Gifts.Chances("GiftSmall").Rewards[1].Chance, 0.55, 1e-9)
	local d = H.data(M)
	d.Unlocked.Nexus = 10
	local scaled = Gifts.Chances("GiftSmall", d, "Nexus")
	H.eq(scaled.Rewards[1].Amount, math.floor(250 * Config.ZoneMultiplier("Nexus", 10)))
	H.eq(scaled.Rewards[1].Base, 250)
	H.eq(scaled.Rewards[1].Dim, "Nexus")
	H.eq(scaled.Rewards[2].Amount, 5, "los diamantes no se escalan")
	H.eq(Gifts.Chances("GiftSmall", d, "Greenwood").Rewards[1].Dim, "Nexus", "un mundo sin desbloquear usa el más avanzado")
end)

return H
