# shellcheck shell=bash

# ---------------------------- Estado e Registro ------------------------------

# Arrays associativos (bash 4+)
declare -Ag __REGISTRY=()      # nome -> função
declare -Ag __DESCRIPTIONS=()  # nome -> descrição
declare -Ag __GROUPS=()        # nome -> grupo (opcional)

register_cmd() {
  # uso: register_cmd <nome> "<descrição>" <handler_func> [grupo]
  local name desc handler group
  name="$1"; desc="$2"; handler="$3"; group="${4:-}"

  if [[ -z "$name" || -z "$desc" || -z "$handler" ]]; then
    log_error "register_cmd: parâmetros insuficientes"
    return 1
  fi
  if ! declare -F "$handler" >/dev/null 2>&1; then
    log_error "Função handler não encontrada: $handler"
    return 1
  fi

  __REGISTRY["$name"]="$handler"
  __DESCRIPTIONS["$name"]="$desc"
  __GROUPS["$name"]="$group"
}

registry_has() {
  local name="$1"
  [[ -n "${__REGISTRY[$name]+set}" ]]
}

run_command() {
  local name="$1"; shift || true
  local fn="${__REGISTRY[$name]}"
  if [[ -z "${fn:-}" ]]; then
    log_error "Comando não registrado: $name"
    return 1
  fi
  "$fn" "$@"
}

# ----------------------------- Listagem/Ordenação ---------------------------

all_commands() {
  if locale -a 2>/dev/null | grep -qiE '^pt_BR\.utf-?8$'; then
    LC_ALL=pt_BR.UTF-8 printf "%s\n" "${!__REGISTRY[@]}" | sort -f
  else
    printf "%s\n" "${!__REGISTRY[@]}" | sort -f
  fi
}

longest_name_len() {
  local max=0 n
  for n in "${!__REGISTRY[@]}"; do
    ((${#n} > max)) && max=${#n}
  done
  printf '%d\n' "$max"
}

# ------------------------------ Helpers UI ----------------------------------

__unicode_ok() { [[ "${LANG:-}" =~ UTF-8|utf-8 ]]; }

__dialog_bin() {
  if command -v dialog >/dev/null 2>&1; then
    echo "dialog"
  elif command -v whiptail >/dev/null 2>&1; then
    echo "whiptail"
  else
    echo ""
  fi
}

# Caixa estilo “Clipper”
draw_box() {
  local w="$1" title="${2:-}"
  local tl tr bl br h v
  if __unicode_ok; then
    tl="┌"; tr="┐"; bl="└"; br="┘"; h="─"; v="│"
  else
    tl="+"; tr="+"; bl="+"; br="+"; h="-"; v="|"
  fi
  printf "%s" "$tl"; printf "%*s" "$((w-2))" "" | tr ' ' "$h"; printf "%s\n" "$tr"
  if [[ -n "$title" ]]; then
    local line=" $title "
    if ((${#line} > w-2)); then line="${line:0:$((w-5))}..."; fi
    local pad=$(( (w-2 - ${#line}) / 2 ))
    local extra=$(( (w-2 - ${#line}) - pad ))
    printf "%s%*s%s%*s%s\n" "$v" "$pad" "" "$line" "$extra" "" "$v"
    printf "%s" "$v"; printf "%*s" "$((w-2))" "" | tr ' ' "$h"; printf "%s\n" "$v"
  fi
  echo "__BOX_FOOTER__ $w $bl $br $h $v"
}

close_box() {
  local w="$1" bl="$2" br="$3" h="$4"
  printf "%s" "$bl"; printf "%*s" "$((w-2))" "" | tr ' ' "$h"; printf "%s\n" "$br"
}

# Pequena função utilitária para “Pressione tecla…”
_pause_for_key() {
  # -n1: uma tecla; -s: silencioso; -r: raw (não interpreta \)
  read -n1 -s -r -p "Pressione qualquer tecla para voltar ao menu..." _ || true
  echo
}

# ------------------------------ Render: dialog -------------------------------

show_menu_dialog() {
  local bin title backtitle height width menu_height
  bin="$(__dialog_bin)"
  if [[ -z "$bin" ]]; then
    log_warn "dialog/whiptail não encontrados; caindo no menu padrão."
    return 2
  fi

  title="${MENU_TITLE:-Menu}"
  backtitle="${MENU_BACKTITLE:-CLI Modular}"

  local tags_items=() name desc group
  while IFS= read -r name; do
    desc="${__DESCRIPTIONS[$name]}"; group="${__GROUPS[$name]}"
    if [[ -n "$group" ]]; then
      tags_items+=( "$name" "[$group] $desc" )
    else
      tags_items+=( "$name" "$desc" )
    fi
  done < <(all_commands)
  tags_items+=( "quit" "Sair do menu" )

  local cols="${COLUMNS:-80}" rows="${LINES:-24}"
  width=$(( cols > 20 ? cols-4 : 76 )); (( width > 120 )) && width=120
  height=$(( rows > 12 ? rows-4 : 20 )); (( height > 30 )) && height=30

  local nopts=$(( ${#tags_items[@]} / 2 ))
  menu_height=$(( nopts < (height-10) ? nopts : height-10 ))
  (( menu_height < 6 )) && menu_height=6

  local choice exit_status
  if [[ "$bin" == "dialog" ]]; then
    choice="$(
      dialog --clear \
             --backtitle "$backtitle" \
             --title "$title" \
             --menu "Use ↑/↓ para navegar, ENTER para selecionar." \
             "$height" "$width" "$menu_height" \
             "${tags_items[@]}" \
             2>&1 >/dev/tty
    )"
    exit_status=$?; clear
  else
    choice="$(
      whiptail --clear \
               --backtitle "$backtitle" \
               --title "$title" \
               --menu "Use ↑/↓ para navegar, ENTER para selecionar." \
               "$height" "$width" "$menu_height" \
               "${tags_items[@]}" \
               3>&2 2>&1 1>&3
    )"
    exit_status=$?; clear
  fi

  (( exit_status != 0 )) && return 1
  [[ -z "$choice" || "$choice" == "quit" ]] && return 1

  # === Execução com captura e exibição em textbox rolável ===
  local tmp status
  tmp="$(mktemp -t cli-output.XXXXXX)"
  # Captura stdout+stderr do handler em arquivo, para mostrar no dialog
  set +e
  {
    echo "==> Executando: $choice"
    echo
    run_command "$choice"
    status=$?
    echo
    echo "<= Exit code: $status"
  } >"$tmp" 2>&1
  set -e

  # Dimensões da caixa de texto
  local t_h=$(( height > 10 ? height : 20 ))
  local t_w=$(( width > 40 ? width : 80 ))

  if [[ "$bin" == "dialog" ]]; then
    dialog --backtitle "$backtitle" \
           --title "Saída: $choice" \
           --ok-label "Voltar" \
           --textbox "$tmp" "$t_h" "$t_w"
    clear
  else
    whiptail --backtitle "$backtitle" \
             --title "Saída: $choice" \
             --scrolltext \
             --textbox "$tmp" "$t_h" "$t_w"
    clear
  fi
  rm -f "$tmp"

  return 0
}

# ------------------------------ Render: clipper ------------------------------

show_menu_clipper() {
  local maxw menu_title="${MENU_TITLE:-Menu}"
  maxw="$(longest_name_len)"; (( maxw < 16 )) && maxw=16

  local lines=() names=() desc group line
  while IFS= read -r name; do
    names+=( "$name" )
    desc="${__DESCRIPTIONS[$name]}"; group="${__GROUPS[$name]}"
    if [[ -n "$group" ]]; then
      line="$(printf "%-${maxw}s  %s %s" "$name" "[$group]" "$desc")"
    else
      line="$(printf "%-${maxw}s  %s" "$name" "$desc")"
    fi
    lines+=( "$line" )
  done < <(all_commands)

  local width=${#menu_title} content content_len
  for content in "${lines[@]}"; do
    content_len=${#content}; (( content_len+8 > width )) && width=$((content_len+8))
  done
  (( width < maxw+20 )) && width=$((maxw+20))
  (( width > ${COLUMNS:-120}-2 )) && width=$(( (${COLUMNS:-120})-2 ))

  local footer w bl br h v
  footer="$(draw_box "$width" "$menu_title")"
  read -r _ w bl br h v <<<"$footer"

  local i=1 ndigits=${#lines[@]}; ndigits=${#ndigits}
  for content in "${lines[@]}"; do
    local pad=$((width-3-2-ndigits-2-1-${#content})); (( pad < 0 )) && pad=0
    printf "%s %s %0${ndigits}d %s  %s%*s%s\n" "$v" "[" "$i" "]" "$content" "$pad" "" "$v"
    ((i++))
  done

  printf "%s" "$v"; printf "%*s" "$((width-2))" "" | tr ' ' "$h"; printf "%s\n" "$v"
  printf "%s %s " "$v" "Escolha o número ou Q para sair:"
  printf "%*s%s\n" $((width-2 - ${#'Escolha o número ou Q para sair:'} - 1)) "" "$v"
  close_box "$width" "$bl" "$br" "$h"

  local sel; IFS= read -r sel || true
  [[ -z "${sel:-}" ]] && return 1
  [[ "$sel" =~ ^[Qq]$ ]] && return 1
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    local idx="$sel"
    if (( idx >= 1 && idx <= ${#names[@]} )); then
      local pick="${names[$((idx-1))]}"
      clear
      echo "==> Executando: $pick"
      echo
      local status=0
      set +e; run_command "$pick"; status=$?; set -e
      echo
      echo "<= Exit code: $status"
      echo
      _pause_for_key
      return 0
    fi
  fi
  log_warn "Entrada inválida: $sel"
  return 0
}

# ------------------------------ Render: padrão -------------------------------

show_menu() {
  # Delegação por estilo
  if [[ "${MENU_STYLE:-}" == "dialog" ]]; then
    show_menu_dialog
    case "$?" in
      0) return 0 ;;
      1) return 1 ;;
      2) ;;   # dialog ausente -> continua para render padrão
    esac
  elif [[ "${MENU_STYLE:-}" == "clipper" ]]; then
    show_menu_clipper
    return $?
  fi

  # Monta lista alinhada
  local maxw; maxw="$(longest_name_len)"; (( maxw < 16 )) && maxw=16
  local lines=() name desc group
  while IFS= read -r name; do
    desc="${__DESCRIPTIONS[$name]}"; group="${__GROUPS[$name]}"
    if [[ -n "$group" ]]; then
      lines+=( "$(printf "%-${maxw}s  %s %s" "$name" "[$group]" "$desc")" )
    else
      lines+=( "$(printf "%-${maxw}s  %s" "$name" "$desc")" )
    fi
  done < <(all_commands)
  lines+=( "$(printf "%-${maxw}s  %s" "quit" "Sair do menu")" )

  # fzf se disponível
  if command -v fzf >/dev/null 2>&1; then
    local choice
    choice="$(printf "%s\n" "${lines[@]}" | fzf --prompt="Selecione: " --height=90% --reverse || true)"
    [[ -z "$choice" ]] && return 1
    local cmd; cmd="$(awk '{print $1}' <<<"$choice")"
    [[ "$cmd" == "quit" ]] && return 1
    clear
    echo "==> Executando: $cmd"
    echo
    local status=0
    set +e; run_command "$cmd"; status=$?; set -e
    echo
    echo "<= Exit code: $status"
    echo
    _pause_for_key
    return 0
  fi

  # Fallback numérico
  echo; echo "$(bold "Menu")"
  local i=1; declare -ag __INDEX=()
  for line in "${lines[@]}"; do
    local cmd="$(awk '{print $1}' <<<"$line")"
    printf "%2d) %s\n" "$i" "$line"
    __INDEX[$i]="$cmd"
    ((i++))
  done
  printf "Escolha [1-%d]: " "$((i-1))"
  local sel; read -r sel || true
  [[ -z "${sel:-}" ]] && return 1
  local pick="${__INDEX[$sel]:-}"
  [[ -z "$pick" || "$pick" == "quit" ]] && return 1

  clear
  echo "==> Executando: $pick"
  echo
  local status=0
  set +e; run_command "$pick"; status=$?; set -e
  echo
  echo "<= Exit code: $status"
  echo
  _pause_for_key
  return 0
}
