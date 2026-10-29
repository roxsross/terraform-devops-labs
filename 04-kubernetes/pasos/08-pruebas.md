# Paso 8 · Pruebas

**Objetivo:** comprobar que lo que armaste se cuida solo, se configura desde afuera y qué pasa con los datos.
Dejá abierto http://web.localhost:8080 mientras probás.

> Usá dos terminales: una mira (`kubectl get pods -w`), la otra actúa.

## 1. Un Pod muere y vuelve

Borrá uno de los 3 Pods:

```bash
kubectl get pods -l app=web
kubectl delete pod <nombre-de-un-pod-web>
kubectl get pods -l app=web -w
```

**Qué deberías ver:** aparece un Pod nuevo con otro nombre y vuelven a ser 3. La página sigue respondiendo:
mientras tanto, Envoy le manda las visitas a los otros 2.

> Si borrás los 3 a la vez (`kubectl delete pod -l app=web`), durante un instante la página puede mostrar
> `upstream connect error`: Envoy todavía no se enteró de las IPs de los Pods nuevos. Recargá y vuelve.

## 2. Escalar desde el archivo

Cambiá `replicas: 3` por `replicas: 5` en [`03-web.yaml`](../k8s/03-web.yaml):

```bash
kubectl apply -f k8s/03-web.yaml
kubectl get pods -l app=web
for i in $(seq 1 10); do curl -s http://web.localhost:8080 | grep -o '"pod":"[^"]*"'; done
```

**Qué deberías ver:** 5 Pods, y el campo `pod` cambiando entre respuestas. Volvé a `3` cuando termines.

## 3. Cambiar el mensaje sin reconstruir la imagen

Editá `MENSAJE` en [`01-configmap.yaml`](../k8s/01-configmap.yaml):

```bash
kubectl apply -f k8s/01-configmap.yaml
kubectl rollout restart deployment web
kubectl rollout status deployment web
```

**Qué deberías ver:** el mensaje nuevo en el navegador. Las variables se leen al arrancar el Pod: por eso el `restart`.

## 4. Sin disco, los datos se pierden

Anotá el número de visitas y borrá el Pod de Valkey:

```bash
kubectl delete pod -l app=valkey
kubectl get pods -l app=valkey -w      # Ctrl+C cuando esté Running
```

**Qué deberías ver:** al recargar, el contador **vuelve a empezar desde 1**. Valkey guardaba todo en memoria,
y el Pod nuevo arranca vacío. Mientras arranca, la página puede mostrar "Valkey no responde" unos segundos.
Para que los datos sobrevivan haría falta un PersistentVolumeClaim (ver la [demo de volúmenes](../../practicas/04-volumenes/)).

## 5. Una segunda ruta (desafío)

Agregá en [`06-httproute.yaml`](../k8s/06-httproute.yaml) un segundo host, `hola.localhost`, que vaya al mismo Service.
Aplicá y abrí http://hola.localhost:8080. ¿Hizo falta tocar el Gateway? ¿Se creó otro proxy Envoy?

## 6. Mirar todo junto

```bash
kubectl get all,cm,gateway,httproute
kubectl get gatewayclass
kubectl get all -n envoy-gateway-system
```

Siguiente: [Paso 9 · Limpieza](09-limpieza.md).
