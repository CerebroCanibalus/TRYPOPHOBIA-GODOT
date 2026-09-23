"""USAR |w| para obtener el angulo MINIMO de rotacion.
Un quaternion (w, x, y, z) y (-w, -x, -y, -z) representan la misma rotacion.
El angulo minimo esta en [0, 180] y se computa como 2*acos(|w|)."""
import struct, json, math

def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20+chunk_length].decode('utf-8'))

gltf = parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets/players/coneja_p/coneja.glb')
nodes = gltf['nodes']

target = ['espina', 'espina1', 'espina2', 'cuello', 'cabeza',
          'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
          'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
          'pierna1_L', 'pierna2_L', 'rodilla_L', 'pie_L',
          'pierna1_R', 'pierna2_R', 'rodilla_R', 'pie_R']

print("ANGULO MINIMO de rotacion por hueso (en grados, usando |w|):\n")
print(f"{'Hueso':<14}  |w|    angulo")
print("-" * 50)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        qw, qx, qy, qz = rot
        n2 = math.sqrt(qw*qw + qx*qx + qy*qy + qz*qz)
        qw, qx, qy, qz = qw/n2, qx/n2, qy/n2, qz/n2
        w_abs = abs(qw)
        angle_rad = 2 * math.acos(min(1.0, w_abs))
        angle_deg = math.degrees(angle_rad)
        s = math.sin(angle_rad / 2)
        if s < 1e-6:
            axis_str = "identidad"
        else:
            axis_str = f"({qx/s:+.2f},{qy/s:+.2f},{qz/s:+.2f})"
        print(f"{name:<14}  {w_abs:.4f}  {angle_deg:7.2f}°  eje={axis_str}")