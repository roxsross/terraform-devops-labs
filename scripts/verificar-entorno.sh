#!/usr/bin/env bash
# Verifica que el entorno esté listo para la clase de CI/CD con ARC.
ok()   { printf "  \033[32m✔\033[0m %s\n" "$1"; }
fail() { printf "  \033[31m✘\033[0m %s\n" "$1"; ERR=1; }
ERR=0
echo "Verificando el entorno..."

command -v git     >/dev/null && ok "git instalado"     || fail "git no está instalado"
command -v node    >/dev/null && ok "node $(node --version)" || fail "Node.js no está instalado"
command -v docker  >/dev/null && ok "docker instalado"  || fail "docker no está instalado"
docker info >/dev/null 2>&1   && ok "Docker está corriendo" || fail "Docker no responde: abrí Docker Desktop"
command -v kubectl >/dev/null && ok "kubectl instalado" || fail "kubectl no está instalado"
command -v helm    >/dev/null && ok "helm $(helm version --short 2>/dev/null)" || fail "helm no está instalado"

CTX=$(kubectl config current-context 2>/dev/null)
[ "$CTX" = "docker-desktop" ] && ok "contexto: docker-desktop" \
  || fail "contexto actual: '${CTX:-ninguno}'. Ejecutá: kubectl config use-context docker-desktop"
kubectl get nodes 2>/dev/null | grep -q " Ready" && ok "hay un nodo en Ready" \
  || fail "ningún nodo en Ready: activá Kubernetes en Docker Desktop"

echo
[ $ERR -eq 0 ] && echo "Todo listo." || echo "Hay algo para revisar antes de empezar."
exit $ERR
