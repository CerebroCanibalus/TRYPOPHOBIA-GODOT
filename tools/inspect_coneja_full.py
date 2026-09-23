"""Inspeccion profunda: estructura completa de huesos de coneja.glb vs Character.glb"""
import struct, json

def inspect_glb_full(path, label):
    print(f"\n========== {label} ==========")
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    json_data = data[20:20+chunk_length].decode('utf-8')
    gltf = json.loads(json_data)

    nodes = gltf.get('nodes', [])
    print(f"  Total nodes: {len(nodes)}")

    # Construir jerarquia
    print("  ALL NODES (id, name, type hints):")
    for i, n in enumerate(nodes):
        name = n.get('name', '<noname>')
        children = n.get('children', [])
        mesh = n.get('mesh')
        skin = n.get('skin')
        trans = n.get('translation')
        hints = []
        if mesh is not None: hints.append(f"mesh={mesh}")
        if skin is not None: hints.append(f"skin={skin}")
        if children: hints.append(f"children={children}")
        print(f"    [{i}] {name} {hints}")

    # Ver si tiene skeleton
    skins = gltf.get('skins', [])
    if skins:
        skin = skins[0]
        joints = skin.get('joints', [])
        print(f"  Skin joints ({len(joints)}): {[nodes[j].get('name', f'node{j}') for j in joints]}")

inspect_glb_full(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb', 'coneja.glb')
inspect_glb_full(r'D:\Mis Juegos\Tripofobia\Repositorio\src\ragdoll_character\models\Character.glb', 'Character.glb')