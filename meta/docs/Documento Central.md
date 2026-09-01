# Documento Central — Tripofobia

**Autor:** Lord Gatito
**Estado:** Activo
**Última actualización:** 2026-08-31

---

## 1. Resumen Ejecutivo

### Nombre del Juego

**Tripofobia**

### Concepto Central

Tripofobia es un juego de terror y comedia cooperativo-asimétrico para 6-8 jugadores. Los jugadores forman parte de **La Carabela**, una expedición militar enviada a destruir **Colmenas** de la **Niebla Roja** — una entidad colonial viva que ha infestado el Nuevo Continente. Uno de los jugadores está **infectado** por la Colmena y debe eliminar al resto sin ser descubierto. El juego es deliberadamente caótico, con pocas restricciones, fomentando la creatividad del jugador tanto para sobrevivir como para traicionar.

El mundo visual de Tripofobia es **Barroco Futurismo**: la fusión del barroco ibérico con tecnología futurista, donde el mestizaje cultural es el principio rector del diseño. Cada estructura, cada objeto, cada personaje cuenta una historia de dos mundos fusionados.

### Tipo de Juego

- **Género:** Horror cooperativo-asimétrico multijugador
- **Jugadores:** 6-8
- **Plataforma:** PC (Windows) — Steam
- **Motor:** Godot 4.4 (Forward Plus)
- **Sesiones:** ~30-60 minutos por partida

---

## 2. Setting — Gran Iberia

### El Mundo

Un planeta **3 veces más grande que la Tierra**, dominado por agua. Tras una inundación cataclísmica, la mayor parte de la superficie terrestre quedó sumergida. Los continentes se convirtieron en archipiélagos, ciudades flotantes y enclaves sobre el agua. La civilización vive entre torres que emergen del océano, plataformas industriales y rutas marítimas que conectan todo el imperio.

### Gran Iberia

Un **imperio socialista** nacido de la revolución de los pueblos íberos. La unión de las naciones íberas en una revolución comunista acabó con sus monarcas y creó un Estado socialista que, tras una guerra devastadora (la **Guerra de la Última Corola**), conquistó gran parte del planeta.

**Datos clave del imperio:**
- La guerra dejó a la sociedad **mayoritariamente femenina** — la mayoría de los hombres murieron en combate
- 200 años después de la revolución, Gran Iberia está en su **auge imperial**
- Burocracia masiva, heroísmo popular, contradicciones internas
- Estética militar-socialista con influencias ibéricas y hispanoamericanas
- Tecnología avanzada pero desigual: zonas de opulencia y zonas olvidadas

### La Niebla Roja

La amenaza del juego. Una **entidad colonial viva** compuesta por billones de microorganismos que emergió de la zona no explorada del **Nuevo Continente**. La Niebla Roja:
- Infecta y asimila organismos vivos
- Crea **Colmenas** — estructuras enormes que sirven como nidos y centros de expansión
- Se propaga como una niebla rojiza que consume todo lo que toca
- Es parcialmente inteligente: puede usar formas de vida asimiladas como vehículos

### La Carabela

El grupo de jugadores. Una de las tantas expediciones militares enviadas por Gran Iberia a destruir las Colmenas. Nombre que evoca las naves de exploración ibéricas del pasado — ahora adaptadas para combatir una amenaza biológica en un mundo acuático.

---

## 3. Gameplay Core

### El Loop Principal

```
LOBBY (preparación)
  └─► Viaje a la zona de la misión
        └─► Infiltración en la ciudad/enclave infestado
              ├─► Explorar y recolectar recursos
              ├─► Buscar la Colmena
              └─► [INFECTADO: sabotear, eliminar, confundir]
                    └─► Destruir la Colmena
                          ├─► VICTORIA: Colmena destruida → Los sanos ganan
                          └─► VICTORIA: Todos los sanos eliminados → El infectado gana
```

### Roles

#### Tripulante Sano (mayoría)
- Explora el entorno infestado
- Recolecta armas, herramientas y recursos
- Busca y destruye la Colmena
- Debe desconfiar de todos — cualquiera puede ser el infectado
- Puede morir y pasar a ser **Director**

#### Infectado (1 jugador)
- Comienza como un tripulante normal — **visualmente idéntico**
- Puede **transformarse** voluntariamente en su forma mutada (capaz de matar)
- Tiene habilidades especiales que dependen del tipo de infección
- Objetivo: eliminar a todos los sanos ANTES de que destruyan la Colmena
- Debe ser creativo — el juego no le da restricciones, solo oportunidades

#### Director (jugador muerto)
- Jugador que fue eliminado mientras esper reaparición
- Puede **interactuar con el entorno**: puertas, luces, maquinaria, sonidos
- Puede ayudar a los sanos o al infectado (su lealtad es ambigua)
- Nunca está "fuera de juego" — siempre tiene agencia

### Condiciones de Victoria

| Equipo | Condición |
|--------|-----------|
| **Sanos** | La Colmena es destruida |
| **Infectado** | Todos los tripulantes sanos son eliminados |

**No hay límite de tiempo.** La presión proviene del entorno y del infectado, no de un cronómetro.

### Mecánicas Principales

#### Movimiento FPS
- Caminar, correr (sprint), agacharse, saltar
- **Wall jump**: saltar desde paredes para acceder a zonas elevadas
- Sistema de stamina: sprint y saltos consumen resistencia

#### Interacción con el Entorno
- `E` — Usar objeto activo / interactuar
- `Click izquierdo` — Agarrar objetos del entorno (RigidBodies)
- `Click derecho` — Empujar objetos y entidades
- El entorno es interactuable: puertas, interruptores, maquinaria, elevation

#### Inventario (4 slots)
- Cada jugador porta hasta 4 objetos ciclables con Scroll
- **Objeto único del personaje**: cada uno de los 12+ personajes tiene un objeto exclusivo
- **Objetos del entorno**: armas, herramientas, consumibles encontrados en el mapa

#### Transformación del Infectado
- Mantener `F` para alternar entre forma humana y forma mutada
- La transformación tiene un **coste visual/sonoro** — revela al infectado si hay testigos
- En forma mutada: acceso a 3 habilidades ciclables con Scroll, activables con `Q`

#### Crea Tu Propia Estrategia
El juego es **deliberadamente caótico**. No hay una forma "correcta" de hacer las cosas:
- Puedes usar el entorno a tu favor (apagar luces, bloquear pasarelas, crear distracciones)
- Puedes traicionar sutilmente (guía al equipo por mal camino, "accidentalmente" activar alarmas)
- Puedes ser agresivo o sigiloso — el juego te deja decidir

### Controles (PC — Teclado + Ratón)

| Acción | Input | Contexto |
|--------|-------|----------|
| Mover | WASD | Siempre |
| Mirar | Ratón | Siempre |
| Saltar / Wall Jump | Espacio | Siempre |
| Agacharse | Ctrl | Siempre |
| Sprint | Shift | Siempre |
| Ciclar inventario | Scroll | Modo normal |
| Usar / Interactuar | E | Modo normal |
| Agarrar objeto | Click izq. | Modo normal |
| Empujar | Click der. | Modo normal |
| Ciclar habilidades | Scroll | Infectado mutado |
| Activar habilidad | Q | Infectado mutado |
| Transformar (hold) | F | Solo infectado |

---

## 4. Diseño de Niveles

### Estructura de un Mapa

Cada misión se desarrolla en una **zona infestada** — una ciudad, enclave o estructura industrial que la Niebla Roja ha colonizado. Los mapas deben tener:

- **Zonas de infiltración**: entradas, pasarelas, túneles — el acceso a la zona
- **Zonas de exploración**: edificios, habitaciones, corredores — donde se buscan recursos
- **La Colmena**: ubicación final que los sanos deben encontrar y destruir
- **Rutas alternativas**: caminos secundarios para flank, escape o emboscadas
- **Interactividad**: puertas, interruptores, maquinaria, luces — todo manipulable

### Tipos de Mapa (futuros)

| Tipo | Descripción |
|------|-------------|
| Ciudad flotante | Estructura vertical sobre el agua, múltiples niveles |
| Plataforma industrial | Complejo mecánico con tuberías y máquinas |
| Ruinas submarinas | Zonas inundadas, visibilidad reducida |
| Nave de guerra | Interior de un buque de La Carabela comprometido |

---

## 5. Personajes

### Estructura

Cada personaje tiene:
- **Nombre y apariencia** única
- **Objeto exclusivo** que define parte de su rol
- **Stats base** (velocidad, stamina, resistencia) — similares entre todos
- **Lore** vinculado a Gran Iberia y La Carabela

### Diseño de Personajes (placeholder — 12+ personajes planeados)

Los personajes son tripulantes de La Carabela, cada uno con personalidad y habilidad única. La variedad incentiva la rejugabilidad y crea dinámicas sociales diferentes.

*Detalle de personajes → ver sección de Personajes (futura)*

---

## 6. Arte y Audio

### Dirección Artística — Barroco Futurismo

El estilo visual propio de Tripofobia se llama **Barroco Futurismo**: un análisis estético del contraste entre la modernidad temprana hispana y el futurismo. No es retrofuturismo soviético ni steampunk — es una identidad visual propia que nace del barroco ibérico, el mestizaje cultural y la ornamentalidad excesiva como lenguaje de poder.

**Pilares del estilo:**
- **Ornamento como identidad**: estructuras cubiertas de relieves, molduras, filigranas — el exceso decorativo del barroco aplicado a tecnología futurista. Cada edificio, cada arma, cada objeto cuenta una historia cultural
- **Mestizaje visual**: fusiones de estilos artísticos hispanoamericanos con tecnología avanzada — azulejos sevillanos con circuitos, arquitectura virreinal con gravedad artificial, trajes ceremoniales con exoesqueletos
- **Contraste barroco**: luz y oscuridad extrema (tenebrismo), decoración excesiva vs funcionalidad mínima, lo sagrado vs lo profano, lo antiguo vs lo ultramoderno
- **Horror orgánico**: la Niebla Roja corrompe el ornamento — los crecimientos biológicos se entrelazan con las molduras, la filigrana se retuerce, lo hermoso se vuelve grotesco

**Paleta:**
- Dorados y bronce (ornamento imperial, poder)
- Rojos profundos (Niebla Roja, sangre, pasión)
- Azules oscuros (océano, distancia, misterio)
- Negros y blancos extremos (tenebrismo barroco)

**Referentes:**
- Barroco hispanoamericano (iglesias de Oaxaca, Potosí, Cartagena)
- Arquitectura virreinal adaptada a escala futurista
- Filigrana andaluza y morisca fusionada con tecnología
- Tenebrismo de Zurbarán y Ribera aplicado a iluminación de escenas
- Mestizaje como principio de diseño: nunca un estilo puro, siempre una fusión

### Audio

- **Ambiente**: Océano, viento, estructuras metálicas crujiendo, sonidos orgánicos de la Colmena
- **Música**: Tensa, minimalista, crece con la acción
- **Efectos de horror**: Sonidos de la Niebla Roja, gritos distorsionados, respiración pesada
- **UI**: Sonidos industriales, clicks metálicos

---

## 7. Aspectos Técnicos

### Motor y Renderizado

- **Godot 4.4** con Forward Plus
- **Física**: Godot Jolt (addon instalado)
- **Niveles**: Roommate addon (generación procedural) + CSG Toolkit

### Multijugador

- **ENet** vía `NetworkingManager.gd`
- Servidor en puerto 7777, descubrimiento UDP en 7778
- Máximo 8 jugadores
- Arquitectura: Listen Server (host-client) — planificación hacia P2P/relay

### Addons Activos

| Addon | Uso |
|-------|-----|
| godot-jolt | Física mejorada |
| roommate | Generación procedural de niveles |
| cyclops_level builder | Edición de geometría BSP |

### Shaders y Efectos

- Post-proceso de horror: viñeta, estática, scan lines, glitch
- Shader de fondo interactivo (paralaje + sacudida)
- Globales de viento para shaders de entorno

---

## 8. Referentes Competitivo

| Aspecto | Lethal Company | Among Us | **Tripofobia** |
|---------|----------------|----------|----------------|
| Traidor oculto | No | Sí (estático) | **Sí (dinámico, transformación)** |
| Jugadores muertos activos | No | Fantasma pasivo | **Director con agencia real** |
| Identidad cultural | No | No | **Gran Iberia — Barroco Futurismo** |
| Multiplayer | 4 | 10 | **6-8** |
| Setting | Corportativo genérico | Espacial genérico | **Imperio socialista acuático** |
| Estilo visual | Realismo sucio | Minimalista | **Barroco futurista con mestizaje** |

---

## 9. Metas del Proyecto

1. **Jugabilidad emergente** — Las historias surgen de las interacciones entre jugadores, no de cinemáticas scripteadas
2. **Rejugabilidad** — Cada partida es distinta por el mapa, los personajes y quién es el infectado
3. **Comunidad** — Workshop de Steam para mapas, personajes y modos
4. **Sin servidores dedicados** — P2P, sin costos operativos continuos

---

## 10. Estado Actual

### Completado
- Menú principal con efectos shader de horror
- Sistema de multijugador ENet (básico)
- Controlador FPS con stamina
- Sistema de interacción con objetos
- IA de enemigos con NavigationAgent3D
- Sistema de sonido con detección
- Efectos de post-proceso

### En Progreso
- Documento Central (este documento)
- Diseño de niveles con Cyclops

### Pendiente
- Sistema de infección / transformación
- Rol de Director
- Diseño de personajes
- Balanceo de habilidades
- Implementación de Colmena como objetivo

---

*Documento Central v1.0 — Base sólida para el diseño del juego*
