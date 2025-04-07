# :material-wrench: Instalación y preparación de MKdocs 
MKdocs es compatible con:

* :simple-linux: Linux
* :fontawesome-brands-windows: Windows 
* :simple-apple: Mac

En este caso, los ejemplos de los comandos son los usados en Linux, pero los pasos son los mismos.

Sugiero hacer lo siguiente desde :material-microsoft-visual-studio: Visual Studio Code, colocados en el repositorio con el que trabajaremos.

### Instalación de :simple-python: Python
Para poder trabajar con MKdocs, necesitamos tener instalado Python. 

```bash title="Instalar la última versión de Python"
sudo apt install python3.12
```

Una vez instalado, necesitaremos "venv", una herramienta para crear entornos aislados para proyectos en :simple-python: Python.
```bash title="Instalamos venv"
sudo apt install python3.12-venv
```

### Creación del entorno virtual
Una vez instalado Python y venv, tenemos que crear el entorno virtual donde crearemos nuestro proyecto.
```bash title="Usamos el siguiente comando para crear el entorno, con una carpeta oculta. Luego, lo activamos."
python3 -m venv .venv
source .venv/bin/activate
```

```bash title="Para asegurarnos que se usa el entorno que hemos activado"
which python3
```

### Instalación de MKdocs
Una vez preparado el entorno con sus respectivas instalaciones previas, instalamos Mkdocs.

```bash title="Usamos pip para la instalación"
pip install mkdocs
```

```bash title="Al estar colocados en el repositorio, ejecutamos este comando para crear los archivos necesarios"
mkdocs new .
```

### Archivo requirements.txt
Para evitar posibles conflictos con temas, o algunas necesidades de MKdocs, vamos a usar un archivo requirements.txt.
Si nos fijamos, no tendremos ningún archivo con este nombre, por lo que lo creamos nosotros mismos y lo añadimos en la carpeta del proyecto junto al mkdocs.yml que se habrá creado. Dejo aquí el requirements que he usado yo para este proyecto:

```text title="Requirements.txt"
mkdocs==1.6.1
mkdocs-get-deps==0.2.0
mkdocs-material==9.6.11
mkdocs-material-extensions==1.3.1
pymdown-extensions==10.14.3pip
```

!!! warning "Atento/a a esto"

    Te habrás percatado de que en cada línea, además de incorporar qué se necesita, también pone su versión. Es mejor indicar la versión con la que va a trabajar el proyecto, así vamos a evitar posibles problemas de versiones más adelante con actualizaciones que tal vez no sean compatibles con alguna otra cosa.

```bash title="Una vez tenemos el archivo puesto donde toca, ejecutamos este comando para aplicarlo"
pip install -r requirements.txt
```

### Lanzar nuestro MKdocs
Ya lo tenemos todo listo, así que ahora solo falta lanzar nuestro proyecto. 

```bash title="Usamos el puerto 8080 para evitar conflicto de puertos."
mkdocs server -a localhost:8080
```

!!! note "A tener en cuenta"

    En mi instalación, encontré un problema. Si instalas MKdocs en Windows, ya que yo estoy usando WSL para este proyecto, por defecto se lanza MKdocs en el puerto 8000, el cual Windows tiene capado para algún servicio. Así que, como he dicho arriba, es mejor usar el 8080 para evitar problemas y quebraderos de cabeza.

Con todo esto, ya tenemos listo nuestro MKdocs para empezar a trabajar :material-arm-flex: