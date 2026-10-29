# Paso 3 · Namespace y ConfigMap

**Objetivo:** crear el espacio de trabajo y la configuración de la app.
**Archivos:** [`00-namespace.yaml`](../k8s/00-namespace.yaml), [`01-configmap.yaml`](../k8s/01-configmap.yaml)

## Qué hace cada uno

| Objeto | Qué guarda | Quién lo usa |
|---|---|---|
| Namespace `k8s-lab` | Nada: agrupa todos los objetos del proyecto | Todos |
| ConfigMap `web-config` | `MENSAJE`, `APP_VERSION`, `VALKEY_HOST`, `VALKEY_PORT` | La app `web` |

El ConfigMap va antes que la app porque el Pod lo lee al arrancar.
Si no existe, el Pod queda en `CreateContainerConfigError` hasta que aparezca.

`VALKEY_HOST: "valkey"` no es una IP: es el nombre del Service que vamos a crear en el paso 4.
Adentro del clúster, cada Service tiene un nombre DNS (`valkey`, o completo `valkey.k8s-lab.svc.cluster.local`).

## Pasos

```bash
kubectl config current-context        # docker-desktop
kubectl apply -f k8s/00-namespace.yaml
kubectl config set-context --current --namespace=k8s-lab
```

El último comando hace que los siguientes `kubectl` trabajen en `k8s-lab` sin escribir `-n k8s-lab`.

```bash
kubectl apply -f k8s/01-configmap.yaml
kubectl get configmap web-config -o yaml
```

## Qué deberías ver

- El namespace `k8s-lab` en `Active` (`kubectl get ns`).
- El ConfigMap con sus 4 claves en texto plano.

Siguiente: [Paso 4 · Valkey](04-valkey.md).
