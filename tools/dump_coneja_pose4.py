"""Veredicto final: mostrar TODOS los cuaterniones crudos de los huesos.
Si w esta cerca de +-1 y xyz cerca de 0, el hueso esta en T-pose.
Si w esta cerca de 0 y xyz es significativo, el hueso esta rotado 90+ grados."""
import struct, json

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

print(f"{'Hueso':<14}  {'Quaternion (w, x, y, z)':<35}  Veredicto")
print("-" * 80)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        qw, qx, qy, qz = rot
        # Veredicto:
        # T-pose = w≈±1, xyz≈0
        # 90deg en eje = w≈0.707, un xyz≈0.707
        xyz_mag = (qx*qx + qy*qy + qz*qz) ** 0.5
        w_mag = abs(qw)
        if xyz_mag < 0.01 and w_mag > 0.99:
            verdict = "T-POSE"
        elif xyz_mag > 0.6:
            verdict = "ROTA 90+ GRADOS"
        elif xyz_mag > 0.1:
            verdict = "rotacion parcial"
        else:
            verdict = "?"
        qstr = f"({qw:+.3f}, {qx:+.3f}, {qy:+.3f}, {qz:+.3f})"
        print(f"{name:<14}  {qstr:<35}  {verdict}")