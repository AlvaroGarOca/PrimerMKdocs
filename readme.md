# Python Install
### Execute this commands first!

```bash
sudo apt install python3.12-venv
python3 -m venv .venv
source .venv/bin/activate
which python3
pip install -r requirements.txt
mkdocs server -a localhost:8080
```

!!! note "Recuerda"
    Para ver las versiones de lo que está instalado, usa:
    ```bash
    python3 -m pip freeze
    ```
