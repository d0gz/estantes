#!/usr/bin/env python3
"""
Extrai TODOS os registros do tipo "Livro" dos acervos LexML (formato TinyDB), com TODOS os campos.

Formato de entrada (confirmado no acervo_1556_1899.json):
    {"_default": {"1": {registro}, "2": {registro}, ...}}   <- tudo numa linha só
Campos vistos até agora: tipoDocumento ("Livro" ou lista), data (texto ou lista), urn,
title, description, identifier, url, localidade, autoridade, type, facet-*.
Outros acervos podem ter campos a mais (ex.: autor). O script não presume nada:
guarda o registro inteiro e lista no resumo todos os campos que encontrou.

Como lê sem estourar a memória:
    ijson.kvitems(arquivo, "_default") entrega UM registro por vez.
    O arquivo inteiro nunca é carregado.

Uso:
    python -m pip install ijson
    python -X utf8 extrair_livros_lexml.py "D:\\caminho\\da\\pasta-lexml"
    python -X utf8 extrair_livros_lexml.py "D:\\caminho\\da\\pasta-lexml" --limite 5000   (teste)

Gera na pasta atual:
    livros_lexml.jsonl    um livro por linha, registro COMPLETO (todos os campos, acentos em NFC)
                          + "_arquivo" (de qual acervo veio) e "_chave" (chave no TinyDB)
    livros_lexml.csv      colunas principais para conferir no Excel:
                          lexml_id, urn, titulo, autores, ano, descricao, outros_tipos
    resumo_extracao.txt   contagens por arquivo e por tipo + INVENTÁRIO DE CAMPOS dos livros
"""
import argparse
import csv
import json
import os
import re
import sys
import time
import unicodedata
from collections import Counter

try:
    import ijson
except ImportError:
    sys.exit("Instale antes: python -m pip install ijson")

RE_ANO_URN = re.compile(r":livro:(\d{4})")
RE_ANO = re.compile(r"\b(1[0-9]{3}|20[0-9]{2})\b")
RE_CAMPO_AUTOR = re.compile(r"autor|author|creator|contributor|responsab", re.I)
MAX_DESCRICAO_CSV = 400
CAMPOS_CONHECIDOS = {
    "tipoDocumento", "facet-tipoDocumento", "data", "urn", "url", "localidade",
    "facet-localidade", "autoridade", "facet-autoridade", "title", "description",
    "type", "identifier",
}


# ------------------------------------------------------------------ limpeza
def nfc(texto):
    """O LexML guarda acentos decompostos ("Suma\u0301rio" = a + acento separado).
    NFC junta letra + acento num caractere só: buscas e comparações passam a funcionar."""
    if not isinstance(texto, str):
        return ""
    return " ".join(unicodedata.normalize("NFC", texto).split())


def nfc_profundo(v):
    """Aplica NFC em todos os textos de um registro, sem mudar a estrutura."""
    if isinstance(v, str):
        return unicodedata.normalize("NFC", v)
    if isinstance(v, list):
        return [nfc_profundo(x) for x in v]
    if isinstance(v, dict):
        return {k: nfc_profundo(x) for k, x in v.items()}
    return v


def limpar_titulo(t):
    t = nfc(t)
    # Catalogação MARC costuma deixar pontuação no fim: "Revue du droit ... --", "Título /"
    return re.sub(r"[\s\-/:;,.]+$", "", t)


def lista(v):
    if v is None:
        return []
    return v if isinstance(v, list) else [v]


def vazio(v):
    return v is None or v == "" or v == [] or v == {}


def eh_livro(reg):
    return "Livro" in lista(reg.get("tipoDocumento"))


def primeiro_str(v):
    for x in lista(v):
        if isinstance(x, str) and x:
            return x
    return ""


def extrair_ano(reg, urn):
    """O ano da URN (":livro:1569;") é o mais confiável: "data" às vezes é uma
    lista de dezenas de anos (edições, volumes, reimpressões)."""
    m = RE_ANO_URN.search(urn)
    if m:
        return m.group(1)
    anos = [m.group(1) for x in lista(reg.get("data")) if isinstance(x, str)
            for m in [RE_ANO.search(x)] if m]
    return min(anos) if anos else ""


def extrair_autores(reg):
    """Junta qualquer campo cujo nome lembre autor (autor, author, creator, contributor...).
    Ignora os 'facet-' (são cópias para filtro) e 'autoridade' (órgão emissor de normas)."""
    nomes = []
    for k, v in reg.items():
        if k.startswith("facet-") or k == "autoridade" or not RE_CAMPO_AUTOR.search(k):
            continue
        for x in lista(v):
            if isinstance(x, str):
                x = nfc(x)
                if x and x not in nomes:
                    nomes.append(x)
            elif isinstance(x, dict):  # ex.: {"nome": "..."}
                for y in x.values():
                    if isinstance(y, str) and nfc(y) and nfc(y) not in nomes:
                        nomes.append(nfc(y))
    return " | ".join(nomes)


def resumir_valor(v, n=120):
    s = json.dumps(v, ensure_ascii=False, default=str)
    return s if len(s) <= n else s[:n] + "…"


# ------------------------------------------------------------------ leitura
def arquivos_de(caminhos):
    saida = []
    for c in caminhos:
        if os.path.isfile(c):
            saida.append(c)
        elif os.path.isdir(c):
            for raiz, _, nomes in os.walk(c):
                saida += [os.path.join(raiz, n) for n in nomes if n.lower().endswith(".json")]
        else:
            print(f"Não encontrado: {c}")
    return sorted(saida)


def registros(caminho):
    """Um registro por vez, direto do disco."""
    with open(caminho, "rb") as f:
        for chave, reg in ijson.kvitems(f, "_default", use_float=True):
            yield chave, reg


class Inventario:
    """Quais campos os livros têm, quantas vezes vêm preenchidos e um exemplo de cada."""
    def __init__(self):
        self.preenchido = Counter()
        self.tipos_valor = {}
        self.exemplo = {}

    def registrar(self, reg):
        for k, v in reg.items():
            self.tipos_valor.setdefault(k, Counter())[type(v).__name__] += 1
            if not vazio(v):
                self.preenchido[k] += 1
                self.exemplo.setdefault(k, resumir_valor(v))

    def linhas(self, total):
        saida = []
        for k in sorted(self.tipos_valor, key=lambda k: -self.preenchido[k]):
            novo = "" if k in CAMPOS_CONHECIDOS else "  <-- CAMPO NOVO"
            formas = ", ".join(f"{t}:{c:,}" for t, c in self.tipos_valor[k].most_common())
            pct = 100 * self.preenchido[k] / total if total else 0
            saida.append(f"   {self.preenchido[k]:>10,} ({pct:5.1f}%)  {k}{novo}")
            saida.append(f"              formas: {formas}")
            if k in self.exemplo:
                saida.append(f"              ex.: {self.exemplo[k]}")
        return saida


def main():
    ap = argparse.ArgumentParser(description="Extrai livros do LexML (todos os campos)")
    ap.add_argument("caminhos", nargs="+")
    ap.add_argument("--limite", type=int, default=0, help="máx. de registros por arquivo (teste)")
    ap.add_argument("--prefixo", default="livros_lexml", help="nome base dos arquivos de saída")
    args = ap.parse_args()

    arquivos = arquivos_de(args.caminhos)
    if not arquivos:
        sys.exit("Nenhum .json encontrado.")
    print(f"ijson backend: {ijson.backend}")
    if ijson.backend == "python":
        print("  AVISO: backend em Python puro é bem mais lento. Tente:"
              " python -m pip install --force-reinstall ijson")

    vistos = set()            # o mesmo livro aparece repetido (no mesmo acervo e entre acervos)
    tipos_total = Counter()
    inv_total = Inventario()
    linhas_resumo = []
    total_livros = total_dup = total_regs = com_autor = 0
    t_inicio = time.time()
    colunas = ["lexml_id", "urn", "titulo", "autores", "ano", "descricao", "outros_tipos"]
    saida_csv, saida_jsonl = f"{args.prefixo}.csv", f"{args.prefixo}.jsonl"

    with open(saida_csv, "w", encoding="utf-8-sig", newline="") as fcsv, \
         open(saida_jsonl, "w", encoding="utf-8") as fjson:
        w = csv.writer(fcsv)
        w.writerow(colunas)

        for arq in arquivos:
            nome = os.path.basename(arq)
            tam = os.path.getsize(arq) / 1e9
            print(f"\n-> {arq} ({tam:.2f} GB)")
            t0 = time.time()
            n = livros = dup = sem_id = 0
            tipos = Counter()
            inv = Inventario()
            try:
                for chave, reg in registros(arq):
                    n += 1
                    if not isinstance(reg, dict):
                        continue
                    for t in set(map(str, lista(reg.get("tipoDocumento")))):
                        tipos[t] += 1

                    if eh_livro(reg):
                        lexml_id = primeiro_str(reg.get("identifier"))
                        urn = next((u for u in lista(reg.get("urn"))
                                    if isinstance(u, str) and ":livro:" in u),
                                   primeiro_str(reg.get("urn")))
                        chave_unica = lexml_id or urn
                        if not chave_unica:
                            sem_id += 1
                        elif chave_unica in vistos:
                            dup += 1
                            continue
                        else:
                            vistos.add(chave_unica)

                        inv.registrar(reg)
                        reg = nfc_profundo(reg)
                        fjson.write(json.dumps({"_arquivo": nome, "_chave": chave, **reg},
                                               ensure_ascii=False) + "\n")
                        autores = extrair_autores(reg)
                        com_autor += bool(autores)
                        outros = sorted(set(map(str, lista(reg.get("tipoDocumento")))) - {"Livro"})
                        w.writerow([lexml_id, urn, limpar_titulo(reg.get("title")), autores,
                                    extrair_ano(reg, urn),
                                    nfc(reg.get("description"))[:MAX_DESCRICAO_CSV],
                                    "|".join(outros)])
                        livros += 1

                    if n % 200_000 == 0:
                        print(f"   {n:,} registros, {livros:,} livros ({time.time() - t0:.0f}s)")
                    if args.limite and n >= args.limite:
                        break
            except ijson.common.IncompleteJSONError as e:
                print(f"   ERRO: JSON incompleto ou corrompido após {n:,} registros: {e}")
                linhas_resumo.append(f"   ERRO após {n:,} registros: {e}")

            fcsv.flush()
            fjson.flush()
            seg = time.time() - t0
            print(f"   {n:,} registros | {livros:,} livros novos | {dup:,} repetidos | {seg:.0f}s")
            total_regs += n
            total_livros += livros
            total_dup += dup
            tipos_total.update(tipos)
            for k, c in inv.preenchido.items():
                inv_total.preenchido[k] += c
            for k, cs in inv.tipos_valor.items():
                inv_total.tipos_valor.setdefault(k, Counter()).update(cs)
            for k, ex in inv.exemplo.items():
                inv_total.exemplo.setdefault(k, ex)

            linhas_resumo.append(f"\n## {nome} — {tam:.2f} GB — {seg:.0f}s")
            linhas_resumo.append(f"   registros: {n:,} | livros gravados: {livros:,}"
                                 f" | repetidos: {dup:,} | sem id: {sem_id:,}")
            linhas_resumo.append("   tipos:")
            linhas_resumo += [f"   {c:>10,}  {t}" for t, c in tipos.most_common(12)]
            linhas_resumo.append("   campos dos livros deste arquivo:")
            linhas_resumo += [f"   {c:>10,}  {k}{'' if k in CAMPOS_CONHECIDOS else '  <-- NOVO'}"
                              for k, c in inv.preenchido.most_common()]

    tam_csv = os.path.getsize(saida_csv)
    tam_jsonl = os.path.getsize(saida_jsonl)
    cab = [
        "# Extração de livros do LexML",
        f"arquivos: {len(arquivos)} | tempo total: {time.time() - t_inicio:.0f}s | ijson: {ijson.backend}",
        f"registros lidos: {total_regs:,}",
        f"livros gravados: {total_livros:,} (repetidos ignorados: {total_dup:,})",
        f"livros com algum campo de autor: {com_autor:,}",
        f"{saida_jsonl}: {tam_jsonl / 1e6:,.1f} MB | {saida_csv}: {tam_csv / 1e6:,.1f} MB",
        f"estimativa no Postgres (colunas do CSV + índices): ~{tam_csv * 2.3 / 1e6:,.0f} MB"
        " (limite grátis do Supabase: 500 MB)",
        "", "## Inventário de campos dos livros (todos os arquivos)",
    ] + inv_total.linhas(total_livros) + [
        "", "## Tipos de documento (todos os arquivos)",
    ] + [f"   {c:>10,}  {t}" for t, c in tipos_total.most_common(40)]
    with open("resumo_extracao.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(cab + ["", "# Por arquivo"] + linhas_resumo) + "\n")

    print("\n" + "\n".join(cab[:7]))
    print("\nPronto. Envie resumo_extracao.txt no chat.")


if __name__ == "__main__":
    main()
