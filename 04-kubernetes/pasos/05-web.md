# Paso 5 · La app web

**Objetivo:** desplegar 3 copias de la app conectadas a Valkey.
**Archivo:** [`03-web.yaml`](../k8s/03-web.yaml)

## Qué hace cada parte del Deployment

| Campo | Qué hace |
|---|---|
| `replicas: 3` | Kubernetes mantiene siempre 3 Pods. Si uno muere, crea otro. |
| `selector` + `labels: app: web` | Así el Deployment y el Service reconocen a "sus" Pods. |
| `image: k8s-app:1.0` | La imagen que construiste en el paso 2. |
| `envFrom: configMapRef` | Todas las claves del ConfigMap como variables de entorno. |
| `readinessProbe` | El Service le manda tráfico a un Pod recién cuando `/health` responde. |
| `resources` | Cuánta CPU y memoria se le reserva (`requests`) y cuánta puede usar como máximo (`limits`). |

El Service `web` es `ClusterIP`: solo existe adentro del clúster. Desde afuera se va a llegar por el Gateway (paso 7).

## Pasos

```bash
kubectl apply -f k8s/03-web.yaml
kubectl rollout status deployment web
kubectl get deploy,rs,pods,svc
```

Probala antes de publicarla, con un túnel directo al Service:

```bash
kubectl port-forward svc/web 9090:80
```

Entrá a http://localhost:9090 y recargá varias veces. Cortá con `Ctrl+C`.

Mirá cómo el Service reparte entre los 3 Pods, desde adentro del clúster:

```bash
kubectl run tmp --rm -it --image=busybox --restart=Never -- \
  sh -c 'for i in 1 2 3 4 5 6; do wget -qO- http://web; done'
```

## Qué deberías ver

- 3 Pods `web-...` en `Running` y `READY 1/1`.
- En el navegador: "Mi app en Kubernetes" y el contador de **visitas** subiendo.
- En el loop de busybox, el campo `pod` cambia entre respuestas.

## Si algo falla

| Estado del Pod | Causa probable |
|---|---|
| `ErrImagePull` / `ImagePullBackOff` | El tag no coincide con la imagen construida. Revisá `docker images k8s-app`. |
| `CreateContainerConfigError` | Falta el ConfigMap. Volvé al paso 3. |
| Visitas: "Valkey no responde" | Valkey no está `Running`. Volvé al paso 4. |

Siguiente: [Paso 6 · Envoy Gateway](06-envoy-gateway.md).
