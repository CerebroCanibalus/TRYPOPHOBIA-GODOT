# TripoNet — Librería Networking Centralizada

**Estado:** En planificación | **Prioridad:** CRÍTICA | **Esfuerzo estimado:** 3-4 semanas

---

## 1. Motivación

El `NetworkingManager.gd` actual es un esqueleto funcionalmente inútil:
- ✅ ENet peer configurado
- ✅ UDP discovery funcional
- ❌ **CERO RPCs** en todo el proyecto
- ❌ Sin sincronización de estado
- ❌ Sin spawn de jugadores
- ❌ Sin reconciliación de autoridad

Godot nativo proporciona `ENetMultiplayerPeer`, `@rpc`, `MultiplayerSynchronizer` y `MultiplayerSpawner`, pero para un cooperativo de 8 jugadores con objetos físicos agarrables, IA sincronizada y animaciones procedurales, necesitamos **abstracciones de alto nivel**.

---

## 2. Arquitectura

```
addons/tripo_net/
├── plugin.cfg
├── trip_net.gd              (Autoload — API principal)
├── core/
│   ├── network_entity.gd       # Base para cualquier objeto sincronizable
│   ├── network_transform.gd    # Sincronización autoritativa de pos/rot
│   ├── network_physics.gd      # Objetos físicos en red
│   └── network_animation.gd    # Sincronización de estados de animación
├── systems/
│   ├── player_spawner.gd       # Spawn de jugadores con equipamiento
│   ├── enemy_sync.gd           # Sincronización IA enemigos
│   ├── interactable_sync.gd    # Objetos agarrables/lanzables
│   └── sound_sync.gd           # Sonidos que afectan IA en red
├── ui/
│   ├── network_debug.gd        # Overlay debug (ping, packet loss)
│   └── server_browser.gd       # Mejora del browser existente
└── utils/
    ├── network_clock.gd        # Reloj sincronizado
    ├── network_priority.gd     # Priorización por distancia
    └── network_pool.gd         # Object pooling para proyectiles
```

---

## 3. API Propuesta

### 3.1 NetworkEntity (clase base)

```gdscript
extends NetworkEntity  # en vez de Node3D

func _ready():
    register_entity("player", multiplayer.get_unique_id())
    sync_property("global_position", NetworkTransform.LINEAR_INTERP, 0.1)
    sync_property("velocity", NetworkTransform.VELOCITY_BASED)
```

### 3.2 Objetos físicos (agarrar/lanzar)

```gdscript
func grab_object(obj: RigidBody3D):
    NetworkEntity.take_authority(obj, multiplayer.get_unique_id())
    obj.freeze = true
    obj.reparent($HandSocket)

func throw_object(impulse: Vector3):
    var obj = $HandSocket.get_child(0)
    NetworkEntity.release_authority(obj)
    obj.reparent(get_tree().current_scene)
    obj.freeze = false
    obj.apply_central_impulse(impulse)
```

### 3.3 Señales globales

```gdscript
signal player_connected(id: int, info: Dictionary)
signal player_disconnected(id: int)
signal authority_changed(node: Node, new_authority: int)
signal state_synced(entity_id: String, state: Dictionary)
```

---

## 4. Componentes Detallados

### 4.1 NetworkTransform
- Modos: `INSTANT`, `LINEAR_INTERP`, `HERMITE`, `VELOCITY_BASED`
- Jitter buffer configurable
- Compresión de floats (half-precision para distancia)

### 4.2 NetworkPhysics
- Transferencia de autoridad para RigidBody3D
- Snapshot de estado físico (pos, rot, vel, ang_vel)
- Reconciliación: servidor autoritario, cliente predice

### 4.3 EnemySync
- Estado mínimo: posición + animación + target
- IA corre en servidor, clientes interpolan
- SoundArea sincronizado vía eventos (no polling)

### 4.4 InteractableSync
- Puertas, botones, objetos agarrables
- Máquina de estados simple con hash de estado
- Rollback si el servidor rechaza la interacción

---

## 5. Interpolación y Compensación de Lag ⭐ CRÍTICO

### 5.1 Problema

En un juego cooperativo de 8 jugadores con física (objetos agarrables, ragdolls) y animaciones procedurales, el lag puede arruinar la experiencia. Un jugador con 150ms de ping no puede esperar al servidor para ver su propio movimiento.

### 5.2 Opciones a Investigar

| Técnica | Ventajas | Desventajas | Complejidad |
|---------|----------|-------------|-------------|
| **Client-Side Prediction (CSP)** | Respuesta inmediata, sensación de zero lag | Requiere reconciliación, código duplicado cliente/servidor | Media |
| **Entity Interpolation (EI)** | Suave, nunca teletransporta | Delay visual (~100ms), no sirve para objetos controlados por jugador | Baja |
| **Lag Compensation** | Hitbox históricas para precisión de daño | Complejo, requiere buffer de estados | Alta |
| **Dead Reckoning** | Predice trayectoria basada en velocidad | Diverge si cambia dirección, requiere correcciones | Media |
| **Snapshot Interpolation** | Estado completo del mundo cada tick | Alto ancho de banda, buffer de snapshots | Alta |

### 5.3 Estrategia Tentativa para Trypophobia

**Para jugadores (control local):**
- Client-Side Prediction: input se aplica inmediatamente
- Servidor corrige con reconciliación suave (no snapping brusco)
- Interpolación de otros jugadores: 100-150ms de buffer

**Para objetos físicos (props agarrables):**
- Autoridad en el jugador que lo sostiene (predicted)
- Al soltar: transferencia de autoridad al servidor con snapshot de velocidad
- Interpolación en observadores, no predicción

**Para enemigos/IA:**
- Servidor autoritario 100%
- Clientes interpolan posición entre snapshots (no predicen)
- Estado mínimo: pos + orientación + anim_hash (no bones completos)

**Para daño/hitboxes:**
- Servidor autoritario (no lag compensation necesario para PvE)
- Si añadimos PvP futuro: evaluar lag compensation con buffer de 200ms

### 5.4 Decisión Pendiente

¿Implementamos CSP completo o un híbrido más simple (predicción solo para movimiento, interpolación para todo lo demás)?

---

## 6. Arquitectura de Red: Async P2P vs Servidor Dedicado ⭐ CRÍTICO

### 6.1 Contexto

El juego es cooperativo PvE (jugadores vs IA). No queremos depender de servidores dedicados mantenidos por nosotros. Las opciones son:

### 6.2 Opciones Evaluadas

| Arquitectura | Ventajas | Desventajas | Ideal para |
|--------------|----------|-------------|------------|
| **Listen Server (Host-Client)** | Simple, nativo Godot, el host juega y sirve | Si el host se va, partida termina; host tiene ventaja de 0 ping | 2-4 jugadores, amigos |
| **Async P2P (Relay/STUN)** | Sin servidor dedicado, NAT traversal automático | Complejo, requiere infraestructura relay (aunque sea mínima), sincronización más difícil | 2-8 jugadores, matchmaking casual |
| **Servidor Dedicado (Headless)** | Fair, estable, anti-cheat mejor | Costo de hosting, requiere mantenimiento | Esports, comunidad grande |
| **Mesh P2P (totalmente descentralizado)** | Cero costos de servidor | 8 conexiones simultáneas por peer, inconsistencias, imposible sincronizar IA | ❌ No viable para 8p |

### 6.3 Propuesta: Hybrid Async P2P con Relay Ligero

```
OPCIÓN A: Listen Server (Inicial)
├── Un jugador hace "Host"
├── Actúa como servidor autoritario
├── Los demás se conectan vía IP directa o discovery LAN
└── Limitación: si el host abandona, la partida muere

OPCIÓN B: Async P2P con Relay NAT Punchthrough (Objetivo)
├── Relay ligero (ej: Photon's free tier, o un micro VPS de $5/mes)
├── Solo para NAT traversal y matchmaking
├── Una vez conectados: tráfico directo P2P (UDP)
├── Autoridad distribuida por "zona de interés"
└── Fallback a relay si P2P directo falla
```

### 6.4 Decisión Pendiente

- **Fase Alpha**: Implementar Listen Server nativo Godot (más simple, testea gameplay)
- **Fase Beta**: Evaluar si necesitamos relay NAT traversal para jugadores con routers restrictivos
- ¿Vale la pena el costo de un relay vs pedir a los usuarios que abran puertos?
- ¿Queremos matchmaking automático o solo browser de servidores LAN/WAN?

---

## 7. Simulación Distribuida y Optimización de Host ⭐ CRÍTICO

### 7.1 Problema

En un Listen Server, el host ejecuta:
- Física de todos los objetos (Jolt)
- IA de todos los enemigos (NavigationAgent3D + pathfinding)
- Lógica de misión, triggers, spawn
- **Todo mientras renderiza el juego a 60 FPS**

Con 8 jugadores + 20 enemigos + props físicos, el host puede convertirse en cuello de botella.

### 7.2 Opciones de Distribución de Carga

| Técnica | Descripción | Impacto | Complejidad |
|---------|-------------|---------|-------------|
| **Autoridad por Zona** | Cada jugador es autoridad de enemigos/props cercanos | Reduce carga del host 60% | Media |
| **Deterministic Lockstep** | Todos ejecutan la misma simulación, solo se sincronizan inputs | 0 carga en host, pero requiere determinismo perfecto | Muy Alta |
| **Snapshot Delta Compression** | Solo enviar diferencias entre frames, no estado completo | Reduce ancho de banda 80% | Baja |
| **Interest Management** | Cada cliente solo recibe entidades dentro de cierto radio | Reduce tráfico proporcionalmente | Media |
| **Physics LOD** | Objetos lejanos del host usan física simplificada | Reduce CPU host | Baja |

### 7.3 Estrategia Recomendada para Trypophobia

**Para IA de enemigos:**
- Servidor (host) calcula pathfinding y decisiones de IA
- Solo envía a clientes: posición + orientación + estado animación (3 floats + 1 byte)
- Clientes no calculan IA, solo interpolan
- **Optimización**: Enemigos lejanos a TODOS los jugadores se desactivan (sleep)

**Para objetos físicos:**
- Objetos estáticos (puertas, cajas pesadas): simulación solo en host, snapshot a clientes
- Objetos dinámicos (props agarrados): autoridad en el jugador que los sostiene
- Objetos "abandonados" (nadie cerca): freeze + snapshot estático, reactivar cuando un jugador se acerca

**Para física general:**
- Godot Jolt ya es más eficiente que el physics server nativo
- Activar `physics_ticks_per_second = 30` en servidor (suficiente para un juego de este estilo)
- Clientes pueden correr a 60fps render, 30fps física

**Para misión/triggers:**
- Host evalúa triggers
- Eventos importantes (objetivo completado, puerta abierta) se envían como eventos fiables (TCP-like sobre ENet)
- Estado de misión se replica a todos (es pequeño: bools y contadores)

### 7.4 Decisión Pendiente

¿Implementamos "Autoridad por Zona" desde el inicio o comenzamos con host autoritario puro y optimizamos después?

Recomendación: **Host autoritario puro en v1**, medir performance con 8 jugadores, luego evaluar distribución si hay problemas.

---

## 8. Network Debug UI

```gdscript
# Panel overlay que muestra:
- Ping de cada jugador (ms)
- Bytes/s enviados / recibidos
- Entidades sincronizadas (cantidad)
- Autoridad por objeto (colores)
- Gráfico de packet loss (últimos 5s)
- Snapshot de clock offset
- Interpolation buffer depth (ms)
- Host load: physics time, AI time
```

---

## 9. Roadmap de Implementación

| Semana | Tarea |
|--------|-------|
| 1 | Arquitectura base: autoridad, entity sync, clock sync |
| 2 | Player sync: CSP, input, reconciliación básica |
| 3 | Interactables: objetos físicos, transferencia de autoridad |
| 4 | Enemy sync + optimización (interest management, LOD) |
| 5 | Async networking: NAT traversal, relay evaluation |
| 6 | Polish: debug UI, compresión, stress test con 8 jugadores |

---

## 10. Dependencias

- Godot 4.4+ (ENetMultiplayerPeer)
- Godot Jolt (para física consistente servidor-cliente)
- Opcional: Relay service (Photon, PlayFab, o VPS propio) para NAT punchthrough
- Sin addons externos adicionales

---

## 11. Notas Técnicas

- **Servidor autoritario**: Toda la lógica de daño, física crítica y estado de misión corre en servidor/host.
- **Client-side prediction**: Input del jugador se aplica inmediatamente en cliente, servidor corrige si hay discrepancia.
- **Entity ID**: String único generado al vuelo o asignado en editor (`@export var entity_id: String`).
- **Compresión**: Usar `PackedByteArray` + `encode_u16` para posiciones relativas a un origin.
- **Tick rate**: 30 Hz para snapshots de gameplay, 10 Hz para entidades no críticas.
- **Reliable vs Unreliable**: Posiciones = unreliable (UDP). Eventos de misión = reliable (ENet channels).

---

*Documento v1.1 — Secciones críticas añadidas: Interpolación, Async P2P, Simulación Distribuida*
