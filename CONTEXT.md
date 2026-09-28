# Contexto para sesiones nuevas (Claude)

Repo `rafaaophelan2-cpu/pet-nexus`: juego de Roblox estilo Pet Simulator, en Luau y sincronizado con Rojo
(solo de archivos a Studio). Antes de empezar, lee WORKFLOW.md, README.md y los archivos de `src/` que vayas a tocar.

## Reglas
- No hay Studio: todo tiene que ser lógica verificable con tests. No inventes instancias del mapa.
- Toda la economía y los teleports los decide el servidor (`teleport()`).
- Comentarios en español neutro; nada de emojis en los textos del juego.
- Nunca trabajes en main: rama nueva, commits claros y push.
- Todo valor que el usuario no fije va en Config marcado como PROVISIONAL.
- No toques WorldBuilder, el mapa, los modelos ni la UI visual salvo que el usuario lo pida.
- El usuario prefiere respuestas directas, sin relleno.

## Estado de git
- `main`: incluye la Esencia AFK y el "cerebro" (stats, variantes, encantamientos, mejoras, diamantes).
- `feature/progresion-v2`: añade mundos, trazado con curva, rebirth, rango, XP de mascotas, gamepasses,
  Developer Products y pociones. Tiene push hecho, pero no hay PR ni está fusionada.

## Arquitectura
- `src/shared/Config.luau`: todo lo configurable, más la API de trazado.
- `Stats`, `Economy`, `Progression` y `Purchases`: funciones puras sobre la tabla `data` del jugador.
  Devuelven `(false, código, extra)` o `(true, ...)` y no tocan instancias.
- `src/server/DataService.luau`: DataStore `PetNexus_v2`.
  - `Reconcile(data, opts)` migra los datos guardados sin romper nada.
  - `Save` devuelve si guardó; si la carga falló, esa sesión no se guarda.
- `src/server/PetNexusServer.server.luau`: remotes, bucles, anticheat y MarketplaceService.
  Los comandos de debug están en `ServerStorage.PetNexusDebug` (solo en Studio).
- `src/client/PetNexusClient.client.luau`: HUD e interfaz.
- `src/build/WorldBuilder.luau`: construye el mapa desde Studio.
- Los remotes nuevos los crea el servidor si no existen en `PetNexus.Remotes` (función `remote(name)`).
- Cada módulo nuevo hay que añadirlo a `default.project.json`.

## Sistemas
- **Meditación**:
  - Zonas con tag `MeditationZone`.
  - Da 1 Esencia por segundo hasta 900 (15 min) y luego 30 min de recarga que solo corre con el jugador conectado.
  - La Esencia no se puede tradear.
- **Stats**:
  - `final = Base × (1+mejora) × (1+encantamientos de las mascotas equipadas) × (1+rebirths) × (1+rango) × (1+gamepasses) × (1+pociones)`.
  - Dentro de una misma fuente los bonus se suman; entre fuentes se multiplican.
  - `MaxEquipped = 3 + mejora PetsEquipped + rebirths + gamepasses`.
- **Mascotas**:
  - Variantes Normal/Golden/Rainbow/Void (×1 / ×1,5 / ×2 / ×3).
  - Encantamientos por tiers; auto enchant con la mejora AutoEnchant.
  - Nivel 1 a 50, +1% por nivel; la XP sale de cada rompible.
- **Mejoras**:
  - Coins es por mundo.
  - Las globales se venden en `SpawnWorld()`.
  - Los diamantes son globales.
- **Mundos**:
  - Greenwood: Order 1, `AreasBuilt 0`, el mapa aún no existe, Origin en x=3000.
  - Nexus: Order 2, `AreasBuilt 2`, `EconomyOrder 1` (PROVISIONAL, para que sus precios no cambien).
  - `StartWorld = "Greenwood"`, pero `SpawnWorld()` devuelve Nexus mientras Greenwood no tenga mapa.
- **Trazado**:
  - Áreas 1-10 en línea recta; las de Nexus están en posición idéntica a la original.
  - El área 10 es una esquina grande donde el camino gira a la derecha; las áreas 11-20 van giradas.
  - API: `AreaCFrame`, `AreaRect`, `PointInArea`, `ZoneFromPosition`, `GateCFrame`, `ZoneEntryCFrame`, `LobbySpawnCFrame`.
- **Rebirth**:
  - Uno por mundo y en orden. Exige el área 10 de ese mundo y estar cerca de una Part con tag `RebirthStatue` y atributo `Dimension`.
  - Reinicia la moneda y las áreas de ese mundo, salvo con el gamepass Rebirth+.
  - Durante la ascensión el anticheat tiene una ventana de gracia.
- **Rango**: 10 niveles pagados con diamantes, más un Developer Product por nivel para saltarlo.
- **Monetización**:
  - Los gamepasses y los 39 Developer Products tienen `Id = 0` (desactivados).
  - Los IDs reales van en `Config.GamePasses.<clave>.Id` / `Config.Products.<clave>.Id`.
  - `ProcessReceipt` no entrega dos veces (guarda el PurchaseId) y solo confirma tras guardar.
- **Pociones**:
  - El tiempo se acumula y solo corre con el jugador conectado.
  - Pociones gratis: Part con tag `PotionShrine`, cooldown de 3 h en tiempo real y como máximo 3 saltos pagados por día.
- **Zona VIP**:
  - `VipBarrier`: el cliente les quita la colisión a los dueños de VIP.
  - `VipZone`: el servidor saca de ahí a los que no son VIP.

## Tests
- `lune run tests/run`: 95 tests.
- `tests/roblox_mock.luau` simula Roblox para correr el servidor real (`tests/server.spec.luau`).
- En la nube GitHub Releases está bloqueado: instala Lune con `cargo install lune --locked`.
  Para lint, `cargo install selene --locked`.
- En los tests de servidor, mueve jugadores con `Mock.debug("teleport", ...)`: un salto directo lo revierte el anticheat.

## Pendiente
- En Studio (lo hace el usuario):
  - Colocar las Parts `RebirthStatue`, `PotionShrine`, `VipBarrier` y `VipZone`.
  - Construir el mapa de Greenwood con las puertas en `Config.GateCFrame`.
  - Poner los IDs reales de gamepasses y productos.
- Subir `Nexus.EconomyOrder` a 2 cuando se rebalanceen los huevos y mascotas de Nexus.
- Los beneficios del Rebirth 2 no están definidos.
- Greenwood usa los modelos de AngelCoin.
- Mantén este archivo al día cuando cambie algo importante.
