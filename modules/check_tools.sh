# shellcheck shell=bash

check_tools_handler() {
  local deps=(docker kind fzf dialog)
  local missing=0
  for dep in "${deps[@]}"; do
    if command -v "$dep" >/dev/null 2>&1; then
      log_info "Ferramenta encontrada: $dep"
    else
      log_error "Ferramenta não encontrada: $dep"
      missing=1
    fi
  done
  return "$missing"
}

register_cmd "check-tools" "Valida dependências básicas" "check_tools_handler" "diagnostico"

