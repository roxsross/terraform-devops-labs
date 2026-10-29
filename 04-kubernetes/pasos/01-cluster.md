# Paso 1 · El clúster

**Objetivo:** tener Kubernetes corriendo en Docker Desktop.

## Qué hace Docker Desktop

Docker Desktop arranca un clúster de Kubernetes usando **kind** por debajo: cada nodo es un contenedor.
Además resuelve dos cosas que en un clúster local suelen ser difíciles:

| Necesidad | Cómo lo resuelve Docker Desktop |
|---|---|
| Usar tu imagen sin publicarla | El clúster ve las imágenes que construís con `docker build` |
| Recibir tráfico de afuera | Publica los Services tipo `LoadBalancer` en `localhost` |

## Pasos

1. Docker Desktop › **Settings › Kubernetes**.
2. Activá **Enable Kubernetes** y elegí el tipo de clúster **kind** (1 o 2 nodos alcanza).
3. **Apply & restart** y esperá el ícono verde.

```bash
kubectl config use-context docker-desktop
kubectl config current-context        # docker-desktop
kubectl get nodes
```

## Qué deberías ver

- `desktop-control-plane` (y `desktop-worker` si pediste 2 nodos) en `Ready`.

## Antes de cada paso

```bash
kubectl config current-context
```

Tiene que decir `docker-desktop`. Si tenés otros clústeres configurados (trabajo, nube),
un comando en el contexto equivocado los toca a ellos.

Siguiente: [Paso 2 · La imagen](02-imagen.md).
