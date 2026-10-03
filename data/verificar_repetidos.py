#!/usr/bin/env python3
"""
Confere se os livros "repetidos" do LexML são MESMO repetidos.

O extrator considera repetido o livro cujo `identifier` (id interno do LexML) já apareceu;
se faltar identifier, usa a URN. Ele NÃO compara títulos.
Este script prova (ou desmente) que essa chave é segura: para cada livro repetido,
compara o registro INTEIRO com a primeira ocorrência, usando um hash (impressão digital)
do JSON normalizado.

Resultado possível para cada repetição:
  idêntico      -> o registro é igual, byte a byte (após normalizar acentos e ordem dos campos)
  divergente    -> mesma chave, conteúdo diferente (o script mostra exemplos lado a lado)

Uso:
    python -X utf8 verificar_repetidos.py "D:\\caminho\\da\\pasta-lexml"
Gera verificacao_repetidos.txt.
"""
import hashlib
import json
import os
import sys
import time
import unicodedata
from collections import Counter

try:
    import ijson
except ImportError:
    sys.exit("Instale antes: python -m pip install ijson")

MAX_EXEMPLOS = 15


def nfc_profundo(v):
    if isinstance(v, str):
        return unicodedata.normalize("NFC", v)
    if isinstance(v, list):
        return [nfc_profundo(x) for x in v]
    if isinstance(v, dict):
        return {k: nfc_profundo(x) for k, x in v.items()}
    return v


def lista(v):
    return [] if v is None else (v if isinstance(v, list) else [v])


def primeiro_str(v):
    return next((x for x in lista(v) if isinstance(x, str) and x), "")


def impressao_digital(reg):
    """Hash do registro: mesma entrada -> mesmo hash; qualquer diferença -> hash diferente."""
    canon = json.dumps(nfc_profundo(reg), sort_keys=True, ensure_ascii=False, default=str)
    return hashlib.blake2b(canon.encode("utf-8"), digest_size=12).digest()


def main(pasta):
    arquivos = sorted(os.path.join(r, n) for r, _, ns in os.walk(pasta)
                      for n in ns if n.lower().endswith(".json"))
    vistos = {}   # chave -> (hash, arquivo, chave_tinydb)
    primeiros = {}  # chave -> registro (só guardamos se precisarmos mostrar exemplo)
    cont = Counter()
    exemplos = []
    t0 = time.time()

    for arq in arquivos:
        nome = os.path.basename(arq)
        print(f"-> {nome}")
        with open(arq, "rb") as f:
            for k_tiny, reg in ijson.kvitems(f, "_default", use_float=True):
                if not isinstance(reg, dict) or "Livro" not in lista(reg.get("tipoDocumento")):
                    continue
                chave = primeiro_str(reg.get("identifier")) or primeiro_str(reg.get("urn"))
                h = impressao_digital(reg)
                if chave not in vistos:
                    vistos[chave] = (h, nome, k_tiny)
                    cont["livros únicos"] += 1
                    continue
                h0, arq0, k0 = vistos[chave]
                lugar = "mesmo arquivo" if arq0 == nome else "outro arquivo"
                if h == h0:
                    cont[f"repetido idêntico ({lugar})"] += 1
                else:
                    cont[f"repetido DIVERGENTE ({lugar})"] += 1
                    if len(exemplos) < MAX_EXEMPLOS:
                        exemplos.append((chave, arq0, k0, nome, k_tiny, nfc_profundo(reg)))

    # Para os exemplos divergentes, relê a primeira ocorrência para mostrar lado a lado.
    alvos = {(arq0, k0) for _, arq0, k0, *_ in exemplos}
    originais = {}
    if alvos:
        for arq in arquivos:
            nome = os.path.basename(arq)
            if not any(a == nome for a, _ in alvos):
                continue
            with open(arq, "rb") as f:
                for k_tiny, reg in ijson.kvitems(f, "_default", use_float=True):
                    if (nome, k_tiny) in alvos:
                        originais[(nome, k_tiny)] = nfc_profundo(reg)

    linhas = ["# Verificação dos livros repetidos",
              f"tempo: {time.time() - t0:.0f}s", "chave usada: identifier (ou urn, se faltar)", ""]
    linhas += [f"   {c:>10,}  {k}" for k, c in sorted(cont.items())]
    if exemplos:
        linhas += ["", f"## Exemplos de repetidos DIVERGENTES ({len(exemplos)})"]
        for chave, arq0, k0, arq1, k1, reg in exemplos:
            orig = originais.get((arq0, k0), {})
            linhas.append(f"\n--- chave {chave}: {arq0}#{k0}  x  {arq1}#{k1}")
            for campo in sorted(set(orig) | set(reg)):
                a, b = orig.get(campo), reg.get(campo)
                if a != b:
                    linhas.append(f"   {campo}:\n      1ª: {json.dumps(a, ensure_ascii=False)[:200]}"
                                  f"\n      2ª: {json.dumps(b, ensure_ascii=False)[:200]}")
    else:
        linhas += ["", "Nenhum repetido divergente: todas as repetições são cópias idênticas."]

    with open("verificacao_repetidos.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(linhas) + "\n")
    print("\n".join(linhas[:12]))
    print("\nDetalhes em verificacao_repetidos.txt")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit('Uso: python -X utf8 verificar_repetidos.py "PASTA"')
    main(sys.argv[1])
