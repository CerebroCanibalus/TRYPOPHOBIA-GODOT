"""Calcula las posiciones GLOBALES de los huesos de la coneja para
saber donde esta la cadera, los pies, la cabeza, etc."""
import struct, json

def q_mult(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (
        aw*bw - ax*bx - ay*by - az*bz,
        aw*bx + ax*bw + ay*bz - az*by,
        aw*by - ax*bz + ay*bw + az*bx,
        aw*bz + ax*by - ay*bx + az*bw,
    )

def q_rotate(q, v):
    qw, qx, qy, qz = q
    vx, vy, vz = v
    # t = 2 * cross(q.xyz, v); v' = v + q.w*t + cross(q.xyz, t)
    tx = 2*(qy*vz - qz*vy)
    ty = 2*(qz*vx - qx*vz)
    tz = 2*(qx*vy - qy*vx)
    return (
        vx + qw*tx + (qy*tz - qz*ty),
        vy + qw*ty + (qz*tx - qx*tz),
        vz + qw*tz + (qx*ty - qy*tx),
    )

def parse_glb_globals(path, bones_of_interest):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    gltf = json.loads(data[20:20+chunk_length].decode('utf-8'))
    nodes = gltf['nodes']
    # walk recursivo, acumulando transformacion global
    def walk(idx, parent_pos, parent_rot, path):
        n = nodes[idx]
        name = n.get('name', f'n{idx}')
        trans = n.get('translation', [0,0,0])
        rot = n.get('rotation', [0,0,0,1])
        local_pos = tuple(trans)
        local_rot = tuple(rot)
        # pos global = parent_pos + parent_rot * local_pos
        rotated_local = q_rotate(parent_rot, local_pos)
        global_pos = (parent_pos[0]+rotated_local[0], parent_pos[1]+rotated_local[1], parent_pos[2]+rotated_local[2])
        global_rot = q_mult(parent_rot, local_rot)
        if name in bones_of_interest:
            print(f"  {name:<14} global_pos=({global_pos[0]:.4f}, {global_pos[1]:.4f}, {global_pos[2]:.4f})")
        for c in n.get('children', []):
            walk(c, global_pos, global_rot, f'{path}/{name}')
    armature_idx = next((i for i,n in enumerate(nodes) if n.get('name')=='Armature'), None)
    walk(armature_idx, (0,0,0), (0,0,0,1), '')

print("Posiciones GLOBALES de los huesos clave de la coneja (en reposo):")
parse_glb_globals(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb', {
    'espina', 'espina1', 'espina2', 'cuello', 'cabeza',
    'hombro_L', 'brazo1_L', 'brazo2_L', 'mano_L',
    'hombro_R', 'brazo1_R', 'brazo2_R', 'mano_R',
    'pierna1_L', 'pierna2_L', 'pie_L',
    'pierna1_R', 'pierna2_R', 'pie_R',
})