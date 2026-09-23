"""Verifica la pose de los huesos del coneja_idle.fbx.
FBX es binario, no JSON; tenemos que parsear el formato FBX 7400."""
import struct, math

def parse_fbx_nodes(path):
    """Lee el FBX y devuelve un dict nombre -> (translation, rotation)."""
    with open(path, 'rb') as f:
        data = f.read()
    # FBX 7400 binary: header magic + version + nodos
    magic = data[:21]
    if not magic.startswith(b'Kaydara FBX'):
        raise ValueError("No es un FBX valido")
    version = struct.unpack('<I', data[23:27])[0]
    # Parse recursivo de nodos
    pos = [27]
    nodes = []

    def read_record():
        end_offset = struct.unpack('<Q', data[pos[0]:pos[0]+8])[0]
        pos[0] += 8
        num_props = struct.unpack('<Q', data[pos[0]:pos[0]+8])[0]
        pos[0] += 8
        prop_list_len = struct.unpack('<Q', data[pos[0]:pos[0]+8])[0]
        pos[0] += 8
        name_len = struct.unpack('<B', data[pos[0]:pos[0]+1])[0]
        pos[0] += 1
        name = data[pos[0]:pos[0]+name_len].decode('utf-8', errors='ignore')
        pos[0] += name_len
        # Props
        props = []
        props_end = pos[0] + prop_list_len
        while pos[0] < props_end:
            tc = data[pos[0]:pos[0]+1].decode('ascii', errors='ignore')
            pos[0] += 1
            if tc == 'L': val = struct.unpack('<q', data[pos[0]:pos[0]+8])[0]; pos[0] += 8; props.append(val)
            elif tc == 'I': val = struct.unpack('<i', data[pos[0]:pos[0]+4])[0]; pos[0] += 4; props.append(val)
            elif tc == 'F': val = struct.unpack('<f', data[pos[0]:pos[0]+4])[0]; pos[0] += 4; props.append(val)
            elif tc == 'D': val = struct.unpack('<d', data[pos[0]:pos[0]+8])[0]; pos[0] += 8; props.append(val)
            elif tc == 'S': l = struct.unpack('<I', data[pos[0]:pos[0]+4])[0]; pos[0] += 4; val = data[pos[0]:pos[0]+l].decode('utf-8', errors='ignore'); pos[0] += l; props.append(val)
            else: break
        return name, props, end_offset

    # Empezamos a parsear; el primer nodo es FBXHeaderExtension
    result = {}
    while pos[0] < len(data) - 24:
        try:
            name, props, end = read_record()
            if name == '\x00':
                break
            nodes.append((name, props, end))
            if end == 0:
                break
            pos[0] = end
        except Exception:
            break
    return nodes

print("Parseando coneja_idle.fbx...")
nodes = parse_fbx_nodes(r'D:\Mis Juegos\Tripofobia\Repositorio\assets/players/coneja_p/coneja_idle.fbx')
print(f"Total nodos: {len(nodes)}")

# Buscar los nodos "Model" que tienen Lcl Translation y Lcl Rotation
# En FBX los transforms viven en nodos "Model" con props 70 (translation) y 80 (rotation, euler)
print("\nBuscando nodos 'Model' de los huesos (con Lcl Translation + Lcl Rotation):\n")
target_names = {'espina', 'espina1', 'espina2', 'cuello', 'cabeza',
                'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
                'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
                'pierna1_L', 'pierna2_L', 'rodilla_L', 'pie_L',
                'pierna1_R', 'pierna2_R', 'rodilla_R', 'pie_R'}

# En FBX los nombres vienen como prop[1] del nodo "Model" (prop[0] = uid version)
print(f"{'Hueso':<14}  Translation (x,y,z)            Rotation Euler (x,y,z)")
print("-" * 80)
for name, props, end in nodes:
    if name == 'Model' and len(props) >= 2:
        bone_name = props[1] if isinstance(props[1], str) else ''
        if bone_name in target_names:
            # El nodo Model tiene sub-nodos con las propiedades. El sub-nodo
            # "Properties70" tiene pares (key, value).
            # Necesitamos parsear el siguiente bloque.
            pass

# Mejor: usar la tool de Godot para parsear el FBX directamente.
# Pero eso requiere Godot ejecutándose. Veamos qué tan comun es parsear
# el FBX en Python... la estructura es compleja.

# Plan B: pedirle a Godot via subprocess que abra el FBX y vuelque las poses.
import subprocess
script_gd = """
extends SceneTree
func _initialize():
	var ps: PackedScene = ResourceLoader.load("res://assets/players/coneja_p/coneja_idle.fbx", "PackedScene")
	if ps == null:
		print("ERROR: no se pudo cargar")
		quit(1)
		return
	var root: Node = ps.instantiate()
	var skel: Skeleton3D = root.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		print("ERROR: sin Skeleton3D")
		quit(1)
		return
	print("Skeleton3D con ", skel.get_bone_count(), " huesos")
	target_names = ['espina','espina1','espina2','cuello','cabeza','hombro_L','brazo1_L','brazo2_L','mano_L','hombro_R','brazo1_R','brazo2_R','mano_R','pierna1_L','pierna2_L','rodilla_L','pie_L','pierna1_R','pierna2_R','rodilla_R','pie_R']
	for i in skel.get_bone_count():
		var n = skel.get_bone_name(i)
		if n in target_names:
			var rest = skel.get_bone_rest(i)
			var q = rest.basis.get_rotation_quaternion()
			print("  [", i, "] ", n, " trans=(", rest.origin.x, ", ", rest.origin.y, ", ", rest.origin.z, ") quat=(", q.w, ", ", q.x, ", ", q.y, ", ", q.z, ")")
	quit(0)
"""
with open(r'D:\Mis Juegos\Tripofobia\Repositorio\tools\inspect_coneja_fbx_godot.gd', 'w') as f:
    f.write(script_gd)
print("\nGenerado: tools/inspect_coneja_fbx_godot.gd")
print("Ejecutar: godot --headless --path . --script tools/inspect_coneja_fbx_godot.gd")