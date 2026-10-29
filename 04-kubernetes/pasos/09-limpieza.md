# Paso 9 · Limpieza

**Objetivo:** dejar tu máquina como estaba.

```bash
kubectl config current-context        # docker-desktop
```

## Opción A · Borrar solo la app

Mantiene Envoy Gateway y la GatewayClass, por si querés volver a aplicar todo:

```bash
kubectl delete namespace k8s-lab
```

Borra todo lo del namespace: la app, Valkey, el Gateway y la HTTPRoute.
Al borrarse el Gateway, Envoy Gateway borra solo su proxy en `envoy-gateway-system`.

Para volver a levantar la app de una vez:

```bash
kubectl apply -f k8s/
kubectl config set-context --current --namespace=k8s-lab
```

`kubectl apply -f` sobre la carpeta aplica los archivos en orden alfabético: por eso están numerados.
Envoy Gateway (paso 6.1) tiene que estar instalado antes, porque `04` a `06` son objetos de Gateway API.

## Opción B · Borrar todo lo del proyecto, sin borrar el clúster

En orden inverso a como lo creaste:

```bash
kubectl delete namespace k8s-lab                 # pasos 3 a 5 y 7
kubectl delete -f k8s/04-gatewayclass.yaml         # paso 6.2
helm uninstall eg -n envoy-gateway-system          # paso 6.1: Envoy Gateway y las CRDs
kubectl delete namespace envoy-gateway-system
kubectl config set-context --current --namespace=default
docker rmi k8s-app:1.0                             # paso 2 (opcional)
```

## Opción C · Borrar el clúster entero

Docker Desktop › Settings › Kubernetes › **Reset cluster** (queda un clúster vacío),
o desactivá **Enable Kubernetes** para apagarlo.

## Qué deberías ver

- `kubectl get ns` sin `k8s-lab` (y sin `envoy-gateway-system` en la opción B).
- `kubectl get crd | grep gateway` vacío después de la opción B.
