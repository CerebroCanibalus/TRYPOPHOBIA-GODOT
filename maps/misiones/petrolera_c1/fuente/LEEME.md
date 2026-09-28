# La fuente del escenario

`petrolera.blend` es la escena de Blender de la que sale todo lo de la carpeta de
arriba. **No la edites a mano**: la reescribe entera

    ~/Documentos/tripofobia-biblia/escenas/petrolera/montar_petrolera.py

que a su vez monta el mapa a partir de `planta.py` y de los `construir_*.py` de
cada pieza. Lo que hay aqui es una copia para que el escenario se pueda reabrir
sin la biblia delante.

El `.gdignore` esta para que Godot no intente importar el `.blend`: su importador
nativo necesita una ruta a Blender configurada en los ajustes del editor y
revienta en headless. El escenario ya llega al motor por dos caminos mejores:

- `../petrolera.tscn`  · el mapa instanciado, 1468 copias de 52 mallas. Es el que
  carga el juego y el que regenera el script.
- `../petrolera.gltf`  · el escenario entero en un fichero (60 mallas, 1528
  nodos). Para abrirlo en cualquier visor o mandarselo a alguien.
