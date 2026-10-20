#!/usr/bin/env bash
#
# Herramienta unificada para la API:
#   1) Probar la API (prueba CRUD completa con verificación de códigos HTTP)
#   2) Cargar datos de ejemplo
#
# El endpoint se puede pasar como argumento, por la variable API_URL,
# o se pide por teclado. Si existe estado de Terraform, se intenta tomar
# de 'terraform output -raw api_url'.
#
# Uso:
#   ./api.sh                         # menú interactivo, pide la URL
#   ./api.sh https://xxxx            # usa esa URL, muestra el menú
#   ./api.sh https://xxxx test       # prueba la API sin menú
#   ./api.sh https://xxxx cargar     # carga datos sin menú
#   API_URL=https://xxxx ./api.sh
#
set -euo pipefail

# ---- Resolver la URL de la API -------------------------------------------
API_URL="${1:-${API_URL:-}}"

if [[ -z "$API_URL" ]] && command -v terraform >/dev/null 2>&1; then
  API_URL="$(terraform output -raw api_url 2>/dev/null || true)"
fi

# Solo se pide por teclado en modo menú; con acción (test/cargar) se falla abajo.
if [[ -z "$API_URL" && -z "${2:-}" ]]; then
  read -r -p "URL de la API: " API_URL
fi

API_URL="${API_URL%/}" # quitar barra final

if [[ -z "$API_URL" ]]; then
  echo "ERROR: no se indicó ninguna URL." >&2
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
