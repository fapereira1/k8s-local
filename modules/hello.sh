# shellcheck shell=bash

hello_handler() {
  echo "Olá! Este é um módulo de exemplo."
}

register_cmd "hello" "Exibe uma mensagem de boas-vindas" "hello_handler" "utilidades"