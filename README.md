# Pet Nexus

Juego de Roblox estilo Pet Simulator. Los scripts se sincronizan con Roblox Studio usando Rojo.

Ver WORKFLOW.md antes de editar.

## Tests
Las reglas son funciones puras (`src/shared/Stats.luau`, `Economy.luau`, `Progression.luau`, `Purchases.luau`, el
trazado en `Config.luau` y la migración en `DataService.Reconcile`) y se prueban sin Studio con
[Lune](https://github.com/lune-org/lune). Además `tests/server.spec.luau` corre el script real del servidor sobre una
simulación mínima de Roblox (`tests/roblox_mock.luau`): remotes, bucles, rebirth, compras y anticheat de punta a punta.
No reemplaza un playtest en Studio.

    aftman install
    lune run tests/run
