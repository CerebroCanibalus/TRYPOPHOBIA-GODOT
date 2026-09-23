"""Verificacion FINAL: cual es la ROTACION LOCAL de cada hueso relevante?
La rotacion local es lo que Godot aplica al hueso; si es identidad (0,0,0,1)
el hueso esta en T-pose. Si no, esta doblado."""
import struct, json

def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20+chunk_length].decode('utf-8'))

gltf = parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb')
nodes = gltf['nodes']

print("ROTACION LOCAL de cada hueso relevante (lo que importa para el ragdoll):")
print("  Identidad = (0, 0, 0, 1). Cualquier otra cosa = hueso doblado en rest pose.\n")
target = ['espina', 'espina1', 'espina2', 'cuello', 'cabeza',
          'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
          'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
          'pierna1_L', 'pierna2_L', 'rodilla_L', 'pie_L',
          'pierna1_R', 'pierna2_R', 'rodilla_R', 'pie_R']
for i, n in enumerate(nodes):
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        trans = n.get('translation', [0,0,0])
        # Convertir quaternion a angulo en grados para entender
        qw, qx, qy, qz = rot
        # angulo = 2 * acos(w), eje = (x,y,z)/sin(ang/2)
        import math
        w_clamp = max(-1.0, min(1.0, qw))
        angle_rad = 2 * math.acos(w_clamp)
        angle_deg = math.degrees(angle_rad)
        s = math.sin(angle_rad / 2) if angle_rad > 0.001 else 1.0
        axis = (qx/s, qy/s, qz/s)
        flag = "  T-POSE" if abs(angle_deg) < 0.1 else f"  {angle_deg:+6.1f}deg eje=({axis[0]:+.2f},{axis[1]:+.2f},{axis[2]:+.2f})"
        print(f"  {name:<14} rot=({qw:+.3f},{qx:+.3f},{qy:+.3f},{qz:+.3f}) trans=({trans[0]:+.3f},{trans[1]:+.3f},{trans[2]:+.3f}){flag}")

print("\nLONGITUD de cada hueso (magnitud de translation local):")
for i, n in enumerate(nodes):
    name = n.get('name', '')
    if name in target:
        trans = n.get('translation', [0,0,0])
        import math
        length = math.sqrt(trans[0]**2 + trans[1]**2 + trans[2]**2)
        print(f"  {name:<14} {length:.4f} m ({trans[0]:+.3f}, {trans[1]:+.3f}, {trans[2]:+.3f})")