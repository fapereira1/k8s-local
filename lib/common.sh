# shellcheck shell=bash

# Estilo
bold()   { printf '\033[1m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }
green()  { printf '\033[32m%s\033[0m' "$*"; }
red()    { printf '\033[31m%s\033[0m' "$*"; }
yellow() { printf '\033[33m%s\033[0m' "$*"; }

# Logs
log_info()  { printf "%s %s\n" "$(green "[OK]")" "$*"; }
log_warn()  { printf "%s %s\n" "$(yellow "[! ]")" "$*"; }
log_error() { printf "%s %s\n" "$(red "[ERRO]")" "$*"; }

# Requisitos
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log_error "Comando requerido não encontrado: $1"
    exit 127
  }
}
