---
stepsCompleted: [1, 2, 3, 4]
inputDocuments: []
documentCounts:
  briefs: 0
  research: 0
  brainstorming: 0
  projectDocs: 0
workflowType: 'gdd'
lastStep: 2
project_name: 'Tripofobia'
user_name: 'Lord Gatito'
date: '2026-03-28'
game_type: 'horror'
game_name: 'Tripofobia'
---

# Tripofobia - Game Design Document

**Author:** Lord Gatito
**Game Type:** Horror — Cooperativo-Asimétrico Multijugador
**Target Platform(s):** PC (Windows) — Steam

---

## Executive Summary

### Nombre del Juego

Tripofobia

### Core Concept

Tripofobia es un juego de terror y comedia cooperativo-asimétrico para hasta 8 jugadores ambientado en un planeta mayoritariamente acuático. Los jugadores asumen el rol de misioneros enviados a destruir colmenas de **La Niebla Roja** — una entidad colonial viva compuesta por billones de microorganismos — ubicadas en ciudades flotantes y enclaves construidos sobre el agua.

El suspenso central del juego emerge de una amenaza invisible: **uno de los jugadores es el Asimilado**, un infectado que mantiene la apariencia de un misionero sano y puede alternar voluntariamente entre su forma humana y su forma monstruosa. Los misioneros no saben quién es, los Asimilados no pueden morir permanentemente y los jugadores muertos pasan a controlar el entorno como Directores mientras esperan su reaparición. Esta estructura crea una tensión constante entre cooperación, paranoia y traición.

El tono oscila deliberadamente entre el horror opresivo y la comedia emergente generada por las interacciones caóticas entre jugadores.

### Tipo de Juego

**Tipo:** Horror (`horror`)
**Framework:** Este GDD usa el template de horror con énfasis en mecánicas de detección social, terror psicológico y sistemas de amenaza asimétrica multijugador.
**Áreas clave:** Atmósfera y tensión · Mecánicas de miedo · Amenaza encubierta (traidor) · Gestión de recursos · Director como jugador activo

### Target Audience

Jugadores de PC de 17+ años, perfil casual y core, familiarizados con referentes como Lethal Company y Among Us. Sesiones de ~45 minutos orientadas a jugar en grupo.

### Unique Selling Points (USPs)

{{unique_selling_points}}

---

## Target Platform(s)

### Plataforma Principal

**PC (Windows) — Steam**
Plataforma única de lanzamiento. Sin planes de port a consola en el horizonte actual.

### Consideraciones de Plataforma

- Rendimiento objetivo: 60 fps estables con 8 jugadores en red, entornos 3D densos
- Multijugador online vía ENet (implementado: servidor puerto 7777, descubrimiento UDP 7778)
- Soporte de chat de voz de terceros recomendado (Discord, o integración nativa futura)
- Logros de Steam y sistema de lobbies como features deseables en fases avanzadas
- Clasificación de contenido: PEGI 18 / AO (violencia gráfica, discursividad política)

### Esquema de Controles

- **Principal:** Teclado + ratón (WASD · Espacio · Ctrl · Shift · E · Click L/R)
- **Secundario:** Mando compatible (no prioritario en v1.0)

---

## Target Audience

### Demografía

Jugadores de 17 años en adelante. El juego contiene violencia explícita y contenido de discursividad política que requiere madurez para contextualizarlo correctamente. No apto para menores.

### Nivel de Experiencia

**Casual y Core** — El juego debe ser accesible para alguien que no ha jugado horror cooperativo antes, pero con profundidad suficiente para que los jugadores core encuentren capas de estrategia y meta-juego (deducción del Asimilado, coordinación táctica, uso del entorno como Director).

### Familiaridad con el Género

Los jugadores de referencia conocen o han jugado:
- **Lethal Company** — loop de misión cooperativa, extracción bajo presión, humor negro emergente
- **Among Us** — mecánica de traidor oculto, paranoia social, deducción entre compañeros

Tripofobia combina ambos referentes: la tensión de supervivencia de Lethal Company con la desconfianza social de Among Us, elevados por el cambio de apariencia del Asimilado.

### Duración de Sesión

**~45 minutos por partida completa** — desde el lobby hasta la resolución de la misión (colmena destruida + extracción, o eliminación de todos los misioneros sanos). Diseño orientado a que una sesión completa quepa en una tarde con amigos.

### Motivaciones del Jugador

- Jugar con amigos en un contexto caótico y con momentos de humor inesperado
- La tensión de no saber quién es el Asimilado en cada partida
- El placer de "ser el villano" cuando te toca ser Asimilado o Director
- Variedad de personajes con estilos de juego distintos que incentivan la rejugabilidad

---

## Goals and Context

### Metas del Proyecto

1. **Sostenibilidad sin infraestructura propia** — El juego opera 100% en P2P (sin servidores dedicados), eliminando costes operativos continuos y permitiendo que la comunidad mantenga el juego vivo indefinidamente sin depender del estudio.

2. **Comunidad activa en Steam con Workshop** — La Workshop de Steam es un pilar de diseño, no un añadido: mapas, personajes, objetos y modos de juego creados por la comunidad extienden la vida del juego más allá del contenido base.

3. **Retención y boca a boca orgánico** — Partidas de ~45 minutos diseñadas para ser historias contables después. El humor emergente y los momentos de traición son el motor de clips, streams y recomendaciones.

### Contexto y Motivación

Tripofobia nace de la intersección entre convicción política y amor cultural. El creador trae una perspectiva arraigada en la iberofonía socialista y las vanguardias iberófonas, así como un vínculo profundo con la cultura hispana y mexicana. Gran Iberia no es un backdrop decorativo — es la expresión de esa visión: un mundo donde el hispanismo y la cultura iberófona son la base civilizatoria de un futuro posible, con todas sus contradicciones, su burocracia, su heroísmo y su absurdo.

El juego llena un gap real: hay muchos títulos de horror cooperativo, pero ninguno con esta identidad política y cultural. Tripofobia le da a los jugadores hispanohablantes e iberófonos un mundo que les pertenece.

---

## Unique Selling Points (USPs)

### 1. El Asimilado Invisible
No hay marcador, no hay color de impostor, no hay animación delatora. El Asimilado es visualmente idéntico a cualquier misionero sano y puede alternar voluntariamente entre su forma humana y su forma monstruosa. La paranoia es estructural: cualquiera puede ser el enemigo en cualquier momento. Esto eleva el horror psicológico muy por encima del modelo "traidor estático" de Among Us.

### 2. Nunca Dejas de Jugar
Morir no es un tiempo muerto. Los jugadores muertos pasan a ser Directores con capacidad real de influir en la partida: controlan puertas, luces y maquinaria, apoyan al Asimilado o dificultan su labor según su lealtad. Cada estado de juego — Misionero, Asimilado, Director — es un modo activo con su propia agencia. Nadie espera viendo una pantalla negra.

### 3. Gran Iberia — Un Mundo con Identidad Política Real
El planeta de Tripofobia está dominado por Gran Iberia, un imperio socialista de inspiración hispanista e iberófona. El setting no es "espacio genérico": tiene ideología, estética, lore y contradicciones propias. Es el primer juego de horror cooperativo con una identidad cultural hispanohablante en su núcleo, no como traducción sino como origen.

### Posicionamiento Competitivo

| | Lethal Company | Among Us | **Tripofobia** |
|---|---|---|---|
| Traidor oculto | No | Sí (estático) | **Sí (dinámico, cambio visual)** |
| Jugadores muertos activos | No | Fantasma pasivo | **Director con agencia real** |
| Identidad cultural propia | No | No | **Sí — Gran Iberia** |
| P2P / sin servidores | No | No | **Sí** |
| Workshop Steam | No | Limitado | **Pilar central** |

---

## Core Gameplay

### Game Pillars

{{game_pillars}}

### Core Gameplay Loop

{{gameplay_loop}}

### Win/Loss Conditions

{{win_loss_conditions}}

---

## Game Mechanics

### Primary Mechanics

{{primary_mechanics}}

### Controls and Input

{{controls}}

---

## Horror — Elementos Específicos del Género

### Atmósfera y Construcción de Tensión

{{atmosphere}}

### Mecánicas de Miedo

{{fear_mechanics}}

### Diseño de Amenaza/Enemigo

{{enemy_threat}}

### Escasez de Recursos

{{resource_scarcity}}

### Zonas Seguras y Respiro

{{safe_zones}}

### Integración de Puzzles

{{puzzles}}

---

## Progression and Balance

### Player Progression

{{player_progression}}

### Difficulty Curve

{{difficulty_curve}}

### Economy and Resources

{{economy_resources}}

---

## Level Design Framework

### Level Types

{{level_types}}

### Level Progression

{{level_progression}}

---

## Art and Audio Direction

### Art Style

{{art_style}}

### Audio and Music

{{audio_music}}

---

## Technical Specifications

### Performance Requirements

{{performance_requirements}}

### Platform-Specific Details

{{platform_details}}

### Asset Requirements

{{asset_requirements}}

---

## Development Epics

### Epic Structure

{{epics}}

---

## Success Metrics

### Technical Metrics

{{technical_metrics}}

### Gameplay Metrics

{{gameplay_metrics}}

---

## Out of Scope

{{out_of_scope}}

---

## Assumptions and Dependencies

{{assumptions_and_dependencies}}
