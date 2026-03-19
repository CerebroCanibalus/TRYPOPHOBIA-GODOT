# Player Movement System with Stamina (Godot 4.6.1)

## Overview
This movement system provides a complete stamina-based player controller for Godot 4.6.1, featuring:
- **Stamina System**: 100 base stamina that depletes when running and jumping
- **Character Stats Resource**: Easily create different characters with unique stats
- **Running**: Hold Shift + WASD to run (consumes stamina)
- **Jumping**: Press Space to jump (consumes stamina)
- **Crouching**: Press Ctrl to crouch
- **Stamina Regeneration**: Automatically regenerates after a delay when not consuming stamina

## Files Created

### Core Scripts
1. **`CharacterStats.gd`** - Resource class defining character statistics
2. **`PlayerMovement.gd`** - Main player controller script with stamina management
3. **`StaminaUI.gd`** - UI script for displaying stamina bar and values

### Example Character Stats Resources
1. **`example_character_stats.tres`** - Balanced default character (100 stamina)
2. **`fast_character_stats.tres`** - Fast but low stamina character (80 stamina)
3. **`tank_character_stats.tres`** - Slow but high stamina character (150 stamina)

## Setup Instructions

### Step 1: Create Your Character Scene
1. Create a new scene with `CharacterBody3D` as the root
2. Add the following child nodes:
   - `CameraPivot` (Node3D) - For camera rotation
     - `Camera3D` - The actual camera
   - `CollisionShape3D` - With a CapsuleShape3D
   - Any mesh/visual components you want

### Step 2: Attach the Movement Script
1. Attach `PlayerMovement.gd` to your CharacterBody3D root node
2. In the Inspector, create a new `CharacterStats` resource or assign an existing one:
   - Click on the "Character Stats" property
   - Select "New Resource" → "CharacterStats"
   - Or load one of the example resources (example_character_stats.tres, etc.)

### Step 3: Configure Input Actions
Make sure these input actions are defined in Project Settings → Input Map:
- `ui_up` - W key
- `ui_down` - S key
- `ui_left` - A key
- `ui_right` - D key
- `ui_run` - Shift key (for sprinting)
- `jump` - Space key
- `crouch` - Ctrl key

### Step 4: Set Up Stamina UI (Optional)
1. Create a CanvasLayer with a Control node
2. Add a ProgressBar node named "StaminaBar"
3. Add a Label node named "StaminaLabel"
4. Attach `StaminaUI.gd` to the Control node
5. Set the "Player" export variable to point to your player node path

## Character Stats Properties

### Movement Stats
- **max_stamina**: Maximum stamina value (default: 100)
- **stamina_drain_rate**: Stamina consumed per second while running (default: 20)
- **stamina_jump_cost**: Stamina consumed per jump (default: 15)
- **stamina_regeneration_rate**: Stamina recovered per second (default: 10)
- **stamina_regeneration_delay**: Delay before stamina starts regenerating (default: 1.0)

### Speed Stats
- **walk_speed**: Walking speed (default: 5.0)
- **run_speed**: Running/sprinting speed (default: 10.0)
- **jump_velocity**: Jump force (default: 8.0)

### Camera Stats
- **mouse_sensitivity**: Mouse look sensitivity (default: 0.002)
- **crouch_height**: Camera height when crouching (default: 0.5)
- **normal_height**: Camera height when standing (default: 1.0)
- **crouch_collider_height**: Collider height when crouching (default: 1.0)
- **normal_collider_height**: Collider height when standing (default: 2.0)

## Creating Different Characters

### Method 1: Using the Editor
1. Right-click in the FileSystem dock
2. Select "New Resource" → "CharacterStats"
3. Save it with a descriptive name (e.g., "ninja_stats.tres")
4. Adjust the values for your character type
5. Assign this resource to your character's PlayerMovement script

### Method 2: Programmatically
```gdscript
var custom_stats = CharacterStats.new()
custom_stats.max_stamina = 200
custom_stats.run_speed = 15.0
custom_stats.jump_velocity = 12.0
$Player.character_stats = custom_stats
```

## API Reference

### PlayerMovement Methods
- `get_stamina_percent()` - Returns stamina as a percentage (0.0 to 1.0)
- `get_current_stamina()` - Returns current stamina value
- `get_max_stamina()` - Returns maximum stamina value
- `modify_stamina(amount: float)` - Add or remove stamina

### Example Usage
```gdscript
# Get player reference
var player = $Player

# Check if player can jump
if player.get_current_stamina() >= 15:
    print("Can jump!")

# Give player a stamina power-up
player.modify_stamina(50)

# Display stamina percentage
var percent = player.get_stamina_percent() * 100
print("Stamina: %d%%" % percent)
```

## Tips
- Balance your character stats carefully - high speed should come with trade-offs
- Consider adding visual/audio feedback when stamina is low
- You can create unlimited character types by making new CharacterStats resources
- The system gracefully handles missing CharacterStats by using default values

## Troubleshooting
- **Player doesn't move**: Check that input actions are properly configured
- **Stamina doesn't regenerate**: Make sure you're not holding run/jump buttons
- **Character falls through floor**: Verify CollisionShape3D has a proper shape assigned
- **Camera doesn't rotate**: Ensure CameraPivot node exists as a child of the player
