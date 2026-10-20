#!/usr/bin/env bash
#
# Herramienta para la API desplegada en MiniStack (emulador local).
#   1) Probar la API (CRUD completo con verificación de códigos HTTP)
#   2) Cargar datos de ejemplo
#
# A diferencia de AWS real, la URL que reporta API Gateway en MiniStack (output
# api_url) NO suele ser accesible desde el host. La invocación se hace contra el
# endpoint local usando el api_id. Este script construye esa URL automáticamente.
#
# Resolución de la URL (en este orden):
#   1. Primer argumento, si es una URL completa de invocación.
#   2. Variable API_URL.
#   3. Se arma a partir de 'terraform output -raw api_id' + MINISTACK_ENDPOINT
#      (ejecutá el script desde la carpeta del laboratorio). Se prueban estos
#      formatos y se usa el primero que responda HTTP 200 a GET /items:
#        a. $MINISTACK_ENDPOINT/_aws/execute-api/<api_id>          (stage $default)
#        b. $MINISTACK_ENDPOINT/_aws/execute-api/<api_id>/<STAGE>
#        c. http://<api_id>.execute-api.localhost:<PUERTO>
#        d. $MINISTACK_ENDPOINT/restapis/<api_id>/<STAGE>/_user_request_
#      Si ninguno responde, se usa el primero y se avisa.
#
# Uso:
#   ./api.sh                                                    # arma la URL desde terraform output
#   ./api.sh http://localhost:4566/_aws/execute-api/<api_id>    # usa esa URL de invocación directa
#   ./api.sh "" test                                            # probar sin menú
#   ./api.sh "" cargar                                          # cargar datos sin menú
#   MINISTACK_ENDPOINT=http://localhost:4566 ./api.sh           # otro endpoint de MiniStack
#   STAGE=dev ./api.sh                                          # otro stage (default: $default)
#
set -euo pipefail

MINISTACK_ENDPOINT="${MINISTACK_ENDPOINT:-http://localhost:4566}"
MINISTACK_ENDPOINT="${MINISTACK_ENDPOINT%/}"
STAGE="${STAGE:-\$default}"

# ---- Resolver la URL base de invocación ----------------------------------
API_URL="${1:-${API_URL:-}}"

build_url_from_terraform() {
  command -v terraform >/dev/null 2>&1 || return 1
  local api_id
  api_id="$(terraform output -raw api_id 2>/dev/null || true)"
  [[ -z "$api_id" ]] && return 1

  # Puerto del endpoint (para el formato por subdominio). Default: 4566.
  local port="4566"
  if [[ "$MINISTACK_ENDPOINT" =~ :([0-9]+)$ ]]; then
    port="${BASH_REMATCH[1]}"
  fi

  # Formatos de invocación de MiniStack. El stage $default de una HTTP API se
  # sirve sin segmento de stage. Se prueban hasta que uno responda 200 a GET /items.
  local candidatos=()
  if [[ "$STAGE" == "\$default" ]]; then
    candidatos+=("$MINISTACK_ENDPOINT/_aws/execute-api/$api_id")
  fi
  candidatos+=(
    "$MINISTACK_ENDPOINT/_aws/execute-api/$api_id/$STAGE"
    "http://$api_id.execute-api.localhost:$port"
    "$MINISTACK_ENDPOINT/restapis/$api_id/$STAGE/_user_request_"
  )

  local base code
  for base in "${candidatos[@]}"; do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$base/items" 2>/dev/null || true)"
    if [[ "$code" == "200" ]]; then
      echo "$base"
      return 0
    fi
  done

  # Ninguno respondió 200: devolver el primero como mejor intento.
  echo "AVISO: ningún formato de URL respondió 200 en GET /items; se usa ${candidatos[0]}" >&2
  echo "${candidatos[0]}"
  return 0
}

if [[ -z "$API_URL" ]]; then
  echo "==> Resolviendo URL de invocación desde terraform (api_id)..." >&2
  API_URL="$(build_url_from_terraform || true)"
fi

# Solo se pide por teclado en modo menú; con acción (test/cargar) se falla abajo.
if [[ -z "$API_URL" && -z "${2:-}" ]]; then
  read -r -p "URL de invocación de la API: " API_URL
fi

API_URL="${API_URL%/}"

if [[ -z "$API_URL" ]]; then
  echo "ERROR: no se pudo determinar la URL de la API." >&2
  echo "Pasala como argumento o exportá API_URL." >&2
  exit 1
fi

# ---- Helper: curl con verificación del código HTTP esperado --------------
# check <descripcion> <esperado> <metodo> <ruta> [datos-json]
check() {
  local desc="$1" expected="$2" method="$3" path="$4" data="${5:-}"
  local args=(-s -o /tmp/api_body.$$ -w '%{http_code}' -X "$method" "$API_URL$path")
  [[ -n "$data" ]] && args+=(-H 'Content-Type: application/json' -d "$data")

  local code body
  # Si curl no puede conectar imprime 000: se reporta como FAIL sin abortar el script.
  code="$(curl "${args[@]}" || true)"
  body="$(cat /tmp/api_body.$$ 2>/dev/null || true)"
  rm -f /tmp/api_body.$$

  if [[ "$code" == "$expected" ]]; then
    printf '  [OK ] %-28s -> %s\n' "$desc" "$code"
  else
    printf '  [FAIL] %-27s -> %s (esperado %s)\n' "$desc" "$code" "$expected"
    FAIL=$((FAIL + 1))
  fi
  if [[ -n "$body" ]]; then
    printf '         %s\n' "$body"
  fi
}

# ---- Opción 1: probar la API (CRUD completo) -----------------------------
probar_api() {
  local item_id
  item_id="test-$(date +%s)"
  FAIL=0

  echo "==> Probando API: $API_URL"
  echo "==> ID de prueba: $item_id"
  echo

  echo "== PUT /items (crear) =="
  check "crear producto" 200 PUT /items \
    "{\"id\":\"$item_id\",\"name\":\"Teclado mecánico\",\"price\":150}"
  echo

  echo "== GET /items (listar) =="
  check "listar productos" 200 GET /items
  echo

  echo "== GET /items/{id} (leer) =="
  check "leer producto creado" 200 GET "/items/$item_id"
  echo

  echo "== GET /items/{id} inexistente =="
  check "leer id inexistente" 404 GET "/items/no-existe-xyz"
  echo

  echo "== PUT /items inválido (sin price) =="
  check "crear sin campos" 400 PUT /items "{\"id\":\"$item_id\"}"
  echo

  echo "== DELETE /items/{id} =="
  check "eliminar producto" 200 DELETE "/items/$item_id"
  echo

  echo "== GET /items/{id} tras borrar =="
  check "leer tras eliminar" 404 GET "/items/$item_id"
  echo

  echo "========================================"
  if [[ "$FAIL" -eq 0 ]]; then
    echo "  Resultado: TODO OK"
  else
    echo "  Resultado: $FAIL caso(s) con FAIL"
  fi
  echo "========================================"
  return "$FAIL"
}

# ---- Opción 2: cargar datos de ejemplo -----------------------------------
cargar_datos() {
  # id | name | price
  local productos=(
    "1|Teclado mecánico|150"
    "2|Mouse inalámbrico|80"
    "3|Monitor 27 pulgadas|320"
    "4|Auriculares|120"
    "5|Webcam HD|65"
  )

  echo "==> Cargando productos en $API_URL/items"
  echo

  local p id name price
  for p in "${productos[@]}"; do
    IFS='|' read -r id name price <<< "$p"
    echo "-> $id: $name (\$$price)"
    curl -s -X PUT "$API_URL/items" \
      -H 'Content-Type: application/json' \
      -d "{\"id\":\"$id\",\"name\":\"$name\",\"price\":$price}"
    echo
  done

  echo
  echo "==> Verificando con GET /items:"
  curl -s "$API_URL/items"
  echo
}

# ---- Menú / despacho -----------------------------------------------------
accion="${2:-}"

run_opcion() {
  case "$1" in
    1|test|probar)  probar_api ;;
    2|cargar|load)  cargar_datos ;;
    *) echo "Opción no válida: $1" >&2; return 1 ;;
  esac
}

if [[ -n "$accion" ]]; then
  run_opcion "$accion"
  exit $?
fi

echo
echo "API: $API_URL"
echo "¿Qué querés hacer?"
echo "  1) Probar la API (CRUD completo)"
echo "  2) Cargar datos de ejemplo"
echo
read -r -p "Opción [1-2]: " opcion
echo
run_opcion "$opcion"
