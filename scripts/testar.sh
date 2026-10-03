#!/bin/bash
# Gera o projeto (XcodeGen) e roda os testes no simulador, mostrando só o essencial.
# Uso: ./scripts/testar.sh
#      DESTINO="platform=iOS Simulator,name=iPhone 14 Pro" ./scripts/testar.sh
#
# Por que existe: a saída completa do xcodebuild tem milhares de linhas. Lida inteira pelo
# Claude Code, ela gasta muitos tokens sem acrescentar nada. Aqui ela vai para um arquivo
# de log, e na tela aparecem só erros, testes que falharam e o resumo.

cd "$(dirname "$0")/../ios" || exit 1

if ! xcodegen generate > /dev/null; then
  echo "Falha no xcodegen generate"; exit 1
fi

DESTINO=${DESTINO:-"platform=iOS Simulator,name=iPhone 14"}
LOG="${TMPDIR:-/tmp}/estantes-xcodebuild-test.log"

xcodebuild test \
  -project Estantes.xcodeproj \
  -scheme Estantes \
  -destination "$DESTINO" \
  CODE_SIGNING_ALLOWED=NO > "$LOG" 2>&1
STATUS=$?

# Só as linhas úteis, sem repetição, no máximo 80.
grep -E "error:|Test Case .* failed|TEST (SUCCEEDED|FAILED)|Executed [0-9]+ test|BUILD FAILED" "$LOG" \
  | awk '!visto[$0]++' | head -80

if [ $STATUS -ne 0 ]; then
  echo "Falhou (código $STATUS). Log completo: $LOG"
fi
exit $STATUS
