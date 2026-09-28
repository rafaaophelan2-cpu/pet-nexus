# Pet Nexus

Juego de Roblox estilo Pet Simulator. Los scripts se sincronizan con Roblox Studio usando Rojo.

Ver WORKFLOW.md antes de editar.

## Tests
Las reglas de economía son funciones puras (`src/shared/Stats.luau`, `src/shared/Economy.luau`, migración en
`DataService.Reconcile`) y se prueban sin Studio con [Lune](https://github.com/lune-org/lune):

    aftman install
    lune run tests/run
