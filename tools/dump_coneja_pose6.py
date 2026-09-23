"""Calculo del angulo de rotacion CORRECTAMENTE.
angle = 2 * acos(clamp(w, -1, 1))
Si w es negativo, el angulo esta en [90, 180] grados.
Para la mayoria de cuaterniones exportados por Blender, las rotaciones
chicas (<5 grados) tienen w ≈ ±1, xyz ≈ 0."""
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

print(f"{'Hueso':<14}  w        xyz_mag  angulo  eje (x,y,z)")
print("-" * 80)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        qw, qx, qy, qz = rot
        # Normalizar
        n2 = math.sqrt(qw*qw + qx*qx + qy*qy + qz*qz)
        qw, qx, qy, qz = qw/n2, qx/n2, qy/n2, qz/n2
        w_c = max(-1.0, min(1.0, qw))
        angle_rad = 2 * math.acos(w_c)
        angle_deg = math.degrees(angle_rad)
        s = math.sin(angle_rad / 2)
        if s < 1e-6:
            axis = "(identidad)"
        else:
            axis = f"({qx/s:+.3f}, {qy/s:+.3f}, {qz/s:+.3f})"
        print(f"{name:<14}  {qw:+.4f}  {(qx*qx+qy*qy+qz*qz)**0.5:.4f}  {angle_deg:6.2f}°  {axis}")