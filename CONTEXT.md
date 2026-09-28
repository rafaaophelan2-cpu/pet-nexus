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
- `feature/inventario-guardado` (sale de `feature/progresion-v2`): guardado con bloqueo de sesión, inventario de
  mascotas con límite, teams, items, regalos por tiempo jugado y salto de la recarga de Esencia. Push hecho, sin PR.

## Arquitectura
- `src/shared/Config.luau`: todo lo configurable, más la API de trazado.
- `Stats`, `Economy`, `Progression`, `Purchases`, `Inventory` y `Gifts`: funciones puras sobre la tabla `data` del jugador.
  Devuelven `(false, código, extra)` o `(true, ...)` y no tocan instancias. El cliente también puede usarlas
  (por ejemplo `Inventory.View(data)` o `Gifts.Chances(itemId, data, dim)` para la UI).
- `src/server/DataService.luau`: DataStore `PetNexus_v2` con bloqueo de sesión (ver "Guardado").
  - `Reconcile(data, opts)` migra los datos guardados sin romper nada.
  - `Save` devuelve si guardó; si la carga falló, esa sesión no se guarda nunca.
- `src/server/PetNexusServer.server.luau`: remotes, bucles, anticheat y MarketplaceService.
  Los comandos de debug están en `ServerStorage.PetNexusDebug` (solo en Studio).
- `src/client/PetNexusClient.client.luau`: HUD e interfaz.
- `src/build/WorldBuilder.luau`: construye el mapa desde Studio.
- Los remotes nuevos los crea el servidor si no existen en `PetNexus.Remotes` (función `remote(name)`).
- Cada módulo nuevo hay que añadirlo a `default.project.json`.

## Sistemas
- **Guardado** (`Config.Save`, todos los tiempos PROVISIONAL):
  - El registro guardado es `data` más `SessionLock = { JobId, Session, Time }`; los registros viejos sin lock cargan igual.
  - `Load` toma el lock con `UpdateAsync`. Si otro servidor lo tiene, reintenta cada `LockRetryDelay`; lo toma si no se
    renovó en `LockExpire` (servidor caído) o tras esperar `LockWaitMax` (abandonado).
  - `Save` solo escribe si el lock es de esta sesión y lo renueva. Si otro servidor lo tomó, la sesión queda perdida:
    no guarda más, `ProcessReceipt` no entrega y se saca al jugador (`DataService.OnSessionLost`).
  - Reintentos con espera creciente (1, 2, 4, 8 s), respeta el presupuesto de peticiones, autoguardado cada
    `AutoSaveInterval` y `BindToClose` libera a todos en paralelo (`CloseAll`).
- **Inventario** (`Inventory.luau`):
  - Máximo = 100 + mejora `InventorySlots` (120/150/200/250) + gamepasses `InventoryPlus250` / `InventoryPlus500`: hasta 1000.
  - Lleno: no se abren huevos ni se reciben mascotas (`Inventory.AddPet` es la única entrada).
  - El jugador controla su equipo: una mascota nueva se equipa sola solo si hay un espacio libre (PROVISIONAL,
    `Config.Inventory.AutoEquipNew`). El servidor solo desequipa si sobran (`ClampEquipped`, al bajar `MaxEquipped`).
  - `pet.Locked = true`: no se puede borrar (ni en bulk). El borrado nunca deja menos de `MinPets` (1, PROVISIONAL).
- **Teams**: `data.Teams["<slot>"] = { Name, PetIds }` (clave texto: el DataStore no admite listas con huecos), hasta
  `MaxEquipped` mascotas, `Config.Teams.Max` = 5 (PROVISIONAL). Los nombres se filtran con `TextService`. Borrar una
  mascota (o consumirla en una máquina de variantes) la quita de los teams.
- **Items**: `data.Items[id] = cantidad`, definiciones en `Config.Items` (nombre, rareza, tipo, ícono). Las pociones
  siguen en `data.Potions`; `Inventory.View` arma las pestañas Pets / Items / Potions / Teams.
- **Regalos por tiempo jugado** (`Gifts.luau`, `Config.PlaytimeGifts` y `Config.GiftTables`, todo PROVISIONAL):
  - 12 regalos, uno cada 15 min en la misma sesión; se reinicia al salir. El servidor mide el tiempo (`os.clock`).
  - Etapas: 1-4 Pequeño, 5-8 Normal, 9-11 Grande, 12 Gigante. Al reclamarlo queda como item; se abre con `OpenGift`.
  - Las tablas no usan suerte ni multiplicadores; las monedas se escalan con el progreso del mundo actual.
  - El cliente lee los atributos `PlaytimeSeconds` y `PlaytimeGiftsClaimed` ("1,2,5") del jugador.
- **Meditación**:
  - Zonas con tag `MeditationZone`.
  - Da 1 Esencia por segundo hasta 900 (15 min) y luego 30 min de recarga que solo corre con el jugador conectado.
  - La Esencia no se puede tradear.
  - Developer Product `EssenceCooldownSkip` termina la recarga (si llega cuando ya no hay recarga, queda como salto
    guardado en `Meditation.SkipCredits` y se usa solo en la próxima).
  - Hook para misiones: `Economy.ReduceMeditationCooldown` / `cutMeditationCooldown` en el servidor
    (`Config.Meditation.MissionCooldownCut` = 15 min). Las misiones aún no existen.
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
  - Los 12 gamepasses y los 40 Developer Products tienen `Id = 0` (desactivados).
  - Los IDs reales van en `Config.GamePasses.<clave>.Id` / `Config.Products.<clave>.Id`.
  - `ProcessReceipt` no entrega dos veces (guarda el PurchaseId) y solo confirma tras guardar.
- **Pociones**:
  - El tiempo se acumula y solo corre con el jugador conectado.
  - Pociones gratis: Part con tag `PotionShrine`, cooldown de 3 h en tiempo real y como máximo 3 saltos pagados por día.
- **Zona VIP**:
  - `VipBarrier`: el cliente les quita la colisión a los dueños de VIP.
  - `VipZone`: el servidor saca de ahí a los que no son VIP.

## Tests
- `lune run tests/run`: 146 tests.
- `tests/datastore.spec.luau` prueba `DataService` con un DataStore falso en memoria y dos "servidores" (lock, lock
  abandonado, reintentos, presupuesto, fallo al cargar, `CloseAll`).
- `tests/roblox_mock.luau` simula Roblox para correr el servidor real (`tests/server.spec.luau`).
- En la nube GitHub Releases está bloqueado: instala Lune con `cargo install lune --locked`.
  Para lint, `cargo install selene --locked`.
- En los tests de servidor, mueve jugadores con `Mock.debug("teleport", ...)`: un salto directo lo revierte el anticheat.
- `ProcessReceipt` puede esperar entre reintentos de guardado: en los tests se llama con `receipt(...)`, que lo corre en
  su propio hilo y avanza el reloj.

## Pendiente
- En Studio (lo hace el usuario):
  - Colocar las Parts `RebirthStatue`, `PotionShrine`, `VipBarrier` y `VipZone`.
  - Construir el mapa de Greenwood con las puertas en `Config.GateCFrame`.
  - Poner los IDs reales de gamepasses y productos (incluye `InventoryPlus250`, `InventoryPlus500` y `EssenceCooldownSkip`).
  - UI de inventario (pestañas Pets / Items / Potions / Teams), regalos por tiempo e íconos `GiftSmall`, `GiftNormal`,
    `GiftBig` y `GiftGiant` en `PetNexusAssets.Icons`.
- `DataSync` manda todos los datos en cada cambio (también al romper): con inventarios de hasta 1000 mascotas conviene
  separar las mascotas en su propio sync (toca el cliente).
- Subir `Nexus.EconomyOrder` a 2 cuando se rebalanceen los huevos y mascotas de Nexus.
- Los beneficios del Rebirth 2 no están definidos.
- Greenwood usa los modelos de AngelCoin.
- Mantén este archivo al día cuando cambie algo importante.
