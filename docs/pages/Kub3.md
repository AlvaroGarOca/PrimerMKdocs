# Añadir Kustomize en el proyecto
Como has visto en la práctica anterior, no podemos usar Skaffold sin tener que añadir el HTML previamente a la imagen que usaremos. Skaffold no es capaz de ver los cambios que se hacen en un configmap. Pero eso lo podemos arreglar con Kustomize, una herramienta a la que le podemos dar unos archivos y unas instrucciones para esos archivos, y así poder hacer que nuestro proyecto sea más limpio y manejable. Vamos a ello.

### Deployment, Service e index.html
Como siempre, necesitaremos estos dos archivos para el proyecto. Aquí vamos a ver que no hay demasiados cambios, empecemos por el Deployment.

Para este Deployment, esta vez le vamos a añadir un volumes y volumeMounts, donde le vamos a decir el configmap que queremos y también dónde se montará el HTML que tenemos creado previamente. Este es el código que he usado:

!!!note "Deployment"
    ```bash
    apiVersion: apps/v1
    kind: Deployment
    metadata:
    name: nginx-skaffold
    spec:
    replicas: 1
    selector:
        matchLabels:
        app: nginx-skaffold
    template:
        metadata:
        labels:
            app: nginx-skaffold
        spec:
        containers:
            - name: nginx
            image: nginx:alpine
            resources:
                requests:
                cpu: "50m"      # Minimum CPU reserved for this container (0.05 cores)
                memory: "64Mi"  # Minimum memory reserved
                limits:
                cpu: "250m"     # Maximum CPU allowed (0.25 cores)
                memory: "128Mi" # Maximum memory allowed
            ports:
                - containerPort: 80
            volumeMounts:
            - name: html
                mountPath: /usr/share/nginx/html/
        volumes:
        - name: html
            configMap:
            name: nginx-configmap
    ```

Service en cambio, no tendrá ningún cambio respecto a la práctica anterior, es el mismo.

!!!note "Service"
    ```bash
    apiVersion: v1
    kind: Service
    metadata:
    name: nginx-skaffold
    spec:
    type: NodePort
    selector:
        app: nginx-skaffold
    ports:
        - port: 80
        targetPort: 80
        nodePort: 30080
    ```

También le damos un HTML como anteriormente, puede ser el mismo que antes, ya que esto es irrelevante realmente.

!!!note "Ejemplo de HTML"
    ```html
    <!DOCTYPE html>
    <html>
    <head>
    <title>Skaffold y Kustomize</title>
    </head>
    <body>
    <h1>Cuarenta grados a la sombra, qué horror</h1>
    </body>
    </html>
    ```

### Skaffold
El Skaffold.yaml es parecido al anterior, pero si nos fijamos veremos algunos cambios. El primer cambio que vemos es que ahora hemos quitado la construcción de la imagen con el dockerfile, ya que es algo que no vamos a usar pues ya no lo necesitamos. También, en manisfests, vemos que ya no usamos la instrucción "rawYaml", si no que usamos Kustomize y le damos como path el directorio en el que se encuentra (que está por encima de todo el proyecto), el resto es prácticamente igual.

!!!note "Skaffold.yaml"
    ```bash
    apiVersion: skaffold/v4beta6
    kind: Config
    metadata:
        name: nginx-skaffold
    manifests:
        kustomize:
            paths:
            - .
    deploy:
        kubectl: {}
    portForward:
        - resourceType: service
            resourceName: nginx-skaffold
            port: 80
            localPort: 8080
    ```

### Kustomization.yaml
Nuestro archivo clave para este ejercicio. Aquí le damos la versión que usaremos, el tipo de archivo que es, y vamos a crear el configMapGenerator. Con esto, le vamos a decir que use el configMap que le hemos indicado en el deployment, que se contruirá a raíz de archivos, en nuestro caso el archivo será nuestro Index.html. Con "disableNameSuffixHash" indicamos a Kustomize que no agregue un sufijo hash al nombre del ConfigMap. Y por último los recursos que usará, que son básicamente nuestro service y deployment. 

!!!note "Kustomization.yaml"
    ```bash
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization

    configMapGenerator:
    - name: nginx-configmap
        files: 
        - html/index.html
    generatorOptions:
    disableNameSuffixHash: true # use a static name
    resources:
    - k8s/nginx-service.yaml
    - k8s/nginx-deployment.yaml
    ```

Como se puede ver, realmente es bastante sencillo una vez visto, pero es algo complejo de entender de buenas a primeras. Al menos a mi me costó. Ahora con Skaffold dev verás que se ejecuta todo y te da el enlace como cuando lo hiciste solo con Skaffold, y podrás trabajar directamente. Si añades cosas al html o haces cambios, los verás solo guardando el archivo. El resultado es el mismo, pero la manera de hacerlo es más eficiente y pulcra, y para proyectos más grandes es más efectivo.