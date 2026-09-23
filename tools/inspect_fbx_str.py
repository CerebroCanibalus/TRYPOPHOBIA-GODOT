"""Inspeccion FBX alternativa: solo busca nombres ASCII legibles."""
import re

with open(r'D:\Mis Juegos\Tripofobia\Repositorio\assets\players\coneja_p\coneja_idle.fbx', 'rb') as f:
    data = f.read()

# FBX Binary 7400: los nodos son 'name\0' + (hash u64) + ...
# Vamos a buscar strings ASCII imprimibles >=4 chars
# y filtrar los que parezcan nombres de animacion/clips
candidates = set(re.findall(rb'[\x20-\x7e]{4,80}', data))
for c in sorted(candidates):
    s = c.decode('ascii', errors='ignore')
    if any(k in s.lower() for k in ['anim', 'pose', 'idle', 'walk', 'grab', 'lean', 'stack', 'layer', 'curve', 'take', 'clip']):
        print(s)
print("\n--- TODOS los strings > 4 chars que NO sean floats/garbage ---")
seen = set()
for c in candidates:
    s = c.decode('ascii', errors='ignore').strip()
    if len(s) >= 5 and not re.match(r'^[0-9.\-,\s]+$', s) and ' ' not in s:
        if s not in seen:
            seen.add(s)
            # Filtrar los mas interesantes
            if not s.startswith(('Diffuse', 'Normal', 'Texture', 'Material', 'Polygon', 'Vertex', 'UV', 'Skin', 'Bind', 'Pose', 'Model', 'Geometry', 'Deformer')):
                print(s)