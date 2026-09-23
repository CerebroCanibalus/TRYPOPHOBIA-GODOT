"""VEREDICTO CORREGIDO. Para un quaternion normalizado (w, x, y, z):
- T-pose (identidad): w = ±1, xyz = 0
- 90° alrededor de eje: w ≈ ±0.707, xyz tiene magnitud ≈0.707
- 180° alrededor de eje: w ≈ 0, xyz tiene magnitud ≈1
Si |w| > 0.99 -> identidad (T-pose)."""
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

print(f"{'Hueso':<14}  |w|    |xyz|   Veredicto")
print("-" * 70)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        qw, qx, qy, qz = rot
        w_mag = abs(qw)
        xyz_mag = (qx*qx + qy*qy + qz*qz) ** 0.5
        if w_mag > 0.99:
            verdict = "T-POSE (≈identidad)"
        elif xyz_mag > 0.7 and w_mag < 0.7:
            verdict = "ROTA 90+ GRADOS"
        elif xyz_mag > 0.1:
            verdict = "rotacion menor"
        else:
            verdict = "?"
        qstr = f"|w|={w_mag:.3f} |xyz|={xyz_mag:.3f}"
        print(f"{name:<14}  {qstr:<25} {verdict}")