# Flujo de trabajo: Studio <-> GitHub <-> nube

Rojo sincroniza en UNA dirección: archivos -> Studio. Solo un lugar edita los scripts a la vez.

## Qué se sincroniza
Solo los scripts listados en `default.project.json`. El mapa, los modelos, los Remotes y todo lo demás
se queda en Studio y Rojo NO lo toca (`$ignoreUnknownInstances: true` en todos los nodos).

## Ciclo
1. Trabajo local con Claude + MCP de Studio (mapa, modelos, playtests).
2. Antes de una sesión en la nube: Claude exporta los scripts de Studio a `src/` -> commit + push (GitHub Desktop).
3. Sesión en la nube (claude.ai/code, repo pet-nexus): solo lógica. Termina con commit/push.
4. Local: Pull en GitHub Desktop -> VS Code: "Rojo: Open menu" -> Start -> en Studio, plugin Rojo -> Connect.
   Los scripts de Studio quedan reemplazados por los del repo.
5. Seguir en local. Si se editan scripts en Studio, volver al paso 2 antes de la próxima sesión en la nube.

## Reglas para la sesión en la nube
- No hay Studio ni playtests: no inventar nombres de instancias que no existan en el mapa.
- Toda economía/daño en el servidor; todo teleport por `teleport()` del servidor (anticheat).
- Nada de emojis en los textos del juego.
