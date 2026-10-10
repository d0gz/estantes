#!/bin/bash
# Compila o app, abre no simulador direto numa tela (com dados de exemplo) e salva uma captura.
# Uso: ./scripts/capturar.sh <Tela> <versão> [<pasta>]
#      ./scripts/capturar.sh Inicio 0.1               → docs/capturas/Inicio/Inicio_0.1.png
#      ./scripts/capturar.sh InicioVazio 0.1 Inicio   → docs/capturas/Inicio/InicioVazio_0.1.png
#
# A tela é um caso do enum `Captura` (App/Exemplos.swift, só em DEBUG), passado como `-captura <Tela>`.
# EXTRA="-chave valor" passa argumentos de lançamento a mais (para testes pontuais).
# As capturas ficam só no Mac (docs/capturas/ está no .gitignore).

TELA=$1
VERSAO=$2
PASTA=${3:-$TELA}
if [ -z "$TELA" ] || [ -z "$VERSAO" ]; then
  echo "Uso: ./scripts/capturar.sh <Tela> <versão> [<pasta>]"; exit 1
fi

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
APARELHO=${APARELHO:-"iPhone 14"}
DERIVADOS="${TMPDIR:-/tmp}/estantes-derivados"
LOG="${TMPDIR:-/tmp}/estantes-xcodebuild-build.log"
SAIDA="$RAIZ/docs/capturas/$PASTA/${TELA}_${VERSAO}.png"

cd "$RAIZ/ios" || exit 1
xcodegen generate > /dev/null || { echo "Falha no xcodegen generate"; exit 1; }

if ! xcodebuild build -project Estantes.xcodeproj -scheme Estantes -configuration Debug \
    -destination "platform=iOS Simulator,name=$APARELHO" -derivedDataPath "$DERIVADOS" \
    CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1; then
  grep -E "error:" "$LOG" | awk '!visto[$0]++' | head -40
  echo "Falha na compilação. Log completo: $LOG"; exit 1
fi

APP="$DERIVADOS/Build/Products/Debug-iphonesimulator/Estantes.app"
xcrun simctl boot "$APARELHO" 2>/dev/null   # já ligado: ignora o erro
open -a Simulator
xcrun simctl bootstatus "$APARELHO" > /dev/null
xcrun simctl terminate "$APARELHO" com.ricardo.estantes 2>/dev/null
xcrun simctl install "$APARELHO" "$APP" || exit 1
xcrun simctl launch "$APARELHO" com.ricardo.estantes -captura "$TELA" $EXTRA > /dev/null || exit 1

sleep "${ESPERA:-3}"   # tempo para a tela montar os exemplos e desenhar
mkdir -p "$(dirname "$SAIDA")"
xcrun simctl io "$APARELHO" screenshot "$SAIDA" > /dev/null 2>&1 || exit 1
echo "$SAIDA"
