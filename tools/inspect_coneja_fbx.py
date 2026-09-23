"""Inspecciona el FBX de la coneja para entender las animaciones que tiene."""
import struct

def inspect_fbx(path, label):
    print(f"\n========== {label} ==========")
    with open(path, 'rb') as f:
        data = f.read()
    print(f"  File size: {len(data)} bytes")
    # FBX empieza con "Kaydara FBX Binary"
    magic = data[:21]
    print(f"  Magic: {magic}")
    # FBX Binary version (uint32 en offset 23)
    version = struct.unpack('<I', data[23:27])[0]
    print(f"  FBX version: {version}")
    # Buscar animaciones en el archivo (buscar "AnimationStack" / "AnimationCurveNode" / "AnimationLayer")
    ascii_data = data.decode('latin-1', errors='ignore')
    # Buscar todos los nodos "AnimationStack" que tienen nombre
    import re
    # En FBX binary cada nodo es un registro. Vamos a buscar strings
    names = re.findall(rb'\x01AnimationStack\x00(.+?)\x00', data)
    if names:
        print(f"  AnimationStack count: {len(names)}")
        for n in names[:10]:
            print(f"    -> {n.decode('latin-1', errors='ignore')}")
    else:
        # Buscar por texto plano
        text_segments = re.findall(rb'AnimationStack\x00(.{1,200})\x00', data)
        print(f"  Busqueda alternativa: {len(text_segments)} matches")
        for t in text_segments[:5]:
            print(f"    -> {t.decode('latin-1', errors='ignore')[:80]}")

inspect_fbx(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja_idle.fbx', 'coneja_idle.fbx')