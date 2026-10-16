#!/usr/bin/env python3
# Hook PreToolUse (Bash): bloqueia comandos git destrutivos antes de rodarem.
#
# Adaptado de skills/misc/git-guardrails-claude-code (scripts/block-dangerous-git.sh), do
# repositório "skills" de Matt Pocock (https://github.com/mattpocock/skills).
# Copyright (c) 2026 Matt Pocock — licença MIT. Reescrito em Python (o Monterey não tem jq).
#
# Diferença do original: em vez de procurar texto no comando inteiro (o que bloqueava
# `git commit -m "... git push ..."` e todo push), o comando é dividido em trechos com shlex
# e cada `git <subcomando>` é analisado pelos argumentos. Push de branch continua liberado.
# Limitação: não enxerga `bash -c "..."` nem `$(...)`. É proteção contra engano, não barreira
# de segurança.
#
# Bloqueia: push para a main (ou sem destino estando na main, ou --all/--mirror), push forçado
# (--force, -f, +refspec; --force-with-lease é liberado), reset --hard, clean -f, branch -D,
# checkout . e restore .
# Saída 2 + mensagem no stderr = bloqueado (o Claude vê a mensagem); saída 0 = liberado.

import json
import shlex
import subprocess
import sys

BRANCH_PROTEGIDA = "main"
# Opções globais do git que consomem o argumento seguinte (git -C dir status).
GLOBAIS_COM_VALOR = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
# Opções do push que consomem o argumento seguinte.
PUSH_COM_VALOR = {"-o", "--push-option", "--repo", "--receive-pack", "--exec"}


def trechos(comando):
    """Divide o comando em listas de palavras, cortando em &&, ||, ;, |, & e parênteses."""
    try:
        lexer = shlex.shlex(comando, posix=True, punctuation_chars=True)
        lexer.whitespace_split = True
        palavras = list(lexer)
    except ValueError:  # aspas sem fechar: cai no corte por espaços
        palavras = comando.split()
    atual = []
    for palavra in palavras:
        if palavra and all(c in ";&|()" for c in palavra):
            if atual:
                yield atual
            atual = []
        else:
            atual.append(palavra)
    if atual:
        yield atual


def chamada_git(palavras):
    """Devolve (subcomando, argumentos, pasta do -C) se o trecho for um git; senão None."""
    i = 0
    while i < len(palavras) and "=" in palavras[i] and not palavras[i].startswith("-"):
        i += 1  # VAR=valor git ...
    if i >= len(palavras) or not (palavras[i] == "git" or palavras[i].endswith("/git")):
        return None
    i += 1
    pasta = None
    while i < len(palavras) and palavras[i].startswith("-"):
        if palavras[i] in GLOBAIS_COM_VALOR:
            if palavras[i] == "-C" and i + 1 < len(palavras):
                pasta = palavras[i + 1]
            i += 2
        else:
            i += 1
    if i >= len(palavras):
        return None
    return palavras[i], palavras[i + 1:], pasta


def flag_curta(argumentos, letra):
    """True se alguma opção curta agrupada (-fd, -xdf) contém a letra."""
    return any(a.startswith("-") and not a.startswith("--") and letra in a for a in argumentos)


def branch_atual(pasta):
    try:
        saida = subprocess.run(
            ["git", "rev-parse", "--abbrev-ref", "HEAD"],
            cwd=pasta, capture_output=True, text=True, timeout=5,
        )
        return saida.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def motivo_push(argumentos, pasta):
    if "--force" in argumentos or flag_curta(argumentos, "f"):
        return "push forçado (use --force-with-lease, se for mesmo preciso)"
    if "--all" in argumentos or "--mirror" in argumentos:
        return f"push de todas as branches inclui a {BRANCH_PROTEGIDA}"
    posicionais = []
    pular = False
    for a in argumentos:
        if pular:
            pular = False
        elif a in PUSH_COM_VALOR:
            pular = True
        elif not a.startswith("-"):
            posicionais.append(a)
    refspecs = posicionais[1:]  # o primeiro é o remoto
    if not refspecs:
        if branch_atual(pasta) == BRANCH_PROTEGIDA:
            return f"push sem destino estando na {BRANCH_PROTEGIDA}"
        return None
    for refspec in refspecs:
        if refspec.startswith("+"):
            return f"push forçado por '+' no refspec '{refspec}'"
        destino = refspec.split(":")[-1].removeprefix("refs/heads/")
        if destino == "HEAD":
            destino = branch_atual(pasta)
        if destino == BRANCH_PROTEGIDA:
            return f"push para a {BRANCH_PROTEGIDA} (use um PR)"
    return None


def motivo(subcomando, argumentos, pasta):
    if subcomando == "push":
        return motivo_push(argumentos, pasta)
    if subcomando == "reset" and "--hard" in argumentos:
        return "reset --hard descarta mudanças"
    if subcomando == "clean" and ("--force" in argumentos or flag_curta(argumentos, "f")):
        return "clean -f apaga arquivos não versionados"
    if subcomando == "branch" and (
        flag_curta(argumentos, "D")
        or (("--delete" in argumentos or flag_curta(argumentos, "d"))
            and ("--force" in argumentos or flag_curta(argumentos, "f")))
    ):
        return "branch -D apaga branch sem conferir o merge"
    if subcomando in ("checkout", "restore") and "." in argumentos:
        return f"{subcomando} . descarta as mudanças da árvore de trabalho"
    return None


def main():
    try:
        entrada = json.load(sys.stdin)
    except ValueError:
        return 0
    comando = (entrada.get("tool_input") or {}).get("command") or ""
    cwd = entrada.get("cwd") or None
    for palavras in trechos(comando):
        chamada = chamada_git(palavras)
        if chamada is None:
            continue
        subcomando, argumentos, pasta = chamada
        razao = motivo(subcomando, argumentos, pasta or cwd)
        if razao:
            print(
                f"BLOQUEADO pelo hook do projeto: {razao}. Comando: {' '.join(palavras)}. "
                "O Ricardo não autorizou este comando; peça a ele, se for necessário.",
                file=sys.stderr,
            )
            return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
