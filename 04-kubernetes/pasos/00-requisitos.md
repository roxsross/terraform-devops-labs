# Paso 0 · Requisitos

**Objetivo:** tener las herramientas instaladas antes de empezar.

| Herramienta | Para qué | Cómo verificarla |
|---|---|---|
| Docker Desktop | Construye la imagen y corre el clúster de Kubernetes | `docker info` responde sin error |
| kubectl | Le habla al clúster | `kubectl version --client` |
| Helm | Instala Envoy Gateway | `helm version` |
| curl | Probar la app desde la terminal | `curl --version` |

No hace falta cuenta de Docker Hub: Docker Desktop comparte tus imágenes locales con el clúster.

## Si te falta alguna (Mac con Homebrew)

```bash
brew install kubectl helm
```

Docker Desktop se descarga de https://www.docker.com/products/docker-desktop/.
En Windows o Linux: [kubectl](https://kubernetes.io/docs/tasks/tools/), [Helm](https://helm.sh/docs/intro/install/).

## Recursos

Docker Desktop › Settings › Resources: dale al menos **4 GB de RAM** y **2 CPU**.

## Qué deberías ver

```bash
docker info --format '{{.ServerVersion}}'   # un número de versión, no un error
kubectl version --client                    # Client Version: v1.3x
helm version --short                        # v3.x o v4.x
```

Siguiente: [Paso 1 · El clúster](01-cluster.md).
