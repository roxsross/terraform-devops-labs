# Paso 4 · Valkey

**Objetivo:** levantar la base de datos donde la app cuenta las visitas.
**Archivo:** [`02-valkey.yaml`](../k8s/02-valkey.yaml)

## Qué hace cada uno

| Objeto | Qué hace |
|---|---|
| Deployment `valkey` | 1 Pod de Valkey. Guarda los datos en memoria. |
| Service `valkey` | Le da el nombre fijo `valkey` en el puerto 6379. La app lo encuentra por ese nombre. |

```mermaid
flowchart LR
    W["Pods web"] -->|"valkey:6379"| SV["Service: valkey"] --> V["Pod valkey<br/>datos en memoria"]
```

- **Sin contraseña:** el Service es `ClusterIP`, así que Valkey solo se alcanza desde adentro del clúster.
- **Sin disco:** si el Pod de Valkey se reemplaza, el contador vuelve a 0. Para que los datos sobrevivan
  haría falta un PersistentVolumeClaim (ver la [demo de volúmenes](../../practicas/04-volumenes/)).

## Pasos

```bash
kubectl config current-context        # docker-desktop
kubectl apply -f k8s/02-valkey.yaml
kubectl rollout status deployment valkey
kubectl get pods,svc -l app=valkey
kubectl exec deploy/valkey -- valkey-cli PING
```

## Qué deberías ver

- El Pod de Valkey en `Running`.
- El Service `valkey` tipo `ClusterIP` en el puerto 6379.
- `PONG` como respuesta al `PING`.

Siguiente: [Paso 5 · La app web](05-web.md).
