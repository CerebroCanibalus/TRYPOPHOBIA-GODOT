"""Extrae las transformadas REST de los huesos del coneja.glb.
Necesitamos los translation/rotation exactos de cada hueso en el archivo
para inicializar los PhysicalBone3D (sino quedan en T-pose absoluta)."""
import struct, json

def parse_glb(path, label):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    gltf = json.loads(data[20:20+chunk_length].decode('utf-8'))
    nodes = gltf.get('nodes', [])
    # Para la coneja: cada nodo relevante tiene translation+rotation en su
    # espacio LOCAL (relativa al padre). La jerarquia esta en `children`.
    # Armature es el root, sus hijos directos son los roots de cadenas.
    print(f"\n=== {label} ===")
    print("Nodos con transform (translation + rotation) en orden de 'padre->hijo':")
    def walk(node_idx, depth, path):
        n = nodes[node_idx]
        name = n.get('name', f'node{node_idx}')
        trans = n.get('translation')
        rot = n.get('rotation')
        scale = n.get('scale')
        if trans is not None or rot is not None:
            tr = [f'{x:.6f}' for x in trans] if trans else ['0','0','0']
            r = [f'{x:.6f}' for x in rot] if rot else ['0','0','0','1']
            sc = [f'{x:.6f}' for x in scale] if scale else ['1','1','1']
            print(f"  [{path}] {name}")
            print(f"    translation = ({', '.join(tr)})")
            print(f"    rotation    = ({', '.join(r)})")
            print(f"    scale       = ({', '.join(sc)})")
        for c in n.get('children', []):
            walk(c, depth+1, f"{path}/{name}")
    # Encuentra Armature
    armature_idx = None
    for i, n in enumerate(nodes):
        if n.get('name') == 'Armature':
            armature_idx = i; break
    if armature_idx is not None:
        walk(armature_idx, 0, '')

parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb', 'coneja.glb')