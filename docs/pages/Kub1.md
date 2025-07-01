# Desplegar un Nginx con Kubernetes
En esta práctica, vamos a hacer una página que nos de la bienvenida, lo que sería un hola mundo de toda la vida. Para ello vamos a crear tres yaml, vayamos por partes.

### ConfigMap
Vamos a usar un Configmap para indicarle el index.html y el contenido que queramos darle, esto lo construirá directamente en una ruta que le daremos en el siguiente yaml.

!!!note "ConfigMap"
    ```bash
    apiVersion: v1
    kind: ConfigMap
    metadata:
    name: welcome-page
    data:
    index.html: |
        <!DOCTYPE html>
        <html>
        <head><title>Bienvenido</title></head>
        <body><h1>¡Bienvenido a mi web con Kubernetes y Nginx!</h1></body>
        </html>
    ```
### Deployment.yaml
En este archivo es donde le damos a dar las instrucciones para que nuestro Minikube despliegue un pod, usando como contenedor la imagen de Nginx en su última versión. También, en la parte de volúmenes, vemos que le vamos a decir que el "welcome-html" es el index.html donde se guarda en Nginx por defecto y como subpath le damos también el index.html. Básicamente, le damos la llave para que la use.

!!!note "deployment.yaml"
    ```bash
    apiVersion: apps/v1
    kind: Deployment
    metadata:
    name: nginx-welcome
    spec:
    replicas: 1
    selector:
        matchLabels:
        app: nginx-welcome
    template:
        metadata:
        labels:
            app: nginx-welcome
        spec:
        containers:
        - name: nginx
            image: nginx:latest
            ports:
            - containerPort: 80
            volumeMounts:
            - name: welcome-html
            mountPath: /usr/share/nginx/html/index.html
            subPath: index.html
        volumes:
        - name: welcome-html
            configMap:
            name: welcome-page
            items:
            - key: index.html
                path: index.html
    ```

### Service
Por último el servicio. Usaremos el tipo NodePort, ya que lo estamos haciendo en local, y más abajo vamos a decirle los puertos por los que trabaja nuestro container, que es el 80, y el nodePort por el que queremos entrar nosotros en local.

!!!note "Service.yaml"
    ```bash
    apiVersion: v1
    kind: Service
    metadata:
    name: nginx-welcome-service
    spec:
    type: NodePort
    selector:
        app: nginx-welcome
    ports:
    - protocol: TCP
        port: 80
        targetPort: 80
        nodePort: 30080
    ```

!!!warning
    Cuidado con las tabulaciones a la hora de escribir el código, ya que puede no ser correcto si no está correctamente colocado.

### Lanzando Minikube
Una vez tenemos los tres archivos, los aplicamos con los siguientes comandos:

```bash
kubectl apply -f configmap.yaml
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml
minikube service --all
```

Con eso aplicaremos los archivos, que crearán un pod de Nginx exponiéndose por el puerto 80 y con el html que le hicimos en el configmap. El último sirve para hacer un túnel y poner entrar de manera local a nuestra página. Si entramos con la IP que nos ofrece, veremos el texto que le pusimos en el configmap.
