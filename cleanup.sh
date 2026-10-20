#!/usr/bin/env bash
#
# cleanup.sh — Limpieza segura de los laboratorios de Terraform.
#
# Para cada laboratorio:
#   1. Si el terraform.tfstate todavía tiene recursos, ejecuta 'terraform destroy'
#      ANTES de borrar nada (así no quedan recursos huérfanos ni costos en AWS).
#   2. Borra los archivos generados: .terraform/, lambda.zip, planes, crash.log.
#   3. Borra terraform.tfstate y terraform.tfstate.backup SOLO si el state quedó vacío.
#
# Nunca toca terraform.tfvars, los *.example ni aws-credentials.sh.
# .terraform.lock.hcl se conserva (se versiona) salvo que uses --purge-locks.
# Trabaja siempre sobre la carpeta donde está este script, no sobre el directorio actual.
#
# Ejecutá './cleanup.sh --help' para ver las opciones.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_LABS=(01-terraform-docker 02-terraform-aws-ministack 03-terraform-aws-real)
MINISTACK_ENDPOINT="${MINISTACK_ENDPOINT:-http://localhost:4566}"
MINISTACK_ENDPOINT="${MINISTACK_ENDPOINT%/}"

DRY_RUN=0
ASSUME_YES=0
NO_DESTROY=0
PURGE_LOCKS=0
SELECTED=()
SUMMARY=()
FINAL_RC=0

usage() {
  cat <<'EOF'
Uso: ./cleanup.sh [opciones]

Limpia los laboratorios de Terraform de este repositorio. Si un laboratorio
todavía tiene recursos en su terraform.tfstate, primero ejecuta terraform destroy.

Opciones:
  -n, --dry-run      Muestra lo que haría, sin borrar ni destruir nada
  -y, --yes          No pide confirmación general (el destroy del lab 03 SIEMPRE pide "yes")
      --no-destroy   No ejecuta terraform destroy; conserva los tfstate que todavía tengan recursos
      --purge-locks  Borra también .terraform.lock.hcl
      --lab NN       Limita a un lab: 01, 02 o 03 (se puede repetir)
  -h, --help         Muestra esta ayuda

Nunca borra terraform.tfvars, *.example ni aws-credentials.sh.
No apaga MiniStack: hacelo con 'docker rm -f ministack'.

Ejemplos:
  ./cleanup.sh --dry-run            # ver qué haría
  ./cleanup.sh --lab 01             # limpiar solo el laboratorio 01
  ./cleanup.sh --yes --no-destroy   # borrar solo archivos generados, sin destroy
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

# Ejecuta un comando, o solo lo muestra en modo --dry-run.
run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

# Pregunta s/N. Con --yes responde que sí sin preguntar.
confirm() {
  local ans=""
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    return 0
  fi
  read -r -p "$1 [y/N]: " ans || true
  case "$ans" in
    y | Y | yes | s | S | si | sí) return 0 ;;
    *) return 1 ;;
  esac
}

# Ejecuta un comando con límite de tiempo (evita cuelgues si Docker no responde).
with_timeout() {
  local secs="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
  else
    "$@"
  fi
}

docker_ok() {
  command -v docker >/dev/null 2>&1 && with_timeout 15 docker info >/dev/null 2>&1
}

add_lab() {
  local lab
  case "$1" in
    1 | 01 | 01-terraform-docker) lab="01-terraform-docker" ;;
    2 | 02 | 02-terraform-aws-ministack) lab="02-terraform-aws-ministack" ;;
    3 | 03 | 03-terraform-aws-real) lab="03-terraform-aws-real" ;;
    *) die "laboratorio inválido: '$1' (usá 01, 02 o 03)" ;;
  esac
  local s
  for s in ${SELECTED[@]+"${SELECTED[@]}"}; do
    [[ "$s" == "$lab" ]] && return 0
  done
  SELECTED+=("$lab")
}

# ---- Argumentos -------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --no-destroy) NO_DESTROY=1 ;;
    --purge-locks) PURGE_LOCKS=1 ;;
    --lab)
      [[ $# -ge 2 ]] || die "--lab necesita un valor: 01, 02 o 03"
      add_lab "$2"
      shift
      ;;
    --lab=*) add_lab "${1#--lab=}" ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Opción desconocida: $1" >&2
      echo >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

# ---- Guarda: tiene que ser la raíz del repositorio -------------------------
for lab in "${ALL_LABS[@]}"; do
  [[ -d "$ROOT/$lab" ]] || die "no encuentro '$ROOT/$lab'. Este script tiene que estar en la raíz del repositorio terraform-devops-labs."
done

if [[ ${#SELECTED[@]} -gt 0 ]]; then
  LABS=("${SELECTED[@]}")
else
  LABS=("${ALL_LABS[@]}")
fi

HAS_TERRAFORM=0
command -v terraform >/dev/null 2>&1 && HAS_TERRAFORM=1

# ---- Resumen inicial ---------------------------------------------------------
echo "🧹 Limpieza de laboratorios de Terraform"
echo "   Repositorio: $ROOT"
echo "   Laboratorios: ${LABS[*]}"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "   Modo: dry-run (no se borra ni se destruye nada)"
fi
if [[ "$NO_DESTROY" -eq 1 ]]; then
  echo "   terraform destroy: NO (--no-destroy)"
else
  echo "   terraform destroy: sí, en los labs cuyo state tenga recursos"
fi
if [[ "$PURGE_LOCKS" -eq 1 ]]; then
  echo "   .terraform.lock.hcl: se borra (--purge-locks)"
else
  echo "   .terraform.lock.hcl: se conserva"
fi
echo

if [[ "$DRY_RUN" -eq 0 && "$ASSUME_YES" -eq 0 ]]; then
  if ! confirm "¿Continuar?"; then
    echo "Cancelado. No se modificó nada."
    exit 0
  fi
  echo
fi

# ---- Funciones por laboratorio ----------------------------------------------

# Cuenta las instancias de recursos administrados leyendo el JSON del state,
# sin necesitar .terraform/ (sirve en el reintento, cuando ya se borró).
count_state_resources() {
  local file="$1"
  if command -v jq >/dev/null 2>&1; then
    jq '[.resources[]? | select(.mode == "managed") | .instances[]?] | length' "$file" 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, sys
s = json.load(open(sys.argv[1]))
print(sum(len(r.get("instances", [])) for r in s.get("resources", []) if r.get("mode") == "managed"))' "$file" 2>/dev/null && return 0
  fi
  return 1
}

# Deja en STATE_STATUS: sin_state | vacio | con_recursos | ilegible
# y en STATE_ERR el motivo cuando es ilegible.
state_status() {
  local dir="$1" out="" count=""
  STATE_STATUS="" STATE_ERR=""
  if [[ ! -f "$dir/terraform.tfstate" ]]; then
    STATE_STATUS="sin_state"
    return 0
  fi
  if [[ "$HAS_TERRAFORM" -eq 0 ]]; then
    STATE_STATUS="ilegible"
    STATE_ERR="no encuentro terraform en el PATH"
    return 0
  fi

  # Sin .terraform/ 'terraform state list' falla (faltan providers): leo el JSON.
  # Si no se puede leer el JSON, ejecuto terraform init (salvo en dry-run).
  if [[ ! -d "$dir/.terraform" ]]; then
    if count="$(count_state_resources "$dir/terraform.tfstate")" && [[ "$count" =~ ^[0-9]+$ ]]; then
      if [[ "$count" -eq 0 ]]; then STATE_STATUS="vacio"; else STATE_STATUS="con_recursos"; fi
      return 0
    fi
    if [[ "$DRY_RUN" -eq 1 ]]; then
      STATE_STATUS="ilegible"
      STATE_ERR="falta .terraform/ y no pude leer el JSON del state (¿no hay jq ni python3, o el archivo está dañado?); ejecutá 'terraform -chdir=$dir init'"
      return 0
    fi
    echo "   No hay .terraform/: ejecuto terraform init para leer el state."
    if ! out="$(terraform -chdir="$dir" init -input=false -no-color 2>&1)"; then
      STATE_STATUS="ilegible"
      STATE_ERR="terraform init falló: $(printf '%s\n' "$out" | grep -m 1 -i 'error' || printf '%s\n' "$out" | tail -n 1)"
      return 0
    fi
  fi

  if ! out="$(terraform -chdir="$dir" state list -no-color 2>&1)"; then
    STATE_STATUS="ilegible"
    STATE_ERR="$(printf '%s\n' "$out" | grep -m 1 -i 'error' || printf '%s\n' "$out" | tail -n 1)"
    STATE_ERR="$STATE_ERR. Probá 'terraform -chdir=$dir init'"
    return 0
  fi
  if [[ -z "$out" ]]; then
    STATE_STATUS="vacio"
  else
    STATE_STATUS="con_recursos"
  fi
}

# Verifica que se pueda destruir el lab (Docker, MiniStack o credenciales AWS).
destroy_prereqs_ok() {
  case "$1" in
    01-terraform-docker)
      if ! docker_ok; then
        echo "   ⚠️  Docker no responde ('docker info' falló). Levantá Docker y volvé a ejecutar."
        return 1
      fi
      ;;
    02-terraform-aws-ministack)
      if ! curl -sf --max-time 5 "$MINISTACK_ENDPOINT/_ministack/health" >/dev/null 2>&1; then
        echo "   ⚠️  MiniStack no responde en $MINISTACK_ENDPOINT/_ministack/health."
        echo "      Levantalo (docker start ministack) y volvé a ejecutar."
        return 1
      fi
      ;;
    03-terraform-aws-real)
      if ! command -v aws >/dev/null 2>&1; then
        echo "   ⚠️  No encuentro AWS CLI ('aws'). Instalala para verificar tus credenciales."
        return 1
      fi
      if ! with_timeout 30 aws sts get-caller-identity >/dev/null 2>&1; then
        echo "   ⚠️  'aws sts get-caller-identity' falló."
        echo "      Cargá credenciales con: source aws-credentials.sh (desde 03-terraform-aws-real)"
        return 1
      fi
      ;;
  esac
  return 0
}

# Ejecuta terraform destroy. Devuelve 0 si terminó bien.
destroy_lab() {
  local lab="$1" dir="$ROOT/$1"
  local args=(-chdir="$dir" destroy)

  if [[ ! -d "$dir/.terraform" ]]; then
    echo "   No hay .terraform/: ejecuto terraform init antes del destroy."
    run terraform -chdir="$dir" init -input=false || return 1
  fi

  if [[ "$lab" == "03-terraform-aws-real" ]]; then
    echo "   AWS real: terraform destroy es SIEMPRE interactivo. Revisá el plan y escribí 'yes'."
  elif [[ "$ASSUME_YES" -eq 1 ]]; then
    args+=(-auto-approve)
  fi

  run terraform "${args[@]}"
}

# Lab 01: contenedor que quedó vivo sin estar en el state.
check_orphan_container() {
  local dir="$ROOT/01-terraform-docker" name="web-terraform" from_tfvars=""
  if [[ -f "$dir/terraform.tfvars" ]]; then
    from_tfvars="$(sed -nE 's/^[[:space:]]*container_name[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/p' "$dir/terraform.tfvars" | head -n 1)"
  fi
  [[ -n "$from_tfvars" ]] && name="$from_tfvars"
  if [[ ! "$name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]]; then
    echo "   ⚠️  container_name inválido en terraform.tfvars; no reviso contenedores."
    return 0
  fi

  if ! docker_ok; then
    echo "   Docker no responde: no reviso si quedó el contenedor '$name'."
    return 0
  fi

  local found
  found="$(with_timeout 15 docker ps -a --filter "name=^/${name}$" --format '{{.Names}}' 2>/dev/null || true)"
  [[ -z "$found" ]] && return 0

  echo "   Encontré el contenedor '$name', que no está en el state de Terraform."
  if [[ "$NO_DESTROY" -eq 1 ]]; then
    echo "   Se conserva (--no-destroy). Para borrarlo: docker rm -f $name"
    return 0
  fi
  if [[ "$DRY_RUN" -eq 1 ]] || confirm "   ¿Eliminarlo con 'docker rm -f $name'?"; then
    run docker rm -f "$name" || {
      echo "   ⚠️  No pude eliminar el contenedor '$name'."
      FINAL_RC=1
    }
  else
    echo "   Se conserva el contenedor '$name'."
  fi
}

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    [[ "$DRY_RUN" -eq 0 ]] && echo "   Borrando ${path#"$ROOT"/}"
    run rm -rf -- "$path"
  fi
}

clean_local_files() {
  local dir="$1" f
  remove_path "$dir/.terraform"
  remove_path "$dir/lambda.zip"
  remove_path "$dir/tfplan"
  remove_path "$dir/crash.log"
  remove_path "$dir/.terraform.tfstate.lock.info"
  for f in "$dir"/*.tfplan; do
    [[ -e "$f" ]] && remove_path "$f"
  done
  if [[ "$PURGE_LOCKS" -eq 1 ]]; then
    remove_path "$dir/.terraform.lock.hcl"
  fi
}

remove_state_files() {
  local dir="$1"
  remove_path "$dir/terraform.tfstate"
  remove_path "$dir/terraform.tfstate.backup"
}

# ---- Proceso principal -------------------------------------------------------
for lab in "${LABS[@]}"; do
  dir="$ROOT/$lab"
  echo "==> $lab"

  state_status "$dir"
  status="$STATE_STATUS"
  result=""
  state_removable=0

  case "$status" in
    sin_state)
      state_removable=1
      ;;
    vacio)
      echo "   terraform.tfstate sin recursos."
      state_removable=1
      ;;
    ilegible)
      echo "   ⚠️  No pude leer terraform.tfstate: $STATE_ERR"
      echo "      Se conserva el state (puede tener recursos sin destruir)."
      result="conservado (state ilegible)"
      FINAL_RC=1
      ;;
    con_recursos)
      if [[ "$NO_DESTROY" -eq 1 ]]; then
        echo "   El state tiene recursos y usaste --no-destroy: se conserva el state."
        result="conservado (--no-destroy, con recursos)"
      elif ! destroy_prereqs_ok "$lab"; then
        echo "   Se conserva el state para poder destruir más tarde."
        result="conservado (no se pudo destruir: falta prerrequisito)"
        FINAL_RC=1
      else
        echo "   El state tiene recursos: ejecuto terraform destroy."
        if destroy_lab "$lab"; then
          if [[ "$DRY_RUN" -eq 1 ]]; then
            result="se destruiría (dry-run)"
          else
            result="destruido"
          fi
          state_removable=1
        else
          echo "   ❌ terraform destroy falló. NO se borra el state."
          result="conservado (destroy falló)"
          FINAL_RC=1
        fi
      fi
      ;;
  esac

  if [[ "$lab" == "01-terraform-docker" && "$state_removable" -eq 1 ]]; then
    check_orphan_container
  fi

  clean_local_files "$dir"
  if [[ "$state_removable" -eq 1 ]]; then
    remove_state_files "$dir"
  fi

  [[ -z "$result" ]] && result="limpio"
  SUMMARY+=("$lab: $result")
  echo
done

# ---- Resumen final -----------------------------------------------------------
echo "========================================"
echo " Resumen"
for line in "${SUMMARY[@]}"; do
  echo "   - $line"
done
echo "========================================"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "dry-run: no se modificó nada."
fi
echo "Tip: este script no apaga MiniStack. Para hacerlo: docker rm -f ministack"

if [[ "$FINAL_RC" -eq 0 ]]; then
  echo "✅ Limpieza completada."
else
  echo "⚠️  Limpieza terminada con advertencias: revisá los mensajes de arriba."
fi
exit "$FINAL_RC"
