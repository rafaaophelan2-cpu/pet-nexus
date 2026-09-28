-- Corre todos los tests: lune run tests/run   (desde la raíz del repo)
local process = require("@lune/process")
local H = require("./harness")

for _, spec in ipairs({ "./stats.spec", "./enchants.spec", "./economy.spec", "./migration.spec", "./layout.spec", "./progression.spec", "./purchases.spec", "./server.spec" }) do
	require(spec)
end

print(string.format("%d tests OK, %d fallidos", H.passed, H.failed))
process.exit(H.failed == 0 and 0 or 1)
