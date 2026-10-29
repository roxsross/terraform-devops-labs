# Laboratorio 05 — GitHub Actions Runner Controller (ARC) en Kubernetes local

> Navegación: [README general](../README.md) · ← anterior: [Laboratorio 04 — Kubernetes](../04-kubernetes/README.md) · siguiente: ninguno (último lab) →

> ⚠ **Advertencia — leé esto antes de empezar.**
>
> - Un runner self-hosted ejecuta el código de los workflows **dentro de tu cluster y con acceso a tu red**.
> - Usalo **solo con repos privados y propios**. **Nunca** lo conectes a un repo público que acepta pull requests de forks: cualquiera podría correr código en tu máquina. Ver [Hardening for self-hosted runners](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#hardening-for-self-hosted-runners).
> - El token (PAT) da permisos de administración sobre el repo. **No lo pegues en comandos, archivos ni capturas**, y **revocalo al terminar** (sección [Limpieza](#limpieza)).

## Objetivo

Instalar **Actions Runner Controller (ARC)** con Helm en el Kubernetes local del laboratorio 04 y registrar un **runner scale set** en un repo propio de GitHub. Al final, un workflow con `runs-on: arc-runner-set` corre en un pod efímero dentro de tu cluster y puede hacer `docker build` gracias al modo Docker-in-Docker (`dind`).

## Qué es ARC y cómo funciona

ARC es un operador de Kubernetes mantenido por GitHub. En lugar de tener una VM con un runner siempre prendido, ARC crea **un pod por job**: el pod se registra como runner, corre el job y se borra.

Se instala con dos charts de Helm:

| Chart | Release | Namespace | Qué instala |
|---|---|---|---|
| `gha-runner-scale-set-controller` | `arc` | `arc-systems` | El controller y las CRDs (`AutoscalingRunnerSet`, `EphemeralRunnerSet`, `EphemeralRunner`, `AutoscalingListener`) |
| `gha-runner-scale-set` | `arc-runner-set` | `arc-runners` | Un runner scale set: el recurso `AutoscalingRunnerSet` que apunta a tu repo |

```mermaid
flowchart LR
  GH[GitHub<br/>repo propio<br/>Actions] <-->|long poll HTTPS<br/>jobs en cola| LIS
  subgraph CL[Cluster local: docker-desktop]
    subgraph SYS[Namespace: arc-systems]
      CTRL[Controller<br/>arc-gha-rs-controller]
      LIS[Listener<br/>arc-runner-set-...-listener]
    end
    subgraph RUN[Namespace: arc-runners]
      ARS[AutoscalingRunnerSet<br/>arc-runner-set]
      SEC[(Secret<br/>pre-defined-secret)]
      R1[Pod runner efímero<br/>runner + sidecar dind]
    end
  end
  CTRL -.->|lee| ARS
  CTRL -->|crea| LIS
  LIS -->|pide N runners| CTRL
  CTRL -->|crea y borra| R1
  SEC -.->|github_token| LIS
  R1 <-->|corre el job| GH
```

| Pieza | Dónde corre | Qué hace |
|---|---|---|
| **Controller** | `arc-systems` | Observa los recursos de ARC y crea el listener y los pods de runner |
| **Listener** | `arc-systems` (namespace del controller) | Mantiene una conexión con GitHub, se entera de los jobs en cola y le pide al controller cuántos runners hacen falta |
| **AutoscalingRunnerSet** | `arc-runners` | La definición del scale set: URL del repo, secret, `minRunners`, `maxRunners` |
| **Secret** `pre-defined-secret` | `arc-runners` | Guarda el PAT en la clave `github_token` |
| **Pods de runner** | `arc-runners` | Efímeros: aparecen cuando llega un job, lo corren y se borran. Con `containerMode.type: dind` traen un sidecar con Docker (ver [Docker dentro del runner (dind)](#docker-dentro-del-runner-dind)) |

> El nombre del scale set es el **nombre del release de Helm** (`arc-runner-set`), y ese es el valor que va en `runs-on`. Se puede cambiar con `runnerScaleSetName`.

## Docker dentro del runner (dind)

Por defecto el pod de runner **no tiene daemon Docker**: un `docker build` falla con `Cannot connect to the Docker daemon`. Para construir imágenes en los jobs, este lab instala el scale set con el modo Docker-in-Docker del chart:

```yaml
containerMode:
  type: "dind"
```

Con ese valor, el chart arma cada pod de runner así (nombres tomados del template del chart `gha-runner-scale-set`):

| Contenedor | Tipo | Qué hace |
|---|---|---|
| `init-dind-externals` | init container | Copia los binarios externos del runner a un volumen compartido y termina |
| `dind` | sidecar (init container con `restartPolicy: Always`) | Imagen `docker:dind` con `privileged: true`; levanta `dockerd` en `unix:///var/run/docker.sock` |
| `runner` | contenedor principal | El runner de GitHub Actions, con `DOCKER_HOST=unix:///var/run/docker.sock` apuntando al socket del sidecar |

> ⚠ **El sidecar `dind` corre como `privileged`**: tiene acceso casi total al nodo. En un cluster local propio es aceptable; en un cluster compartido o productivo no lo es. Alternativas que construyen imágenes sin privilegios: Kaniko o BuildKit en modo rootless (no se cubren en este lab).

La tabla vale para Kubernetes `>= 1.29` (el de Docker Desktop actual lo cumple: `kubectl version`), donde `dind` corre como sidecar nativo. En clusters `< 1.29`, `dind` aparece como un contenedor más junto a `runner`. Detalle en [Using Docker-in-Docker mode](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets#using-docker-in-docker-mode).

## Prerrequisitos

| ✔ | Requisito | Cómo verificarlo | Resultado esperado |
|---|---|---|---|
| [ ] | Kubernetes de Docker Desktop (el del [lab 04](../04-kubernetes/README.md)); si no lo tenés, seguí [Paso 1 · El clúster](../04-kubernetes/pasos/01-cluster.md) | `kubectl get nodes` | `desktop-control-plane` en `Ready` |
| [ ] | `kubectl` | `kubectl version --client` | `Client Version: v1.x` |
| [ ] | Helm `>= 3.8` (soporte OCI) | `helm version` | `v3.8` o superior (Helm 4 también sirve) |
| [ ] | Un repo **privado y propio** en GitHub | Abrirlo en el navegador | Sos admin del repo |
| [ ] | Un PAT con los permisos de [El token (PAT)](#el-token-pat) | — | Lo tenés a mano, sin guardarlo en archivos |

> ⚠ **Contexto de kubectl.** Antes de cada paso corré `kubectl config current-context`. Tiene que decir `docker-desktop`. Si tenés otros clusters configurados (trabajo, nube), un comando en el contexto equivocado los toca a ellos.

No hace falta tener desplegada la app del lab 04: ARC usa sus propios namespaces y puede convivir con ella.

## Archivos del laboratorio

| Archivo | Para qué sirve |
|---|---|
| `README.md` | Esta guía |
| `values.yaml` | Values de ejemplo del scale set (`githubConfigSecret`, `containerMode.type: dind`, `minRunners`, `maxRunners`). **Sin secretos** |
| `workflow-ejemplo/arc-demo.yml` | Workflow de prueba con `runs-on: arc-runner-set`: un job de `echo`/`hostname` y otro con `docker version` y `docker build`. Se copia a `.github/workflows/` de tu repo |
| `workflow-ejemplo/Dockerfile` | Imagen mínima (`alpine`) que construye el job `docker`. Se copia a `arc-demo/Dockerfile` de tu repo |
| `workflow-ejemplo/ci-cd.yml` | Pipeline de la app del lab 04: `init → test → build → deploy-dev → deploy-prod`. Ver [Pipeline completo](#pipeline-completo-de-github-al-cluster) |
| `workflow-ejemplo/chart/` | Chart de Helm de la app (convertido desde `04-kubernetes/k8s/`) con `values-dev.yaml` y `values-prod.yaml` |
| `rbac-deployer.yaml` | Namespaces `k8s-lab-dev` y `k8s-lab-prod`, ServiceAccount `arc-deployer` y un Role + RoleBinding por namespace para el deploy con Helm |

## El token (PAT)

ARC necesita autenticarse contra la API de GitHub para registrar runners. Para un laboratorio alcanza con un **personal access token (PAT)**. Para uso real en repos u organizaciones, GitHub recomienda una **GitHub App** ([Authenticating ARC to the GitHub API](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api)).

**Opción recomendada: fine-grained PAT** (GitHub › Settings › Developer settings › Personal access tokens › Fine-grained tokens):

- **Repository access:** *Only select repositories* → solo tu repo de prueba.
- **Permissions › Repository permissions › Administration:** *Read and write*. (*Metadata: Read-only* se agrega solo.)
- **Expiration:** lo más corto posible (por ejemplo, 7 días).

**Alternativa: classic PAT** con el scope `repo` (para runners a nivel organización haría falta además `admin:org`; este lab usa runners de repo).

La URL que identifica al dueño de los runners tiene este formato:

```text
https://github.com/<owner>/<repo>
```

Por ejemplo, `https://github.com/mi-usuario/mi-repo-privado`. Sin `.git` al final y sin `/` final.

## Paso a paso

### Paso 1 · Verificar el cluster

```bash
kubectl config current-context
kubectl get nodes
helm version
```

Salida esperada:

```text
docker-desktop
NAME                    STATUS   ROLES           AGE   VERSION
desktop-control-plane   Ready    control-plane   ...   v1.x
```

### Paso 2 · Instalar el controller

```bash
NAMESPACE="arc-systems"
helm install arc \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller
```

Helm baja el chart del registry OCI de GitHub (`ghcr.io`) e instala el controller y las CRDs. Para fijar una versión, agregá `--version <x.y.z>` (las versiones están en el [registry del chart](https://github.com/actions/actions-runner-controller/pkgs/container/actions-runner-controller-charts%2Fgha-runner-scale-set-controller)).

Verificá:

```bash
kubectl get pods -n arc-systems
```

Salida esperada (el hash cambia):

```text
NAME                                     READY   STATUS    RESTARTS   AGE
arc-gha-rs-controller-6d8c9f7b5d-x2k4p   1/1     Running   0          40s
```

> En versiones viejas del chart el pod se llama `arc-gha-runner-scale-set-controller-...`. Lo importante es que esté `Running`.

### Paso 3 · Cargar el token sin dejarlo en el historial

El comando original pone el token en una variable escrita a mano (`GITHUB_PAT="TOKEN"`), y eso queda en el historial del shell. En cambio, pedilo con `read -s` (no se ve en pantalla ni queda en el historial):

```bash
read -s -p "Pegá tu PAT: " GITHUB_PAT; echo
export GITHUB_PAT

GITHUB_CONFIG_URL="https://github.com/<owner>/<repo>"   # tu repo privado
```

Comprobá que la variable tiene algo, sin mostrarla:

```bash
echo "${#GITHUB_PAT} caracteres"
```

### Paso 4 · Crear el secret (recomendado)

En vez de pasarle el token a Helm, lo guardás en un Secret de Kubernetes y le pasás a Helm **solo el nombre** del Secret. El Secret va en el **namespace del scale set**, que tiene que existir antes:

```bash
kubectl create namespace arc-runners

kubectl create secret generic pre-defined-secret \
    --namespace arc-runners \
    --from-literal=github_token="$GITHUB_PAT"

unset GITHUB_PAT
```

Salida esperada:

```text
namespace/arc-runners created
secret/pre-defined-secret created
```

> El token no se escribe en ningún archivo ni en el historial: `"$GITHUB_PAT"` se expande en el momento. Desde acá ya no hace falta tenerlo en la terminal.

### Paso 5 · Instalar el runner scale set

Camino recomendado, con el Secret del paso 4:

```bash
INSTALLATION_NAME="arc-runner-set"
NAMESPACE="arc-runners"
helm install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    --set githubConfigSecret=pre-defined-secret \
    --set containerMode.type="dind" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

`--create-namespace` no molesta aunque el namespace ya exista. `containerMode.type="dind"` agrega Docker al pod de runner (ver [Docker dentro del runner (dind)](#docker-dentro-del-runner-dind)). Si preferís usar el [`values.yaml`](values.yaml) del lab, que ya trae el Secret y el modo dind (desde la carpeta `05-github-actions-arc/`):

```bash
helm install arc-runner-set \
    --namespace arc-runners \
    -f values.yaml \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

#### Variante: token en `--set` (el comando del quickstart)

Es el comando del [quickstart oficial](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart), con el agregado de `containerMode.type="dind"`. Funciona sin el paso 4, porque el chart crea el Secret por vos:

```bash
INSTALLATION_NAME="arc-runner-set"
NAMESPACE="arc-runners"
GITHUB_CONFIG_URL="https://github.com/<owner>/<repo>"
# GITHUB_PAT cargado con read -s (paso 3), nunca escrito acá
helm install "${INSTALLATION_NAME}" \
    --namespace "${NAMESPACE}" \
    --create-namespace \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    --set githubConfigSecret.github_token="${GITHUB_PAT}" \
    --set containerMode.type="dind" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

> ⚠ Con esta variante el token queda guardado **en los values del release de Helm**: cualquiera con acceso al namespace lo ve con `helm get values arc-runner-set -n arc-runners`. Por eso la [documentación oficial](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets) recomienda crear el Secret aparte y pasar solo su nombre.

### Paso 6 · Verificar la instalación

```bash
helm list -A
```

```text
NAME            NAMESPACE     REVISION  UPDATED  STATUS    CHART                                   APP VERSION
arc             arc-systems   1         ...      deployed  gha-runner-scale-set-controller-0.x.y   0.x.y
arc-runner-set  arc-runners   1         ...      deployed  gha-runner-scale-set-0.x.y              0.x.y
```

El listener aparece en el namespace **del controller**:

```bash
kubectl get pods -n arc-systems
```

```text
NAME                                     READY   STATUS    RESTARTS   AGE
arc-gha-rs-controller-6d8c9f7b5d-x2k4p   1/1     Running   0          3m
arc-runner-set-754b578d-listener         1/1     Running   0          20s
```

El scale set y el namespace de runners (sin pods todavía, porque `minRunners` es 0):

```bash
kubectl get autoscalingrunnersets -n arc-runners
kubectl get pods -n arc-runners
```

```text
NAME             MINIMUM RUNNERS   MAXIMUM RUNNERS   CURRENT RUNNERS   STATE   PENDING RUNNERS   RUNNING RUNNERS   FINISHED RUNNERS   DELETING RUNNERS
arc-runner-set                                       0
No resources found in arc-runners namespace.
```

En GitHub: tu repo › **Settings › Actions › Runners**. Tiene que aparecer el scale set **`arc-runner-set`**.

### Paso 7 · Correr el workflow de prueba

1. En **tu repo**, copiá [`workflow-ejemplo/arc-demo.yml`](workflow-ejemplo/arc-demo.yml) a `.github/workflows/arc-demo.yml` y [`workflow-ejemplo/Dockerfile`](workflow-ejemplo/Dockerfile) a `arc-demo/Dockerfile`:

   ```bash
   # desde la raíz de tu repo privado
   LAB=/ruta/a/terraform-devops-labs/05-github-actions-arc
   mkdir -p .github/workflows arc-demo
   cp "$LAB/workflow-ejemplo/arc-demo.yml" .github/workflows/
   cp "$LAB/workflow-ejemplo/Dockerfile" arc-demo/
   git add .github/workflows/arc-demo.yml arc-demo/Dockerfile
   git commit -m "ci: workflow de prueba para ARC"
   git push
   ```

2. En otra terminal, mirá los pods de runner:

   ```bash
   kubectl get pods -n arc-runners -w
   ```

3. En GitHub: **Actions › ARC demo › Run workflow**.

Salida esperada en la terminal del `-w`: el workflow tiene dos jobs (`demo` y `docker`), así que aparecen dos pods. Cada uno arranca, corre su job y se borra. `READY 2/2` son el `runner` y el sidecar `dind`:

```text
NAME                                READY   STATUS            RESTARTS   AGE
arc-runner-set-rmrgw-runner-p9p5n   0/2     Pending           0          0s
arc-runner-set-rmrgw-runner-k7d2q   0/2     Pending           0          0s
arc-runner-set-rmrgw-runner-p9p5n   0/2     Init:1/2          0          2s
arc-runner-set-rmrgw-runner-p9p5n   2/2     Running           0          9s
arc-runner-set-rmrgw-runner-k7d2q   2/2     Running           0          10s
arc-runner-set-rmrgw-runner-p9p5n   1/2     Completed         0          25s
arc-runner-set-rmrgw-runner-p9p5n   0/2     Terminating       0          26s
...
```

Los nombres, los tiempos y los estados intermedios varían. Mientras un pod está `Running`, comprobá sus contenedores (reemplazá el nombre por uno de tu salida):

```bash
POD=arc-runner-set-rmrgw-runner-k7d2q
kubectl get pod -n arc-runners "$POD" -o jsonpath='{.spec.initContainers[*].name}{"\n"}{.spec.containers[*].name}{"\n"}'
```

```text
init-dind-externals dind
runner
```

`dind` aparece entre los init containers porque es un sidecar nativo (`restartPolicy: Always`): sigue corriendo junto al `runner` durante todo el job. En clusters `< 1.29` la segunda línea dice `runner dind`.

En GitHub, el log del job:

- **demo**: el paso **Nombre del pod (hostname)** muestra el nombre del pod (`arc-runner-set-...-runner-...`).
- **docker**: `docker version` muestra las secciones `Client` y `Server` (el `Server` es el `dockerd` del sidecar), el `docker build` termina con `naming to docker.io/library/arc-demo:<run_id>` y `docker run` imprime `imagen construida dentro de un runner de ARC`.

Salí del `-w` con `Ctrl+C`.

> La primera vez el job puede tardar un poco más: el nodo tiene que bajar la imagen del runner (`ghcr.io/actions/actions-runner`).

## Pipeline completo: de GitHub al cluster

Con el runner corriendo **dentro** del cluster se puede armar un CI/CD completo de la app del [lab 04](../04-kubernetes/README.md), con dos ambientes en el mismo cluster local: `dev` (namespace `k8s-lab-dev`) y `prod` (namespace `k8s-lab-prod`). El workflow es [`workflow-ejemplo/ci-cd.yml`](workflow-ejemplo/ci-cd.yml) y la app se despliega con un chart de Helm propio, [`workflow-ejemplo/chart/`](workflow-ejemplo/chart/).

El namespace `k8s-lab` del lab 04 no se toca: sigue siendo tu despliegue manual de referencia en `http://web.localhost:8080`.

```mermaid
flowchart LR
  PR[pull request] --> I
  PUSH[push a main<br/>o tag v*.*.*] --> I
  I[init<br/>metadatos + npm ci] --> T[test<br/>npm test + helm lint/template]
  T -->|no en PR| B[build<br/>docker build + push<br/>ghcr.io/owner/repo:sha]
  B --> D[deploy-dev<br/>environment dev<br/>k8s-lab-dev]
  D -->|aprobación| P[deploy-prod<br/>environment prod<br/>k8s-lab-prod]
  B -.->|imagen| GHCR[(GHCR)]
  GHCR -.->|misma imagen| D
  GHCR -.->|misma imagen| P
```

Cada etapa es un job encadenado con `needs`, y cada job corre en un pod nuevo de `arc-runner-set`:

| Job | Qué hace |
|---|---|
| `init` | Checkout, calcula el nombre de la imagen (`ghcr.io/<owner>/<repo>` en minúsculas) y el tag (short sha), los expone como `outputs`; `npm ci` con caché de npm (`actions/setup-node`) |
| `test` | `npm ci` + `npm test --if-present`; `helm lint` y `helm template` del chart con los values de dev y de prod |
| `build` | `docker build` en el sidecar `dind` y `docker push` a GHCR con el tag del sha. Se construye **una sola vez**: la misma imagen se promueve a dev y a prod |
| `deploy-dev` | `azure/setup-kubectl` + `azure/setup-helm`, `helm upgrade --install ... --wait` en `k8s-lab-dev` y smoke test |
| `deploy-prod` | Igual que dev pero en `k8s-lab-prod`, con la imagen ya probada en dev. Espera la aprobación del environment `prod` |

| Evento | init | test | build | deploy-dev | deploy-prod |
|---|---|---|---|---|---|
| `pull_request` a `main` | ✔ | ✔ | — | — | — |
| `push` a `main` | ✔ | ✔ | ✔ | ✔ automático | ✔ con aprobación (si `prod` tiene required reviewers) |
| `push` de un tag `v*.*.*` | ✔ | ✔ | ✔ | ✔ | ✔ con aprobación |
| `workflow_dispatch` (a mano) | ✔ | ✔ | ✔ | ✔ | ✔ con aprobación |

| Credencial | Para qué | Dónde vive |
|---|---|---|
| `GITHUB_TOKEN` | `docker login` y `docker push` a GHCR | Lo genera GitHub en cada run. El workflow pide `contents: read` y, solo en `build`, `packages: write` |
| ServiceAccount `arc-deployer` | `helm` y `kubectl` en `k8s-lab-dev` y `k8s-lab-prod` | Token montado en el pod de runner. **No** hay kubeconfig en los secrets de GitHub |
| PAT `read:packages` (opcional) | Que el cluster baje la imagen si el package es privado | Secret `ghcr-pull` en cada namespace (ver [Pull de la imagen desde GHCR](#pull-de-la-imagen-desde-ghcr)) |

### El chart de la app

[`workflow-ejemplo/chart/`](workflow-ejemplo/chart/) convierte los manifiestos de [`04-kubernetes/k8s/`](../04-kubernetes/k8s/) en templates, con los mismos nombres (`web`, `valkey`, `web-config`, `web-gateway`):

| Archivo | Sale de | Qué se parametriza |
|---|---|---|
| `Chart.yaml` | — | Nombre `k8s-app`, versión del chart |
| `values.yaml` | Valores del lab 04 | `replicaCount`, `image.repository`, `image.tag`, `imagePullSecrets`, `config`, `resources`, `gateway.port` |
| `values-dev.yaml` | — | 1 réplica, mensaje `(dev)`, Gateway en el puerto `8081` |
| `values-prod.yaml` | — | 2 réplicas, más CPU y memoria, mensaje `(prod)`, Gateway en el puerto `8082` |
| `templates/configmap.yaml` | `01-configmap.yaml` | Las claves de `config` |
| `templates/valkey.yaml` | `02-valkey.yaml` | Imagen de Valkey |
| `templates/web.yaml` | `03-web.yaml` | Réplicas, imagen, recursos, pull secrets. Si cambia el ConfigMap, los pods se reemplazan |
| `templates/gateway.yaml` | `05-gateway.yaml` y `06-httproute.yaml` | Puerto y host |

El Namespace (`00`) y la GatewayClass (`04`) no están en el chart: son objetos de todo el cluster y el pipeline no tiene permisos sobre ellos. Cada ambiente usa otro puerto porque Docker Desktop publica cada Gateway como un LoadBalancer en `localhost`, y dos Gateways en el mismo puerto chocarían.

Probalo sin cluster, desde `05-github-actions-arc/workflow-ejemplo/`:

```bash
helm lint ./chart -f chart/values-dev.yaml --set image.tag=abc1234
helm template app ./chart -n k8s-lab-prod -f chart/values-prod.yaml --set image.tag=abc1234 | grep -E 'replicas:|image:|port: 808'
```

```text
1 chart(s) linted, 0 chart(s) failed
  replicas: 1
          image: valkey/valkey:9-alpine
  replicas: 2
          image: "ghcr.io/owner/repo:abc1234"
      port: 8082
```

`image.tag` es obligatorio: sin `--set image.tag=...` el render falla a propósito, para no desplegar una imagen indefinida.

### Cómo queda el repo de la app

Usá el **mismo repo privado** al que apunta el scale set (`GITHUB_CONFIG_URL`): los runners de repo solo atienden jobs de ese repo. Si preferís un repo nuevo, hacé `helm upgrade` del scale set con su URL y verificá que el PAT tenga acceso a él.

```text
<tu-repo>/
├── app/                          # copia de 04-kubernetes/app
│   ├── Dockerfile
│   ├── package.json              # + script "test" (Paso CI-4)
│   ├── package-lock.json         # generado en el Paso CI-4 (npm ci y la caché lo necesitan)
│   └── server.js
├── chart/                        # copia de 05-github-actions-arc/workflow-ejemplo/chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── values-dev.yaml
│   ├── values-prod.yaml
│   └── templates/
│       ├── _helpers.tpl
│       ├── configmap.yaml
│       ├── valkey.yaml
│       ├── web.yaml
│       └── gateway.yaml
└── .github/
    └── workflows/
        └── ci-cd.yml             # copia de 05-github-actions-arc/workflow-ejemplo/ci-cd.yml
```

### Paso CI-1 · Preparar el cluster

Envoy Gateway y la GatewayClass `envoy` del lab 04 tienen que estar instalados ([paso 6 del lab 04](../04-kubernetes/pasos/06-envoy-gateway.md) y `04-gatewayclass.yaml`):

```bash
kubectl get gatewayclass envoy
```

```text
NAME    CONTROLLER                                      ACCEPTED   AGE
envoy   gateway.envoyproxy.io/gatewayclass-controller   True       ...
```

### Paso CI-2 · Namespaces y permisos (RBAC)

[`rbac-deployer.yaml`](rbac-deployer.yaml) lo aplicás vos, una vez, con tu usuario de admin del cluster. Crea:

- los namespaces `k8s-lab-dev` y `k8s-lab-prod` (por eso el deploy no usa `--create-namespace` y el pipeline no necesita permisos de todo el cluster);
- la ServiceAccount `arc-deployer` en `arc-runners`;
- un Role y un RoleBinding **por namespace** con lo que necesita Helm: Secrets (Helm guarda cada release como un Secret), ConfigMaps, Services, Deployments, Gateways y HTTPRoutes, y lectura de ReplicaSets, Pods, logs y eventos para `--wait`.

Desde `05-github-actions-arc/`:

```bash
kubectl apply -f rbac-deployer.yaml
```

```text
namespace/k8s-lab-dev created
namespace/k8s-lab-prod created
serviceaccount/arc-deployer created
role.rbac.authorization.k8s.io/arc-deployer created
rolebinding.rbac.authorization.k8s.io/arc-deployer created
role.rbac.authorization.k8s.io/arc-deployer created
rolebinding.rbac.authorization.k8s.io/arc-deployer created
```

Verificá qué puede y qué no puede hacer:

```bash
SA=system:serviceaccount:arc-runners:arc-deployer
kubectl auth can-i create secrets -n k8s-lab-dev --as="$SA"        # yes
kubectl auth can-i patch deployments -n k8s-lab-prod --as="$SA"    # yes
kubectl auth can-i patch deployments -n k8s-lab --as="$SA"         # no
kubectl auth can-i create namespaces --as="$SA"                    # no
```

> ⚠ La misma ServiceAccount despliega en dev **y** en prod, y la usa **cualquier** job del repo que corra en `arc-runner-set` (también los de pull requests). Además, como Helm necesita Secrets, puede leer todos los Secrets de esos dos namespaces. Mejora opcional: dos scale sets (por ejemplo `arc-runner-set-dev` y `arc-runner-set-prod`), cada uno con su ServiceAccount y su Role, y `runs-on` distinto en cada job de deploy, para que un job de dev no pueda tocar prod.

### Paso CI-3 · Scale set con la ServiceAccount

En [`values.yaml`](values.yaml) descomentá el bloque `template` para que quede así:

```yaml
template:
  spec:
    serviceAccountName: arc-deployer
```

Y aplicalo (desde `05-github-actions-arc/`):

```bash
helm upgrade arc-runner-set \
    --namespace arc-runners \
    -f values.yaml \
    --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
    oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
```

El chart combina este `template.spec` con el de `containerMode.type: dind`: el pod de runner sigue teniendo `runner` y `dind`, y ahora usa `arc-deployer`. Si usás `--set` en vez de editar el archivo: `--set template.spec.serviceAccountName=arc-deployer`.

> El orden importa: primero `rbac-deployer.yaml`, después `helm upgrade`. Si la ServiceAccount no existe, el controller no puede crear los pods de runner y los jobs quedan en *Waiting for a runner*.

### Paso CI-4 · Armar el repo

Desde la raíz de **tu** repo privado (el mismo del paso 7):

```bash
LABS=/ruta/a/terraform-devops-labs
cp -R "$LABS/04-kubernetes/app" .
cp -R "$LABS/05-github-actions-arc/workflow-ejemplo/chart" .
mkdir -p .github/workflows
cp "$LABS/05-github-actions-arc/workflow-ejemplo/ci-cd.yml" .github/workflows/
```

La app del lab 04 no tiene dependencias ni script de test. `npm ci` y la caché de `actions/setup-node` necesitan un `package-lock.json`, y el job `test` corre `npm test --if-present` (si no hay script `test`, no hace nada). Agregá un test mínimo (chequea la sintaxis de `server.js`) y generá el lockfile:

```bash
cd app
npm pkg set scripts.test="node --check server.js"
npm install --package-lock-only
npm test
cd ..
```

```text
> k8s-app@1.0.0 test
> node --check server.js
```

No hace falta tocar la imagen en ningún manifiesto: el pipeline pasa `image.repository` e `image.tag` a Helm en cada deploy.

### Paso CI-5 · Environments `dev` y `prod`

En tu repo: **Settings › Environments › New environment**.

1. `dev`: crealo sin reglas. El deploy a dev es automático.
2. `prod`: crealo y marcá **Required reviewers** (agregate a vos). Opcional: en **Deployment branches and tags** elegí *Selected branches and tags* y agregá la rama `main` y el tag `v*.*.*`. **Save protection rules**.

> ⚠ **Disponibilidad según el plan** ([Managing environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)): con GitHub Free, los environments solo se configuran en repos **públicos**. En repos privados hace falta GitHub Pro, Team o Enterprise, y aun así los *required reviewers* en repos privados solo existen en Enterprise. Sin aprobación disponible, cambiá la condición de `deploy-prod` en `ci-cd.yml` por `if: startsWith(github.ref, 'refs/tags/v')`: prod se despliega solo cuando empujás un tag (`git tag v1.0.0 && git push origin v1.0.0`). Si referenciar un environment te da error en tu plan, sacá los bloques `environment:` de `deploy-dev` y `deploy-prod`: el pipeline funciona igual, sin aprobación.

### Paso CI-6 · Push y seguimiento

Si vas a usar un package privado, antes del push leé la [opción B](#pull-de-la-imagen-desde-ghcr). Después:

```bash
git add app chart .github/workflows/ci-cd.yml
git commit -m "ci: pipeline de build y deploy con ARC"
git push origin main
```

- En GitHub: **Actions › CI/CD app** › el run. Vas a ver `init → test → build → deploy-dev → deploy-prod`.
- Cuando `deploy-dev` termina, `deploy-prod` queda en *Waiting*: entrá al run, **Review deployments**, marcá `prod` y **Approve and deploy**.
- En una terminal, los pods de runner: `kubectl get pods -n arc-runners -w`.
- En otra, el rollout: `kubectl get pods -n k8s-lab-dev -w` (y después `-n k8s-lab-prod`).

Cuando el run termina en verde:

```bash
helm list -n k8s-lab-dev
helm list -n k8s-lab-prod
kubectl get deployment web -n k8s-lab-prod -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
curl http://web.localhost:8081      # dev
curl http://web.localhost:8082      # prod
```

```text
NAME  NAMESPACE     REVISION  UPDATED  STATUS    CHART          APP VERSION
app   k8s-lab-dev   1         ...      deployed  k8s-app-0.1.0  1.0
NAME  NAMESPACE     REVISION  UPDATED  STATUS    CHART          APP VERSION
app   k8s-lab-prod  1         ...      deployed  k8s-app-0.1.0  1.0
ghcr.io/<owner>/<repo>:3f9c2e1
{"mensaje":"Mi app en Kubernetes (dev)","version":"1.0","pod":"web-...","visitas":...}
{"mensaje":"Mi app en Kubernetes (prod)","version":"1.0","pod":"web-...","visitas":...}
```

Para probar el ciclo completo, cambiá algo en `app/server.js` o en `chart/values-dev.yaml`, hacé commit y push a `main`, y mirá cómo se reemplazan los pods.

### Pull de la imagen desde GHCR

Un package nuevo en GHCR es **privado** por defecto, y el nodo del cluster no tiene credenciales para bajarlo: los pods nuevos de `web` quedan en `ImagePullBackOff` y `helm --wait` vence. Hay dos salidas ([visibilidad de packages](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)):

**Opción A · Package público (recomendada solo para este lab local).** El package existe recién después del primer `build`, así que el primer `deploy-dev` puede fallar. Entonces: tu perfil de GitHub › **Packages** › el package › **Package settings** › **Change visibility** › *Public*, y en el run **Re-run failed jobs**. La imagen queda visible para cualquiera: no pongas nada sensible en ella.

**Opción B · Package privado con `imagePullSecret`.** Creá un **PAT classic** solo con el scope `read:packages` (GHCR no acepta fine-grained PATs) y guardalo en un Secret `docker-registry` en cada namespace, sin dejarlo en el historial:

```bash
read -s -p "PAT read:packages: " GHCR_PULL_TOKEN; echo
for NS in k8s-lab-dev k8s-lab-prod; do
  kubectl create secret docker-registry ghcr-pull \
      --namespace "$NS" \
      --docker-server=ghcr.io \
      --docker-username=<owner> \
      --docker-password="$GHCR_PULL_TOKEN"
done
unset GHCR_PULL_TOKEN
```

Y referencialo en `chart/values.yaml` de tu repo:

```yaml
imagePullSecrets:
  - name: ghcr-pull
```

Lo usa el kubelet al bajar la imagen. Detalle en [Pull an Image from a Private Registry](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/).

### Rollback

- **Con Helm** (rápido, desde tu terminal):

  ```bash
  helm history app -n k8s-lab-prod
  helm rollback app <REVISION> -n k8s-lab-prod --wait
  ```

- **Con el pipeline** (deja registro en GitHub): abrí en **Actions** el run del commit bueno y usá **Re-run jobs** sobre `deploy-prod` (GitHub permite re-ejecutar runs de los últimos 30 días). Vuelve a desplegar el tag de ese commit, que sigue en GHCR.

El próximo push a `main` vuelve a desplegar lo último. Para que el rollback quede fijo, revertí el commit (`git revert`) y empujalo.

## Verificación

- [ ] `kubectl get pods -n arc-systems` muestra el controller y el listener en `Running`.
- [ ] `helm list -A` muestra `arc` y `arc-runner-set` en `deployed`.
- [ ] El repo muestra `arc-runner-set` en **Settings › Actions › Runners**.
- [ ] El workflow **ARC demo** terminó en verde, incluido el job `docker` (`docker build` dentro del runner).
- [ ] Viste aparecer y desaparecer el pod de runner con `kubectl get pods -n arc-runners -w`.
- [ ] El token nunca quedó escrito en un archivo ni en el historial (`history | grep -i pat` no muestra el valor).
- [ ] (Pipeline) `kubectl auth can-i create secrets -n k8s-lab-dev --as=system:serviceaccount:arc-runners:arc-deployer` responde `yes` y `create namespaces` responde `no`.
- [ ] (Pipeline) En un pull request corren solo `init` y `test`.
- [ ] (Pipeline) En un push a `main`, el run de **CI/CD app** terminó en verde, con `deploy-prod` aprobado (o desplegado por tag).
- [ ] (Pipeline) `helm list` muestra `app` en `k8s-lab-dev` y `k8s-lab-prod`, y los dos usan la misma imagen `ghcr.io/<owner>/<repo>:<sha>`.

## Ejercicios opcionales

1. **Runner siempre listo.** Cambiá `minRunners: 1` en `values.yaml` y aplicalo:

   ```bash
   helm upgrade arc-runner-set \
       --namespace arc-runners \
       -f values.yaml \
       --set githubConfigUrl="${GITHUB_CONFIG_URL}" \
       oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set
   kubectl get pods -n arc-runners
   ```

   Tiene que quedar un pod de runner esperando aunque no haya jobs. Volvé a `0` al terminar.

2. **Límite de concurrencia.** Con `maxRunners: 1`, lanzá el workflow tres veces seguidas. Los jobs se ejecutan de a uno y el resto queda en cola.
3. **Otro nombre.** Descomentá `runnerScaleSetName: "mi-scale-set"`, hacé `helm upgrade` y cambiá `runs-on` en el workflow. Con el `runs-on` viejo, el job queda en *Waiting for a runner*.
4. **Desafío: el mismo despliegue con Terraform.** El provider [`hashicorp/helm`](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) instala charts con el recurso `helm_release`. Un punto de partida (no está incluido como archivo del lab; armalo en una carpeta aparte y no subas el `.tfstate`):

   ```hcl
   # Desafío: no forma parte del laboratorio. Provider hashicorp/helm ~> 3.0
   provider "helm" {
     kubernetes = {
       config_path    = "~/.kube/config"
       config_context = "docker-desktop"
     }
   }

   resource "helm_release" "arc" {
     name             = "arc"
     namespace        = "arc-systems"
     create_namespace = true
     repository       = "oci://ghcr.io/actions/actions-runner-controller-charts"
     chart            = "gha-runner-scale-set-controller"
   }

   resource "helm_release" "arc_runner_set" {
     name       = "arc-runner-set"
     namespace  = "arc-runners"
     repository = "oci://ghcr.io/actions/actions-runner-controller-charts"
     chart      = "gha-runner-scale-set"
     values     = [file("${path.module}/values.yaml")]

     set = [
       { name = "githubConfigUrl", value = var.github_config_url },
     ]

     depends_on = [helm_release.arc]
   }
   ```

   El `values.yaml` del lab ya incluye `containerMode.type: dind`, así que el runner tiene Docker también por este camino. El token **no** va en Terraform: el Secret `pre-defined-secret` se crea antes con `kubectl` (paso 4), así no termina en el `.tfstate`.

## Limpieza

Si armaste el [pipeline](#pipeline-completo-de-github-al-cluster), empezá por esto:

- Desinstalá la app de los dos ambientes:

  ```bash
  helm uninstall app -n k8s-lab-dev
  helm uninstall app -n k8s-lab-prod
  ```

- Borrá namespaces y permisos (incluye el Secret `ghcr-pull` si lo creaste): `kubectl delete -f rbac-deployer.yaml` (desde `05-github-actions-arc/`). Si usaste la opción B, revocá también ese PAT `read:packages`.
- Borrá la imagen: tu perfil de GitHub › **Packages** › el package › **Package settings** › **Delete this package**.
- Borrá los environments `dev` y `prod` en **Settings › Environments**, si los creaste.
- Volvé a comentar el bloque `template` en `values.yaml`.

El orden importa: **primero el scale set, después el controller**. Si borrás el controller primero, los recursos del scale set quedan con finalizers que nadie procesa y el namespace se traba en `Terminating`.

1. Desinstalar el scale set y esperar a que se vaya el listener:

   ```bash
   helm uninstall arc-runner-set -n arc-runners
   kubectl get pods -n arc-systems     # el pod ...-listener tiene que desaparecer
   kubectl get pods -n arc-runners     # No resources found
   ```

2. Desinstalar el controller:

   ```bash
   helm uninstall arc -n arc-systems
   ```

3. Borrar los namespaces (incluye el Secret `pre-defined-secret`):

   ```bash
   kubectl delete namespace arc-runners arc-systems
   ```

4. Verificar que no quedó nada:

   ```bash
   helm list -A
   kubectl get namespaces | grep arc     # sin resultados
   ```

   Las CRDs de ARC (`*.actions.github.com`) quedan instaladas, porque Helm no borra CRDs. Si querés sacarlas también:

   ```bash
   kubectl get crds -o name | grep actions.github.com | xargs kubectl delete
   ```

5. En GitHub:
   - Borrá `.github/workflows/arc-demo.yml` (y `ci-cd.yml`, si lo agregaste) de tu repo.
   - Revisá **Settings › Actions › Runners**: `arc-runner-set` ya no tiene que aparecer.
   - **Revocá el PAT**: Settings › Developer settings › Personal access tokens › tu token › *Delete*.

6. En la terminal:

   ```bash
   unset GITHUB_PAT GITHUB_CONFIG_URL INSTALLATION_NAME NAMESPACE
   ```

> `cleanup.sh` de la raíz del repo **no** cubre este laboratorio: la limpieza del lab 05 es manual.

## Problemas comunes

| Síntoma | Causa | Solución |
|---|---|---|
| Listener en `CrashLoopBackOff` o `Error` | PAT inválido, vencido o sin el permiso *Administration: Read and write*; o `githubConfigUrl` mal escrita | `kubectl logs -n arc-systems -l app.kubernetes.io/component=runner-scale-set-listener` y `kubectl logs -n arc-systems deployment/arc-gha-rs-controller`. Corregí el token (recreá el Secret) o la URL y hacé `helm upgrade` |
| No aparece ningún pod `...-listener` | El Secret no existe en `arc-runners` o tiene otra clave | `kubectl get secret pre-defined-secret -n arc-runners -o jsonpath='{.data}' \| grep -c github_token` tiene que dar `1`. Revisá los logs del controller |
| El runner no aparece en **Settings › Actions › Runners** | URL de otro repo, o el token no tiene acceso a ese repo | Revisá `helm get values arc-runner-set -n arc-runners` (la URL) y el *Repository access* del PAT |
| `Cannot connect to the Docker daemon at unix:///var/run/docker.sock` en el job `docker` | El scale set se instaló sin `containerMode.type=dind` | Aplicalo con `helm upgrade arc-runner-set -n arc-runners -f values.yaml --set githubConfigUrl="${GITHUB_CONFIG_URL}" oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set` y volvé a correr el workflow. Verificá con el `jsonpath` del paso 7 que el pod tenga `dind` |
| El pod de runner no arranca y el evento menciona `privileged` | El cluster no permite contenedores privilegiados (Pod Security `restricted`/`baseline` en el namespace) | En el cluster local, revisá las etiquetas `pod-security.kubernetes.io/*` de `arc-runners`; si no podés usar `privileged`, sacá `containerMode` (sin `docker build`) |
| El job queda en *Waiting for a runner* | `runs-on` distinto del nombre del scale set | `runs-on: arc-runner-set` tiene que coincidir con el release de Helm (o con `runnerScaleSetName`) |
| El pod de runner queda en `Pending` o `ImagePullBackOff` | Falta de recursos en el nodo o sin red para bajar `ghcr.io/actions/actions-runner` | `kubectl describe pod -n arc-runners <pod>`; dale más memoria a Docker Desktop o revisá la conexión |
| `Error: ... failed to authorize` / `unauthorized` al bajar el chart OCI | Credenciales viejas de `ghcr.io` guardadas en Helm | `helm registry logout ghcr.io` y reintentá (el chart es público) |
| `Error: ... unsupported protocol scheme "oci"` | Helm anterior a 3.8 | Actualizá Helm (`helm version` tiene que dar `v3.8` o superior) |
| `namespaces "arc-runners" not found` al crear el Secret | El namespace no existe todavía | `kubectl create namespace arc-runners` antes del Secret |
| El namespace queda en `Terminating` | Se desinstaló el controller antes que el scale set | Reinstalá el controller (paso 2), desinstalá `arc-runner-set` y recién después el controller |
| (Pipeline) Pods `web-...` en `ImagePullBackOff` y `helm upgrade --wait` vence (`context deadline exceeded`) | El package de GHCR es privado y el cluster no tiene credenciales, o el tag no existe | `kubectl describe pod -n k8s-lab-dev <pod>` muestra el error de pull. Hacé público el package o usá el `imagePullSecret` de la [opción B](#pull-de-la-imagen-desde-ghcr) y re-ejecutá el workflow |
| (Pipeline) `Error from server (Forbidden): ... "system:serviceaccount:arc-runners:arc-runner-set-gha-rs-no-permission" cannot ...` | El scale set no usa `arc-deployer` | Descomentá `template.spec.serviceAccountName` y hacé el `helm upgrade` del [Paso CI-3](#paso-ci-3--scale-set-con-la-serviceaccount) |
| (Pipeline) `Forbidden` con `system:serviceaccount:arc-runners:arc-deployer` (por ejemplo `cannot list resource "secrets"`) | Falta un permiso en el Role, el namespace no es `k8s-lab-dev`/`k8s-lab-prod`, o se agregó `--create-namespace` | Revisá `rbac-deployer.yaml` y `kubectl auth can-i <verbo> <recurso> -n k8s-lab-dev --as=system:serviceaccount:arc-runners:arc-deployer`. Los namespaces los crea `rbac-deployer.yaml`, no el pipeline |
| (Pipeline) `helm upgrade --wait` vence aunque la imagen baja bien | Los pods nuevos no pasan la `readinessProbe` (`/health`) o falta Valkey | `kubectl get pods -n k8s-lab-dev` y `kubectl logs -n k8s-lab-dev deployment/web`. Volvé a la versión anterior con `helm rollback` (ver [Rollback](#rollback)) |
| (Pipeline) `Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress` | Un deploy anterior se cortó a mitad de camino | `helm history app -n <ns>` y `helm rollback app <última revisión deployed> -n <ns>` |
| (Pipeline) `execution error ... image.tag es obligatorio` | Se corrió `helm template`/`upgrade` sin `--set image.tag=...` | Pasá el tag; en el pipeline sale del job `init` |
| (Pipeline) `npm ci` falla con `The npm ci command can only install with an existing package-lock.json`, o `setup-node` no encuentra el lockfile | Falta `app/package-lock.json` en el repo | Generalo con `npm install --package-lock-only` (Paso CI-4) y commitealo |
| (Pipeline) `deploy-prod` no pide aprobación | El environment `prod` no tiene *Required reviewers* o tu plan no los permite en repos privados | Ver [Paso CI-5](#paso-ci-5--environments-dev-y-prod); alternativa: desplegar prod solo con tags |
| (Pipeline) Gateway de dev o prod sin dirección / `curl` a `:8081` o `:8082` no responde | Otro servicio usa ese puerto en tu máquina | `kubectl get gateway -n k8s-lab-dev`; cambiá `gateway.port` en `values-dev.yaml` / `values-prod.yaml` |
| (Pipeline) `denied: permission_denied: write_package` en `docker push` | Falta `packages: write` en el workflow, o el package existe y no le dio acceso a este repo | Revisá `permissions:` en `ci-cd.yml`; en **Package settings › Manage Actions access** agregá el repo con rol *Write* |
| (Pipeline) `no matches for kind "Gateway"` | Envoy Gateway (y las CRDs de Gateway API) no está instalado | Instalalo como en el [paso 6 del lab 04](../04-kubernetes/pasos/06-envoy-gateway.md) |
| Los comandos afectan a otro cluster | Contexto de `kubectl` equivocado | `kubectl config use-context docker-desktop` |

Más casos en [Troubleshooting Actions Runner Controller errors](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/troubleshoot).

## Preguntas de repaso

1. **¿Qué valor va en `runs-on`?** El nombre del scale set, que por defecto es el nombre del release de Helm (`arc-runner-set`).
2. **¿Dónde corre el listener y dónde los runners?** El listener en el namespace del controller (`arc-systems`); los pods de runner en el namespace del scale set (`arc-runners`).
3. **¿Qué agrega `containerMode.type: dind`?** Un sidecar `dind` privilegiado con `dockerd` y `DOCKER_HOST` en el contenedor `runner`, para que los jobs puedan hacer `docker build`.
4. **¿Por qué conviene `githubConfigSecret=pre-defined-secret` en lugar de `githubConfigSecret.github_token=...`?** Porque el token no queda en los values del release de Helm ni en el historial del shell.
5. **¿Cómo se autentica el job de deploy contra el cluster?** Con el token de la ServiceAccount `arc-deployer` montado en el pod de runner. Como el runner corre dentro del cluster, no hace falta guardar un kubeconfig en GitHub.
6. **¿Qué significa "build once, promote"?** Que la imagen se construye una sola vez (tag = short sha) y esa misma imagen, ya probada en dev, es la que se despliega en prod.
7. **¿Por qué no se usan runners self-hosted en repos públicos?** Porque un pull request desde un fork podría ejecutar código arbitrario en tu cluster y tu red.
8. **¿En qué orden se desinstala?** Primero el scale set, después el controller, y al final se revoca el PAT.

## Fuentes

Contenido parafraseado de la documentación oficial de GitHub:

- [Quickstart for Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/quickstart)
- [Deploying runner scale sets with Actions Runner Controller](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/deploy-runner-scale-sets)
- [Authenticating ARC to the GitHub API](https://docs.github.com/en/actions/tutorials/use-actions-runner-controller/authenticate-to-the-api)
- [values.yaml del chart `gha-runner-scale-set`](https://github.com/actions/actions-runner-controller/blob/master/charts/gha-runner-scale-set/values.yaml)
- [Security hardening for self-hosted runners](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions#hardening-for-self-hosted-runners)
- [Working with the Container registry (GHCR)](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Configuring a package's access control and visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility)
- [Managing environments for deployment](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments)
- [azure/setup-kubectl](https://github.com/Azure/setup-kubectl) y [azure/setup-helm](https://github.com/Azure/setup-helm)
- [Kubernetes: Using RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Terraform: recurso `helm_release`](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release)
