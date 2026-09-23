"""Verificacion: las rotaciones que mido son locales (respecto al padre) o ya
estan en espacio de armature? glTF2 aplica TRS local a cada nodo, pero hay
que respetar el orden T*R*S. Verifiquemos contra el inverseBindMatrix que
ES la transformacion del hueso en espacio del armature (que es donde vive el
mesh)."""
import struct, json
import numpy as np

def parse_glb(path):
    with open(path, 'rb') as f:
        data = f.read()
    chunk_length = struct.unpack('<I', data[12:16])[0]
    return json.loads(data[20:20+chunk_length].decode('utf-8'))

gltf = parse_glb(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb')
nodes = gltf['nodes']

# Busca el skin y su inverseBindMatrices
skins = gltf.get('skins', [])
if skins:
    skin = skins[0]
    ibm_acc = skin.get('inverseBindMatrices')
    joints = skin.get('joints', [])
    print(f"Skin joints count: {len(joints)}")

    # Leer accessor
    if ibm_acc is not None:
        acc = gltf['accessors'][ibm_acc]
        buf_view = gltf['bufferViews'][acc['bufferView']]
        buf_data = gltf['buffers'][buf_view['buffer']]
        # data esta en data URI base64 o archivo externo
        if 'uri' in buf_data and buf_data['uri'].startswith('data:'):
            import base64
            bin_bytes = base64.b64decode(buf_data['uri'].split(',', 1)[1])
        else:
            # GLB BIN chunk
            with open(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja.glb', 'rb') as f:
                glb = f.read()
            chunk_length2 = struct.unpack('<I', glb[12:16])[0]
            bin_start = 20 + chunk_length2
            bin_offset = buf_view.get('byteOffset', 0)
            bin_length = buf_view.get('byteLength', 0)
            # Necesita alinear a 4 bytes
            bin_offset = (bin_offset + 3) & ~3
            bin_bytes = glb[bin_start + bin_offset: bin_start + bin_offset + bin_length]

        offset = acc.get('byteOffset', 0)
        comp_type = acc.get('componentType', 5126)
        count = acc['count']
        type_ = acc['type']
        # matrices 4x4 = 16 floats
        if type_ == 'MAT4' and comp_type == 5126:
            matrices = np.frombuffer(bin_bytes, dtype=np.float32, count=count*16, offset=offset).reshape(count, 4, 4)
            print(f"Matrices count: {count}")
            # Para cada joint, la inversa de la IBM es la transformacion del hueso en espacio de armature
            # Mostremos las posiciones (translation de la columna 4) y la rotacion
            joint_names_of_interest = ['espina', 'espina1', 'espina2', 'cuello', 'cabeza',
                                       'pierna1_L', 'pierna2_L', 'pie_L',
                                       'pierna1_R', 'pierna2_R', 'pie_R']
            for ji in joints:
                n = nodes[ji]
                name = n.get('name', f'n{ji}')
                if name in joint_names_of_interest:
                    ibm = matrices[ji]
                    # La IBM es la inversa de la bone matrix. La bone matrix tiene la translation del hueso en el espacio del armature (en la columna 4)
                    bone = np.linalg.inv(ibm)
                    pos = bone[:3, 3]
                    # Extraer rotacion (asumiendo escala 1, que es lo normal en rig)
                    # bone_matrix = T * R * S -> R = parte 3x3 de bone_matrix (con escala)
                    rot_mat = bone[:3, :3]
                    # cuaternion from rotation matrix
                    trace = rot_mat[0,0] + rot_mat[1,1] + rot_mat[2,2]
                    if trace > 0:
                        s = 0.5 / np.sqrt(trace + 1.0)
                        w = 0.25 / s
                        x = (rot_mat[2,1] - rot_mat[1,2]) * s
                        y = (rot_mat[0,2] - rot_mat[2,0]) * s
                        z = (rot_mat[1,0] - rot_mat[0,1]) * s
                    else:
                        if rot_mat[0,0] > rot_mat[1,1] and rot_mat[0,0] > rot_mat[2,2]:
                            s = 2.0 * np.sqrt(1.0 + rot_mat[0,0] - rot_mat[1,1] - rot_mat[2,2])
                            w = (rot_mat[2,1] - rot_mat[1,2]) / s
                            x = 0.25 * s
                            y = (rot_mat[0,1] + rot_mat[1,0]) / s
                            z = (rot_mat[0,2] + rot_mat[2,0]) / s
                        elif rot_mat[1,1] > rot_mat[2,2]:
                            s = 2.0 * np.sqrt(1.0 + rot_mat[1,1] - rot_mat[0,0] - rot_mat[2,2])
                            w = (rot_mat[0,2] - rot_mat[2,0]) / s
                            x = (rot_mat[0,1] + rot_mat[1,0]) / s
                            y = 0.25 * s
                            z = (rot_mat[1,2] + rot_mat[2,1]) / s
                        else:
                            s = 2.0 * np.sqrt(1.0 + rot_mat[2,2] - rot_mat[0,0] - rot_mat[1,1])
                            w = (rot_mat[1,0] - rot_mat[0,1]) / s
                            x = (rot_mat[0,2] + rot_mat[2,0]) / s
                            y = (rot_mat[1,2] + rot_mat[2,1]) / s
                            z = 0.25 * s
                    print(f"  {name:<12} pos=({pos[0]:+.4f}, {pos[1]:+.4f}, {pos[2]:+.4f})  quat=({w:+.4f}, {x:+.4f}, {y:+.4f}, {z:+.4f})")