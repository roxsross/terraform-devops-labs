# Paso 2 · La imagen

**Objetivo:** construir la imagen de la app.
**Archivos:** [`app/server.js`](../app/server.js), [`app/Dockerfile`](../app/Dockerfile)

## Qué hace la app

Un servidor Node sin dependencias que escucha en el puerto 3000:

| Ruta | Respuesta |
|---|---|
| `/` | Página (en el navegador) o JSON (con curl) con el mensaje, el nombre del Pod, la versión y las visitas |
| `/health` | `ok`. Kubernetes la usa para saber si el Pod está listo |

Cada visita le suma 1 a la clave `visitas` en Valkey.
Toda la configuración llega por variables de entorno: `MENSAJE`, `APP_VERSION`, `VALKEY_HOST` y `VALKEY_PORT`.
Así la misma imagen sirve en cualquier lado: cambia la config, no el código.

## Pasos

```bash
docker build -t k8s-app:1.0 ./app
docker run --rm -d -p 3000:3000 --name prueba k8s-app:1.0
curl http://localhost:3000          # probala en Docker antes de llevarla a Kubernetes
docker rm -f prueba
```

## Qué deberías ver

- El `curl` responde `{"mensaje":"Hola desde Kubernetes","version":"1.0","pod":"...","visitas":"sin Valkey"}`.
  Todavía no hay Valkey: por eso `sin Valkey`.

## Ojo con el tag

En [`k8s/03-web.yaml`](../k8s/03-web.yaml) la imagen es `k8s-app:1.0` con `imagePullPolicy: IfNotPresent`:
Kubernetes usa la imagen local de Docker Desktop.
Si usaras `latest`, Kubernetes intentaría descargarla de Docker Hub y el Pod quedaría en `ErrImagePull`.

Cada vez que cambies el código: `docker build` con un tag nuevo (`1.1`) y actualizá el tag en el YAML.

Siguiente: [Paso 3 · Namespace y ConfigMap](03-namespace-configmap.md).
