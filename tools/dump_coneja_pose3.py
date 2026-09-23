"""Conversion CORRECTA quaternion -> angulo minimo de rotacion + eje.
Esto es independiente del orden de rotacion."""
import struct, json, math

def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20+chunk_length].decode('utf-8'))

gltf = parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb')
nodes = gltf['nodes']

print("ROTACION de cada hueso (angulo minimo + eje principal):")
print("Identidad = 0 grados. Cualquier valor indica un hueso doblado en rest pose.\n")

target = ['espina', 'espina1', 'espina2', 'cuello', 'cabeza',
          'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
          'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
          'pierna1_L', 'pierna2_L', 'rodilla_L', 'pie_L',
          'pierna1_R', 'pierna2_R', 'rodilla_R', 'pie_R']

print(f"{'Hueso':<14} {'Angulo':>8}  Eje (X, Y, Z)")
print("-" * 56)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        qw, qx, qy, qz = rot
        # Normalizar
        norm = math.sqrt(qw*qw + qx*qx + qy*qy + qz*qz)
        if norm < 1e-6: continue
        qw, qx, qy, qz = qw/norm, qx/norm, qy/norm, qz/norm
        # angulo minimo
        w_abs = abs(qw)
        if w_abs > 1: w_abs = 1.0
        angle = 2 * math.acos(w_abs)
        angle_deg = math.degrees(angle)
        # eje
        s = math.sqrt(1 - w_abs*w_abs)
        if s < 1e-6:
            axis = (1.0, 0.0, 0.0)
        else:
            axis = (qx/s, qy/s, qz/s)
        if angle_deg < 0.1: continue  # skip identidad
        flag = "  <<<" if angle_deg > 1 else ""
        print(f"{name:<14} {angle_deg:>7.2f}°  ({axis[0]:+.3f}, {axis[1]:+.3f}, {axis[2]:+.3f}){flag}")