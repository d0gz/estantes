#!/usr/bin/env python3
"""
Enriquece livros do LexML a partir da página da URN (ficha completa).

A página https://www.lexml.gov.br/urn/<URN> traz o que o dataset não tem:
  - da OBRA: autor(es), título, data, classificação CDDir com a hierarquia
  - de cada EDIÇÃO da obra: URN, edição/tiragem, ano, imprenta (local, editora, ano),
    descrição física, ISBN, bibliotecas que têm o livro
Uma consulta traz todas as edições da obra: é isso que resolve o agrupamento.

Regras de boa convivência (robots.txt do LexML):
  - só acessa /urn (permitido); nunca /busca/
  - espera 6 s entre pedidos (o robots pede 5 s)
  - guarda cada página em cache_urn/: rodar de novo não baixa outra vez

Instalar:  python -m pip install requests beautifulsoup4

Uso:
  1) Testar o leitor SEM internet, com a página salva:
       python -X utf8 enriquecer_urn.py --html paginaURN.html
  2) Achar a URN de um livro seu no CSV extraído (sem acento/maiúsculas):
       python -X utf8 enriquecer_urn.py --buscar "defesa do executado" --csv livros_lexml.csv
  3) Enriquecer URNs específicas:
       python -X utf8 enriquecer_urn.py "urn:lex:br:rede.virtual.bibliotecas:livro:2000;000582216"
  4) Teste de robustez: N URNs sorteadas do CSV, de várias épocas:
       python -X utf8 enriquecer_urn.py --amostra 30 --csv livros_lexml.csv

Saídas: fichas_urn.jsonl (uma ficha por linha) e o resumo no console.
"""
import argparse
import csv
import json
import os
import random
import re
import sys
import time
import unicodedata

try:
    from bs4 import BeautifulSoup
except ImportError:
    sys.exit("Instale antes: python -m pip install requests beautifulsoup4")

BASE = "https://www.lexml.gov.br/urn/"
INTERVALO_S = 6
PASTA_CACHE = "cache_urn"
USER_AGENT = "EstantesApp/0.1 (projeto pessoal de estudo; catalogacao de biblioteca pessoal)"


# ------------------------------------------------------------------ utilidades
def limpa(t):
    """Junta espaços (inclui &nbsp;) e normaliza acentos para NFC."""
    t = unicodedata.normalize("NFC", t or "").replace("\xa0", " ")
    return " ".join(t.split())


def sem_acento(t):
    t = unicodedata.normalize("NFD", t or "")
    return "".join(c for c in t if unicodedata.category(c) != "Mn").lower()


def isbn_valido(isbn):
    """Confere o dígito verificador. ISBN-10: soma ponderada 10..1 divisível por 11.
    ISBN-13: pesos 1,3,1,3... e soma divisível por 10."""
    if len(isbn) == 10:
        soma = sum((10 - i) * (10 if c == "X" else int(c)) for i, c in enumerate(isbn))
        return soma % 11 == 0
    if len(isbn) == 13 and isbn.isdigit():
        soma = sum((1 if i % 2 == 0 else 3) * int(c) for i, c in enumerate(isbn))
        return soma % 10 == 0
    return False


def isbn10_para_13(isbn10):
    base = "978" + isbn10[:9]
    soma = sum((1 if i % 2 == 0 else 3) * int(c) for i, c in enumerate(base))
    return base + str((10 - soma % 10) % 10)


def extrair_isbns(texto):
    """'ISBN: 85-203-1814-2 (broch.)' -> [{'bruto':..., 'isbn13':'9788520318142', 'valido':True}]"""
    saida = []
    for bruto in re.findall(r"[\dXx][\dXx\- ]{8,20}[\dXx]", texto):
        so = re.sub(r"[^0-9Xx]", "", bruto).upper()
        if len(so) not in (10, 13):
            continue
        ok = isbn_valido(so)
        isbn13 = isbn10_para_13(so) if (len(so) == 10 and ok) else (so if ok else None)
        saida.append({"bruto": bruto.strip(), "isbn13": isbn13, "valido": ok})
    return saida


def separar_imprenta(texto):
    """'São Paulo, Revista dos Tribunais, 2000.' -> local, editora, ano (melhor esforço)."""
    t = texto.rstrip(". ")
    ano = re.search(r"(1[5-9]\d{2}|20\d{2})(?!.*\d{4})", t)
    partes = [p.strip() for p in t.split(",")]
    local = partes[0] if len(partes) >= 2 else ""
    editora = ", ".join(partes[1:-1]) if len(partes) >= 3 else ""
    return {"texto": texto, "local": local, "editora": editora,
            "ano": ano.group(1) if ano else ""}


# ------------------------------------------------------------------ leitura da página
def ler_ficha(html, urn_pedida=""):
    sopa = BeautifulSoup(html, "html.parser")
    paineis = sopa.select("div.panel.panel-default")
    if not paineis:
        raise ValueError("página sem painéis: layout mudou ou URN inexistente")

    ficha = {"urn_pedida": urn_pedida, "autores": [], "titulo": "", "tipo": "", "data": "",
             "cddir": "", "cddir_hierarquia": [], "edicoes": []}

    # Painel 1: dados da obra (pares rótulo/valor)
    rotulo_ant = ""
    for item in paineis[0].select("div.list-group-item"):
        colunas = item.select("div.row > div")
        if len(colunas) < 2:
            continue
        rotulo = limpa(colunas[0].get_text())
        valor_div = colunas[1]
        valor = limpa(valor_div.get_text(" "))
        if rotulo == "Tipo":
            ficha["tipo"] = valor
        elif rotulo == "Autor":
            nomes = [limpa(a.get_text()) for a in valor_div.find_all("a")] or [valor]
            ficha["autores"] += [n for n in nomes if n and n not in ficha["autores"]]
        elif rotulo == "Título":
            ficha["titulo"] = valor
        elif rotulo == "Data":
            ficha["data"] = valor
        elif rotulo.startswith("Classificação"):
            ficha["cddir"] = valor
        elif rotulo == "" and rotulo_ant.startswith("Classificação"):
            # "DIREITO PÚBLICO [ 341 ] » DIREITO PROCESSUAL [ 341.4 ] » ..."
            for nome, codigo in re.findall(r"([^\[\]»]+?)\s*\[\s*([\d.]+)\s*\]", valor):
                ficha["cddir_hierarquia"].append({"codigo": codigo, "nome": limpa(nome)})
        if rotulo:
            rotulo_ant = rotulo

    # Painéis seguintes: uma linha por edição ("Publicação: Texto - Português", etc.)
    for painel in paineis[1:]:
        titulo_painel = limpa(painel.select_one(".panel-title").get_text()) \
            if painel.select_one(".panel-title") else ""
        for item in painel.select("div.list-group-item"):
            colunas = item.select("div.row > div")
            if len(colunas) < 3:
                continue
            principal = colunas[2]
            link = principal.select_one("b a[href*='/urn/']")
            if not link:
                continue
            texto = principal.get_text("\n")
            linhas = [limpa(l) for l in texto.split("\n") if limpa(l)]

            def campo(prefixo):
                for l in linhas:
                    if l.startswith(prefixo):
                        return l[len(prefixo):].strip()
                return ""

            negrito = limpa(principal.select_one("b").get_text())
            responsabilidade = negrito.split(" / ", 1)[1] if " / " in negrito else ""
            imprenta = campo("Imprenta:")
            isbn_txt = " ".join(l for l in linhas if l.startswith("ISBN"))
            bibliotecas = []
            for span in principal.select("span.controlTitleDivBib"):
                tit = limpa(span.get("title", ""))
                nome, _, loc = tit.partition("Localização:")
                bibliotecas.append({"sigla": limpa(span.get_text()),
                                    "nome": nome.strip(" ."),
                                    "localizacao": loc.strip(" []")})
            disp = principal.select_one("a[href*='doc_number=']")
            ficha["edicoes"].append({
                "urn": link["href"].split("/urn/", 1)[1],
                "publicacao": titulo_painel,
                "edicao": limpa(colunas[0].get_text()).rstrip(". "),
                "ano": limpa(colunas[1].get_text()),
                "titulo": limpa(link.get_text()),
                "responsabilidade": responsabilidade.rstrip("."),
                "imprenta": separar_imprenta(imprenta) if imprenta else None,
                "descricao_fisica": campo("Descrição Física:"),
                "isbns": extrair_isbns(isbn_txt),
                "bibliotecas": bibliotecas,
                "catalogo_senado": disp["href"] if disp else "",
            })
    return ficha


# ------------------------------------------------------------------ rede (com cache)
_ultimo_pedido = [0.0]


def baixar(urn):
    os.makedirs(PASTA_CACHE, exist_ok=True)
    arq = os.path.join(PASTA_CACHE, re.sub(r"[^\w.-]", "_", urn) + ".html")
    if os.path.exists(arq):
        with open(arq, encoding="utf-8") as f:
            return f.read(), "cache"
    import requests
    espera = INTERVALO_S - (time.time() - _ultimo_pedido[0])
    if espera > 0:
        time.sleep(espera)
    r = requests.get(BASE + urn, headers={"User-Agent": USER_AGENT}, timeout=30)
    _ultimo_pedido[0] = time.time()
    r.raise_for_status()
    r.encoding = "utf-8"
    with open(arq, "w", encoding="utf-8") as f:
        f.write(r.text)
    return r.text, "rede"


# ------------------------------------------------------------------ CSV
def ler_csv(caminho):
    with open(caminho, encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def resumo_ficha(ficha):
    ed = ficha["edicoes"]
    isbns = sorted({i["isbn13"] for e in ed for i in e["isbns"] if i["isbn13"]})
    return (f"   autor: {' | '.join(ficha['autores']) or '—'}\n"
            f"   título: {ficha['titulo']}\n"
            f"   CDDir: {ficha['cddir'] or '—'}  "
            f"{' > '.join(h['nome'] for h in ficha['cddir_hierarquia'])}\n"
            f"   edições: {len(ed)} | ISBNs válidos: {', '.join(isbns) or '—'}")


def main():
    ap = argparse.ArgumentParser(description="Enriquece livros do LexML pela página da URN")
    ap.add_argument("urns", nargs="*")
    ap.add_argument("--html", help="testar com uma página salva (sem internet)")
    ap.add_argument("--csv", help="livros_lexml.csv gerado pelo extrator")
    ap.add_argument("--buscar", help="procura um trecho de título no CSV e mostra as URNs")
    ap.add_argument("--amostra", type=int, help="enriquece N URNs sorteadas do CSV")
    ap.add_argument("--semente", type=int, default=42)
    args = ap.parse_args()

    if args.html:
        with open(args.html, encoding="utf-8") as f:
            ficha = ler_ficha(f.read(), "(arquivo local)")
        print(resumo_ficha(ficha))
        print(json.dumps(ficha, ensure_ascii=False, indent=2))
        return

    urns = list(args.urns)
    if args.buscar or args.amostra:
        if not args.csv:
            sys.exit("Use --csv livros_lexml.csv junto com --buscar ou --amostra.")
        linhas = ler_csv(args.csv)
        if args.buscar:
            alvo = sem_acento(args.buscar)
            achados = [l for l in linhas if alvo in sem_acento(l["titulo"])]
            for l in achados[:30]:
                print(f"{l['ano']}  {l['titulo'][:70]}\n      {l['urn']}")
            print(f"\n{len(achados)} livro(s) encontrado(s).")
            return
        random.seed(args.semente)
        urns = [l["urn"] for l in random.sample(linhas, min(args.amostra, len(linhas)))]
        print(f"Amostra de {len(urns)} URNs (~{len(urns) * INTERVALO_S // 60 + 1} min).")

    if not urns:
        ap.print_help()
        return

    stats = {"ok": 0, "erro": 0, "com_autor": 0, "com_isbn": 0, "com_cddir": 0}
    with open("fichas_urn.jsonl", "a", encoding="utf-8") as saida:
        for i, urn in enumerate(urns, 1):
            print(f"\n[{i}/{len(urns)}] {urn}")
            try:
                html, origem = baixar(urn)
                ficha = ler_ficha(html, urn)
                ficha["baixado_de"] = origem
                saida.write(json.dumps(ficha, ensure_ascii=False) + "\n")
                print(resumo_ficha(ficha))
                stats["ok"] += 1
                stats["com_autor"] += bool(ficha["autores"])
                stats["com_cddir"] += bool(ficha["cddir"])
                stats["com_isbn"] += any(x["isbn13"] for e in ficha["edicoes"] for x in e["isbns"])
            except Exception as e:  # registra e segue: o objetivo é medir a robustez
                stats["erro"] += 1
                print(f"   ERRO: {type(e).__name__}: {e}")

    n = stats["ok"] or 1
    print("\n# Resumo")
    print(f"   lidas: {stats['ok']} | erros: {stats['erro']}")
    print(f"   com autor: {stats['com_autor']} ({100 * stats['com_autor'] // n}%)"
          f" | com CDDir: {stats['com_cddir']} ({100 * stats['com_cddir'] // n}%)"
          f" | com ISBN: {stats['com_isbn']} ({100 * stats['com_isbn'] // n}%)")
    print("   fichas em fichas_urn.jsonl; páginas em cache_urn/")


if __name__ == "__main__":
    main()
