"""Calculo CORRECTO del angulo de rotacion a partir de quaternion.
El angulo esta en [0, 180] y se computa como 2*acos(|w|).
Ademas calculo la orientacion absoluta del eje de rotacion."""
import struct, json, math

def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20+chunk_length].decode('utf-8'))

gltf = parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb')
nodes = gltf['nodes']

def quat_to_euler_deg(qw, qx, qy, qz):
    """Convierte quaternion a angulos Euler (yaw=Y, pitch=X, roll=Z) en grados."""
    # Sin roll: rotación solo en eje
    # yaw (Y-axis rotation)
    siny_cosp = 2 * (qw * qy + qx * qz)
    cosy_cosp = 1 - 2 * (qy * qy + qx * qx)
    yaw = math.degrees(math.atan2(siny_cosp, cosy_cosp))
    # pitch (X-axis rotation)
    sinp = 2 * (qw * qx - qy * qz)
    pitch = math.degrees(math.asin(max(-1, min(1, sinp))))
    # roll (Z-axis rotation)
    sinr_cosp = 2 * (qw * qz + qx * qy)
    cosr_cosp = 1 - 2 * (qx * qx + qz * qz)
    roll = math.degrees(math.atan2(sinr_cosp, cosr_cosp))
    return (pitch, yaw, roll)

print("Rotacion local de cada hueso en angulos Euler (pitch, yaw, roll) en grados:")
print("(el angulo minimo de rotacion desde identidad)\n")
target = ['espina', 'espina1', 'espina2', 'cuello', 'cabeza',
          'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
          'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
          'pierna1_L', 'pierna2_L', 'rodilla_L', 'pie_L',
          'pierna1_R', 'pierna2_R', 'rodilla_R', 'pie_R']

# Tabla de salida limpia
print(f"{'Hueso':<14} {'Pitch':>8} {'Yaw':>8} {'Roll':>8}  {'Total':>8}")
print("-" * 56)
for n in nodes:
    name = n.get('name', '')
    if name in target:
        rot = n.get('rotation', [0,0,0,1])
        if rot == [0,0,0,1]: continue  # skip identidad
        qw, qx, qy, qz = rot
        p, y, r = quat_to_euler_deg(qw, qx, qy, qz)
        total = math.sqrt(p*p + y*y + r*r)
        flag = "  <<<" if total > 5 else ""
        print(f"{name:<14} {p:+8.2f} {y:+8.2f} {r:+8.2f}  {total:>8.2f}{flag}")