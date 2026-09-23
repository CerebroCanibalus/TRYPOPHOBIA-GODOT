"""Inspeccion FBX correcta: parsea nodos y extrae AnimationStack/AnimationLayer names."""
import struct

def read_fbx_node(f, end_offset):
    """Lee un nodo FBX (FBX 7400). Devuelve (name, props, children_data, end_offset)."""
    # Formato: end_offset(uint64), num_props(uint64), prop_list_len(uint64), name_len(uint8), name
    end = struct.unpack('<Q', f.read(8))[0]
    num_props = struct.unpack('<Q', f.read(8))[0]
    prop_list_len = struct.unpack('<Q', f.read(8))[0]
    name_len = struct.unpack('<B', f.read(1))[0]
    name = f.read(name_len).decode('utf-8', errors='ignore')
    # Leer props
    props = []
    props_end = f.tell() + prop_list_len
    while f.tell() < props_end:
        # Cada prop: type_code (char) + data
        type_code = f.read(1)
        if not type_code: break
        t = type_code.decode('ascii', errors='ignore')
        if t == 'Y': val = struct.unpack('<h', f.read(2))[0]; props.append(('i16', val))
        elif t == 'C': val = struct.unpack('<?', f.read(1))[0]; props.append(('bool', val))
        elif t == 'I': val = struct.unpack('<i', f.read(4))[0]; props.append(('i32', val))
        elif t == 'F': val = struct.unpack('<f', f.read(4))[0]; props.append(('f32', val))
        elif t == 'D': val = struct.unpack('<d', f.read(8))[0]; props.append(('f64', val))
        elif t == 'L': val = struct.unpack('<q', f.read(8))[0]; props.append(('i64', val))
        elif t == 'S': length = struct.unpack('<I', f.read(4))[0]; val = f.read(length).decode('utf-8', errors='ignore'); props.append(('str', val))
        elif t == 'R': val = f.read(16); props.append(('raw', val.hex()))
        else:
            # Tipo desconocido: leer tipo y tamaño asociado
            size_map = {'f': 4, 'd': 8, 'l': 8, 'i': 4, 'b': 1}
            sz = size_map.get(t, 1)
            val = f.read(sz)
            props.append((t, val.hex() if val else None))
    # Children: nested nodes o sentinel NULL
    children = []
    while f.tell() < end:
        # Ver si hay otro nodo
        peek = f.read(8)
        if not peek: break
        # NULL record (25 zeros)
        if peek == b'\x00' * 8:
            f.read(8 + 8 + 1)  # name_len + name("\x00")
            children.append({'name': '__NULL__', 'props': [], 'children': []})
            continue
        f.seek(-8, 1)
        child_end = struct.unpack('<Q', f.read(8))[0]
        f.seek(-8, 1)
        if child_end == 0 and f.tell() == end - 25:
            break
        child = read_fbx_node(f, child_end)
        if child['name'] == '__NULL__':
            break
        children.append(child)
    return {'name': name, 'props': props, 'children': children}

def walk(node, depth=0, path=''):
    name = node['name']
    p = path + '/' + name
    if name in ('AnimationStack', 'AnimationLayer', 'AnimationCurveNode', 'AnimationCurve'):
        # Mostrar props (suelen tener un nombre)
        props_str = str(node['props'])[:120]
        print(f"{'  '*depth}[{name}] {props_str}")
    for c in node['children']:
        walk(c, depth + 1, p)

with open(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja_idle.fbx', 'rb') as f:
    # Header
    magic = f.read(21)
    f.read(2)  # unknown
    version = struct.unpack('<I', f.read(4))[0]
    print(f"FBX version: {version}")
    # Leer top-level nodes
    while f.tell() < len(f.read(0)) if False else True:
        # En FBX 7400+ los nodos top-level se encadenan
        pos = f.tell()
        try:
            node = read_fbx_node(f, None)
        except Exception as e:
            print(f"Stop at offset {pos}: {e}")
            break
        if not node['name'] or node['name'] == '__NULL__':
            break
        if node['name'] in ('AnimationStack', 'AnimationLayer'):
            print(f"\n--- TOP-LEVEL: {node['name']} ---")
            for p in node['props']:
                print(f"  prop: {p}")
        if node['name'] == 'Objects':
            # Walk recursivo buscando animaciones
            for c in node['children']:
                walk(c, depth=1)
        if pos == f.tell():
            break
        if pos > 100000:  # safety
            break