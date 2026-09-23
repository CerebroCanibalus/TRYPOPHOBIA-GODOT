"""Inspecciona los .glb/.fbx de la coneja para entender que tienen dentro."""
import struct, json, sys

def inspect_glb(path, label):
    print(f"\n=== {label} ===")
    with open(path, 'rb') as f:
        data = f.read()
    magic = data[0:4]
    version = struct.unpack('<I', data[4:8])[0]
    length = struct.unpack('<I', data[8:12])[0]
    chunk_length = struct.unpack('<I', data[12:16])[0]
    chunk_type = struct.unpack('<I', data[16:20])[0]
    json_data = data[20:20+chunk_length].decode('utf-8')
    gltf = json.loads(json_data)

    print(f"  File length: {length}, Version: {version}")
    asset = gltf.get('asset', {})
    print(f"  Asset version: {asset.get('version')}")
    print(f"  Generator: {asset.get('generator')}")
    print(f"  Nodes: {len(gltf.get('nodes', []))}")
    print(f"  Meshes: {len(gltf.get('meshes', []))}")
    print(f"  Skins: {len(gltf.get('skins', []))}")
    print(f"  Animations: {len(gltf.get('animations', []))}")
    print(f"  Animation names: {[a.get('name') for a in gltf.get('animations', [])]}")

    print("  Skeleton bones (relevant):")
    for i, n in enumerate(gltf.get('nodes', [])):
        name = n.get('name', '')
        if any(k in name for k in ['Arm', 'Leg', 'Head', 'Body', 'Hip', 'Root', 'Hips']):
            print(f"    [{i}] {name} (translation={n.get('translation', 'N/A')})")

    if gltf.get('animations'):
        a = gltf['animations'][0]
        print(f"  First animation: {a.get('name')}, channels: {len(a.get('channels', []))}")
        for ch in a.get('channels', [])[:5]:
            target = ch.get('target', {})
            print(f"    target.node={target.get('node')} target.path={target.get('path')}")

base = r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p'
inspect_glb(rf'{base}\coneja.glb', 'coneja.glb')
inspect_glb(rf'{base}\coneja_grab.glb', 'coneja_grab.glb')
inspect_glb(rf'{base}\coneja_LeaningBack.glb', 'coneja_LeaningBack.glb')
inspect_glb(rf'{base}\coneja_LeaningFront.glb', 'coneja_LeaningFront.glb')

print("\n\n=== Character.glb (en src/ragdoll_character/models/) ===")
inspect_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\src\ragdoll_character\models\Character.glb', 'Character.glb')