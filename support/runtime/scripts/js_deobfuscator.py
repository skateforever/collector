#!/usr/bin/env python3
"""
js_deobfuscator.py — Identifica o(s) tipo(s) de ofuscação presentes num arquivo
JavaScript e aplica a desofuscação correspondente.

Uso:
    python3 js_deobfuscator.py caminho/para/arquivo.js
    python3 js_deobfuscator.py caminho/para/arquivo.js -o saida.js
    python3 js_deobfuscator.py caminho/para/arquivo.js --relatorio-json saida.json

O script NUNCA executa o arquivo inteiro (que poderia ter efeitos colaterais
reais, como iniciar uma aplicação Angular ou fazer requisições de rede).
Quando é necessário rodar código, isso é feito isolando apenas a função
estritamente necessária (ex.: o decodificador de strings) dentro de um
subprocesso Node.js descartável, sem acesso ao DOM/rede/globals da aplicação.
"""

from __future__ import annotations

import argparse
import base64
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from pathlib import Path


# ---------------------------------------------------------------------------
# Estruturas de resultado
# ---------------------------------------------------------------------------

@dataclass
class Deteccao:
    tecnica: str
    confianca: str          # "alta" | "media" | "baixa"
    evidencia: str          # trecho ou contagem que motivou a detecção
    desofuscavel_automatico: bool


@dataclass
class Relatorio:
    arquivo: str
    tamanho_bytes: int
    deteccoes: list[Deteccao] = field(default_factory=list)
    acoes_aplicadas: list[str] = field(default_factory=list)
    avisos: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "arquivo": self.arquivo,
            "tamanho_bytes": self.tamanho_bytes,
            "deteccoes": [vars(d) for d in self.deteccoes],
            "acoes_aplicadas": self.acoes_aplicadas,
            "avisos": self.avisos,
        }


# ---------------------------------------------------------------------------
# 1. IDENTIFICAÇÃO — cada função de detecção corresponde a uma seção do
#    guia desofuscacao-js.md e devolve uma Deteccao (ou None se ausente).
# ---------------------------------------------------------------------------

# Identificador "estilo ofuscador": qualquer identificador JS válido que
# CONTENHA um trecho "0x" + 3-8 dígitos hex em algum lugar do nome. Cobre
# tanto o prefixo clássico "_0x1a2b3c" quanto variantes vistas em diferentes
# versões/CLIs do javascript-obfuscator, como "a0_0x3dfb" ou "a1_0x1a2b".
# Não ancoramos no prefixo "_0x" porque isso quebra silenciosamente sempre
# que o gerador de nomes do ofuscador usar outro prefixo.
IDENT = r"[A-Za-z_$][A-Za-z0-9_$]*"
RE_HEX_IDENT = re.compile(rf"\b{IDENT}0x[0-9a-fA-F]{{3,8}}\b")
RE_HEX_ESCAPE = re.compile(r"\\x[0-9a-fA-F]{2}")
RE_UNICODE_ESCAPE = re.compile(r"\\u[0-9a-fA-F]{4}")
RE_ATOB = re.compile(r"\batob\s*\(")
RE_BASE64_LITERAL = re.compile(r"['\"]([A-Za-z0-9+/]{16,}={0,2})['\"]")
RE_DEAN_EDWARDS = re.compile(
    r"eval\(function\(p,a,c,k,e,[dr]\)"
)
# Função geradora do array de strings: "function NOME(){ const/var/let X = [ ... "
# (estrutural — não depende do prefixo do nome do identificador).
RE_STRING_ARRAY_FN = re.compile(
    rf"function\s+({IDENT})\s*\(\s*\)\s*\{{\s*(?:const|var|let)\s+({IDENT})\s*=\s*\["
)
# A IIFE de shuffle varia na condição de loop ("while(true)" ou "while(!![])")
# e no prefixo dos identificadores — detectamos pela ESTRUTURA (IIFE com 2
# parâmetros contendo um while/try/catch com push/shift), não pelo nome.
RE_SHUFFLE_IIFE = re.compile(
    rf"\(function\s*\(\s*{IDENT}\s*,\s*{IDENT}\s*\)\s*\{{.*?while\s*\(\s*(?:true|!+\s*\[\s*\])\s*\).*?(?:push|shift)",
    re.DOTALL,
)
RE_CONTROL_FLOW_FLATTENING = re.compile(
    r"while\s*\(\s*(?:true|!\s*\[\s*\]\s*)\s*\)\s*\{\s*switch\s*\(",
)
RE_SPLIT_ORDER_ARRAY = re.compile(r"['\"][0-9]+(?:\|[0-9]+){2,}['\"]\s*\.\s*split\s*\(\s*['\"]\|['\"]\s*\)")
RE_DEBUGGER_LOOP = re.compile(r"while\s*\(\s*true\s*\)\s*\{\s*debugger\s*;?\s*\}")
RE_TOSTRING_CHECK = re.compile(r"\.toString\s*\(\s*\)\s*\.\s*(?:search|indexOf|match)\s*\(")
RE_MEMBER_BRACKET_CALL = re.compile(rf"\[\s*{IDENT}\(\s*0x[0-9a-fA-F]+\s*\)\s*\]")


def detectar_minificacao_simples(src: str) -> Deteccao | None:
    """Identificadores curtos de 1-2 chars, mas sem padrão _0x e sem array de strings."""
    curtos = re.findall(r"\b(?:function|const|let|var)\s+([a-zA-Z]{1,2})\b", src)
    if len(curtos) > 20 and not RE_HEX_IDENT.search(src):
        return Deteccao(
            tecnica="Minificação simples (Terser/UglifyJS/esbuild)",
            confianca="media",
            evidencia=f"{len(curtos)} identificadores curtos (1-2 chars) sem padrão _0x",
            desofuscavel_automatico=True,
        )
    return None


def detectar_hex_identificadores(src: str) -> Deteccao | None:
    achados = RE_HEX_IDENT.findall(src)
    if achados:
        return Deteccao(
            tecnica="javascript-obfuscator (identificadores _0x...)",
            confianca="alta",
            evidencia=f"{len(achados)} identificadores no padrão _0x encontrados",
            desofuscavel_automatico=True,
        )
    return None


def _extrair_bloco_balanceado(src: str, inicio: int) -> str | None:
    """A partir de 'inicio' (começo de uma declaração 'function ... {'),
    devolve o texto completo até a chave de fechamento correspondente,
    contando profundidade de chaves (lida com aninhamento interno)."""
    primeira_chave = src.find("{", inicio)
    if primeira_chave == -1:
        return None
    profundidade = 0
    i = primeira_chave
    while i < len(src):
        if src[i] == "{":
            profundidade += 1
        elif src[i] == "}":
            profundidade -= 1
            if profundidade == 0:
                return src[inicio:i + 1]
        i += 1
    return None


def _localizar_decoder(src: str, nome_array_fn: str) -> tuple[str, str] | None:
    """
    Localiza a função decodificadora de forma ESTRUTURAL (comportamento),
    não por um template fixo de texto: procura toda declaração
    'function NOME(...) { ... }' cujo corpo (a) chame a função geradora do
    array de strings já identificada e (b) contenha uma subtração de offset
    hexadecimal típica do padrão 'indice = indice - 0xNNN'. Isso cobre
    variações entre versões/CLIs do javascript-obfuscator sem depender de
    um prefixo de nome específico (ex.: '_0x...' vs 'a0_0x...').
    """
    for m in re.finditer(rf"function\s+({IDENT})\s*\([^)]*\)\s*\{{", src):
        nome_candidato = m.group(1)
        if nome_candidato == nome_array_fn:
            continue
        bloco = _extrair_bloco_balanceado(src, m.start())
        if bloco is None:
            continue
        chama_array_fn = re.search(rf"\b{re.escape(nome_array_fn)}\s*\(", bloco)
        tem_offset = re.search(r"[-+]=?\s*0x[0-9a-fA-F]+", bloco)
        if chama_array_fn and tem_offset:
            return nome_candidato, bloco
    return None


def _localizar_aliases(src: str, nome_decoder: str) -> list[str]:
    """O javascript-obfuscator costuma criar aliases do decodificador em
    MÚLTIPLOS níveis: um alias de módulo (ex.: 'const a0_0x569be1 =
    a0_0x3155;') e, dentro de CADA função que usa o decoder, um segundo
    alias local apontando para o alias de módulo (ex.: 'const _0x214a34 =
    a0_0x569be1;'). Resolvemos de forma transitiva (fecho/BFS): a cada
    rodada, procuramos aliases de QUALQUER nome já conhecido (decoder
    real + aliases achados até agora), até não encontrar mais nenhum novo."""
    conhecidos = {nome_decoder}
    fila = [nome_decoder]
    todos_aliases: list[str] = []
    while fila:
        atual = fila.pop(0)
        # o alias pode ser o único declarador ('const x = y;') ou um entre
        # vários na mesma instrução ('const x = y, outra = {...};') — o
        # terminador aceito é ';' OU ',' (próximo declarador), nunca exigimos
        # que a instrução termine logo ali.
        novos = re.findall(rf"(?:const|let|var)\s+({IDENT})\s*=\s*{re.escape(atual)}\s*[;,]", src)
        for novo in novos:
            if novo not in conhecidos:
                conhecidos.add(novo)
                todos_aliases.append(novo)
                fila.append(novo)
    return todos_aliases


def detectar_string_array_decoder(src: str) -> Deteccao | None:
    fn_match = RE_STRING_ARRAY_FN.search(src)
    if not fn_match:
        return None
    nome_array_fn = fn_match.group(1)
    decoder = _localizar_decoder(src, nome_array_fn)
    if not decoder:
        return None
    nome_decoder, _ = decoder
    aliases = _localizar_aliases(src, nome_decoder)
    shuffle_match = RE_SHUFFLE_IIFE.search(src)
    nota_shuffle = "IIFE de shuffle presente" if shuffle_match else "shuffle IIFE não localizado (array pode já estar na ordem final)"
    nota_alias = f", alias(es) de chamada: {aliases}" if aliases else ""
    return Deteccao(
        tecnica="Array de strings + função decodificadora (string array encoding)",
        confianca="alta",
        evidencia=f"função de array '{nome_array_fn}', decodificador '{nome_decoder}'{nota_alias}. {nota_shuffle}",
        desofuscavel_automatico=True,
    )


def detectar_member_bracket(src: str) -> Deteccao | None:
    achados = RE_MEMBER_BRACKET_CALL.findall(src)
    if len(achados) > 5:
        return Deteccao(
            tecnica="Ofuscação de acesso a propriedades (member expression obfuscation)",
            confianca="alta",
            evidencia=f"{len(achados)} acessos via colchete com chamada decodificadora, ex.: {achados[0]}",
            desofuscavel_automatico=True,  # depende do decoder da seção anterior já resolvido
        )
    return None


def detectar_hex_escapes(src: str) -> Deteccao | None:
    achados = RE_HEX_ESCAPE.findall(src)
    if len(achados) > 10:
        return Deteccao(
            tecnica="Codificação de strings em hex escapes (\\xHH)",
            confianca="alta",
            evidencia=f"{len(achados)} sequências \\xHH encontradas",
            desofuscavel_automatico=True,
        )
    return None


def detectar_unicode_escapes(src: str) -> Deteccao | None:
    achados = RE_UNICODE_ESCAPE.findall(src)
    if len(achados) > 10:
        return Deteccao(
            tecnica="Codificação de strings em unicode escapes (\\uHHHH)",
            confianca="alta",
            evidencia=f"{len(achados)} sequências \\uHHHH encontradas",
            desofuscavel_automatico=True,
        )
    return None


def detectar_base64(src: str) -> Deteccao | None:
    tem_atob = bool(RE_ATOB.search(src))
    candidatos = RE_BASE64_LITERAL.findall(src)
    validos = [c for c in candidatos if _parece_base64_valido(c)]
    if tem_atob and validos:
        return Deteccao(
            tecnica="Codificação Base64 (atob())",
            confianca="alta",
            evidencia=f"atob() presente + {len(validos)} literais candidatos a Base64",
            desofuscavel_automatico=True,
        )
    if validos and not tem_atob:
        return Deteccao(
            tecnica="Possível Base64 com decodificador customizado (sem atob nativo)",
            confianca="baixa",
            evidencia=f"{len(validos)} literais candidatos a Base64, sem chamada a atob()",
            desofuscavel_automatico=False,
        )
    return None


def _parece_base64_valido(s: str) -> bool:
    if len(s) % 4 != 0 or len(s) < 16:
        return False
    try:
        base64.b64decode(s, validate=True)
        return True
    except Exception:
        return False


def detectar_dean_edwards(src: str) -> Deteccao | None:
    if RE_DEAN_EDWARDS.search(src):
        return Deteccao(
            tecnica="Packer estilo Dean Edwards (eval(function(p,a,c,k,e,d){...}(...)))",
            confianca="alta",
            evidencia="Assinatura eval(function(p,a,c,k,e,d) encontrada",
            desofuscavel_automatico=True,
        )
    return None


def detectar_control_flow_flattening(src: str) -> Deteccao | None:
    cff = RE_CONTROL_FLOW_FLATTENING.findall(src)
    ordens = RE_SPLIT_ORDER_ARRAY.findall(src)
    if cff:
        return Deteccao(
            tecnica="Achatamento de fluxo de controle (control flow flattening)",
            confianca="alta" if ordens else "media",
            evidencia=f"{len(cff)} blocos while(true){{switch()}} encontrados"
                      + (f", {len(ordens)} arrays de ordem tipo '2|0|1'.split('|')" if ordens else ""),
            desofuscavel_automatico=False,  # requer análise semântica, não é 1:1 reversível por regex
        )
    return None


def detectar_dead_code_hint(src: str) -> Deteccao | None:
    suspeitos = re.findall(r"Math\.random\s*\(\s*\)\s*[<>]=?\s*[2-9]\d*", src)
    if suspeitos:
        return Deteccao(
            tecnica="Possível injeção de código morto (condição estaticamente impossível)",
            confianca="media",
            evidencia=f"{len(suspeitos)} comparações do tipo Math.random() > N (N>=2, sempre falso)",
            desofuscavel_automatico=False,  # requer leitura humana para confirmar irrelevância
        )
    return None


def detectar_anti_debug(src: str) -> Deteccao | None:
    loop = RE_DEBUGGER_LOOP.search(src)
    checagem = RE_TOSTRING_CHECK.search(src)
    debugger_count = src.count("debugger")
    if loop or (checagem and debugger_count > 0):
        return Deteccao(
            tecnica="Anti-debug / self-defending code",
            confianca="alta" if loop else "media",
            evidencia=(
                f"{'loop while(true){debugger;} encontrado' if loop else 'checagem via toString() + debugger presente'}, "
                f"{debugger_count} ocorrências de 'debugger' no total"
            ),
            desofuscavel_automatico=False,  # mitigação: nunca executar o bundle inteiro
        )
    return None


DETECTORES = [
    detectar_hex_identificadores,
    detectar_string_array_decoder,
    detectar_member_bracket,
    detectar_hex_escapes,
    detectar_unicode_escapes,
    detectar_base64,
    detectar_dean_edwards,
    detectar_control_flow_flattening,
    detectar_dead_code_hint,
    detectar_anti_debug,
    detectar_minificacao_simples,
]


def identificar(src: str) -> list[Deteccao]:
    deteccoes: list[Deteccao] = []
    for detector in DETECTORES:
        resultado = detector(src)
        if resultado is not None:
            deteccoes.append(resultado)
    return deteccoes


# ---------------------------------------------------------------------------
# 2. DESOFUSCAÇÃO — uma função por técnica, todas puras (recebem a string
#    de origem e devolvem a string tratada), exceto a do string-array
#    decoder, que precisa de um subprocess Node isolado para EXECUTAR o
#    decodificador (não há como simular o algoritmo do javascript-obfuscator
#    por regex: o shuffle depende de uma rotação só resolvível rodando a
#    IIFE real extraída do próprio arquivo).
# ---------------------------------------------------------------------------

def desofuscar_hex_escapes(src: str) -> str:
    """\\xHH -> caractere real. Seguro: aplica apenas em literais de string,
    usando o parser de escape do próprio Python (equivalente ao do JS para
    esta sequência, já que ambos seguem a tabela ASCII/Latin-1)."""
    def repl(m: re.Match) -> str:
        return chr(int(m.group(0)[2:], 16))

    # só substitui hex escapes que estejam dentro de literais de string
    # (entre aspas simples/duplas), para não corromper regex literais do
    # próprio bundle que usem \x fora de string.
    def em_strings(match: re.Match) -> str:
        conteudo = match.group(2)
        return match.group(1) + RE_HEX_ESCAPE.sub(repl, conteudo) + match.group(1)

    padrao_string = re.compile(r"(['\"])((?:\\.|(?!\1).)*)\1")
    return padrao_string.sub(em_strings, src)


def desofuscar_unicode_escapes(src: str) -> str:
    def repl(m: re.Match) -> str:
        return chr(int(m.group(0)[2:], 16))

    def em_strings(match: re.Match) -> str:
        conteudo = match.group(2)
        return match.group(1) + RE_UNICODE_ESCAPE.sub(repl, conteudo) + match.group(1)

    padrao_string = re.compile(r"(['\"])((?:\\.|(?!\1).)*)\1")
    return padrao_string.sub(em_strings, src)


def desofuscar_base64(src: str) -> str:
    """Substitui atob("...") por uma string comentada com o valor decodificado,
    preservando a chamada original (não removemos o atob, só anotamos ao
    lado — é mais seguro para não quebrar a sintaxe caso haja falsos positivos)."""
    def repl(m: re.Match) -> str:
        literal = m.group(1)
        try:
            decodificado = base64.b64decode(literal + "=" * (-len(literal) % 4)).decode(
                "utf-8", errors="replace"
            )
        except Exception:
            return m.group(0)
        return f'{m.group(0)} /* decodificado: {decodificado!r} */'

    padrao = re.compile(r"atob\(\s*['\"]([A-Za-z0-9+/=]{8,})['\"]\s*\)")
    return padrao.sub(repl, src)


def desofuscar_dean_edwards(src: str) -> str:
    """Localiza eval(function(p,a,c,k,e,d){...}(ARGUMENTOS)) e EXECUTA só o
    descompactador (sem o eval final) para obter o código-fonte real,
    usando um subprocess Node isolado (sandbox descartável, sem rede/DOM)."""
    match = re.search(r"eval\((function\(p,a,c,k,e,[dr]\)\{.*?\}\s*\(.*?\))\)", src, re.DOTALL)
    if not match:
        return src
    chamada_sem_eval = match.group(1)
    resultado = _executar_em_node_sandbox(f"console.log({chamada_sem_eval});")
    if resultado is None:
        return src
    return src.replace(match.group(0), f"/* DESOFUSCADO (packer Dean Edwards):\n{resultado}\n*/")


def desofuscar_string_array(src: str) -> str | None:
    """
    Reconstrói o decodificador do javascript-obfuscator (array de strings +
    decoder + shuffle IIFE), localizando cada peça de forma ESTRUTURAL
    (ver _localizar_decoder), resolve aliases de nível de módulo
    (const alias = decoderReal;), executa tudo num subprocess Node isolado,
    e substitui toda chamada — via nome real OU via alias — pelo literal
    JSON real correspondente.

    Retorna None se as peças necessárias não puderem ser localizadas.
    """
    fn_match = RE_STRING_ARRAY_FN.search(src)
    if not fn_match:
        return None
    nome_array_fn = fn_match.group(1)

    decoder = _localizar_decoder(src, nome_array_fn)
    if decoder is None:
        return None
    nome_decoder, decoder_src = decoder

    arr_fn_src = _extrair_bloco_balanceado(src, fn_match.start())
    if arr_fn_src is None:
        return None

    # localiza a IIFE de shuffle, se existir (nem todo bundle usa shuffle;
    # alguns já deixam o array na ordem final)
    shuffle_match = RE_SHUFFLE_IIFE.search(src)
    shuffle_src = ""
    if shuffle_match:
        shuffle_src = _extrair_iife_balanceada(src, shuffle_match.start()) or ""

    # resolve alias(es) de nível de módulo que apontam para o decoder real —
    # o resto do arquivo pode chamar o decoder só pelo nome do alias.
    aliases = _localizar_aliases(src, nome_decoder)
    nomes_de_chamada = [nome_decoder] + aliases

    # coleta todos os índices hex usados em QUALQUER um desses nomes
    todos_indices: set[str] = set()
    for nome in nomes_de_chamada:
        todos_indices.update(re.findall(rf"\b{re.escape(nome)}\s*\(\s*(0x[0-9a-fA-F]+)", src))
    if not todos_indices:
        return None

    script_node = f"""
{arr_fn_src}
{decoder_src}
{shuffle_src}
const indices = {json.dumps(sorted(todos_indices))};
const mapa = {{}};
for (const hex of indices) {{
  try {{ mapa[hex] = {nome_decoder}(parseInt(hex, 16)); }}
  catch (e) {{ mapa[hex] = null; }}
}}
console.log(JSON.stringify(mapa));
"""
    saida = _executar_em_node_sandbox(script_node)
    if saida is None:
        return None
    try:
        mapa = json.loads(saida.strip().splitlines()[-1])
    except Exception:
        return None

    # substitui cada chamada NOME(0x....) — real ou alias — pelo literal real
    def repl(m: re.Match) -> str:
        hexval = m.group(2)
        valor = mapa.get(hexval)
        if valor is None:
            return m.group(0)
        return json.dumps(valor, ensure_ascii=False)

    alternancia_nomes = "|".join(re.escape(n) for n in nomes_de_chamada)
    padrao_chamada = re.compile(rf"\b({alternancia_nomes})\s*\(\s*(0x[0-9a-fA-F]+)\s*\)")
    return padrao_chamada.sub(repl, src)


def _extrair_iife_balanceada(src: str, inicio: int) -> str | None:
    """Para a IIFE '(function(a,b){ ... })(args);' — localiza o fechamento
    do parêntese externo contando profundidade de parênteses."""
    profundidade = 0
    i = inicio
    while i < len(src):
        if src[i] == "(":
            profundidade += 1
        elif src[i] == ")":
            profundidade -= 1
            if profundidade == 0:
                # inclui a chamada final "(...)" e o ';' se presente
                fim = i + 1
                while fim < len(src) and src[fim] in "(); \t":
                    if src[fim] == ";":
                        fim += 1
                        break
                    fim += 1
                return src[inicio:fim]
        i += 1
    return None


def _executar_em_node_sandbox(script: str, timeout: int = 10) -> str | None:
    """Executa um trecho de JS num subprocess Node descartável. O script
    roda SEM qualquer módulo externo, SEM acesso a rede/DOM/filesystem do
    projeto (não passamos --allow-* nem requires), e com timeout curto —
    é um sandbox de leitura, nunca o bundle completo da aplicação."""
    if shutil.which("node") is None:
        return None
    with tempfile.NamedTemporaryFile(mode="w", suffix=".js", delete=False) as f:
        f.write(script)
        caminho = f.name
    try:
        resultado = subprocess.run(
            ["node", "--jitless", caminho],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if resultado.returncode != 0:
            print(f"[aviso] Node retornou erro ao executar sandbox:\n{resultado.stderr}", file=sys.stderr)
            return None
        return resultado.stdout
    except subprocess.TimeoutExpired:
        print("[aviso] Timeout ao executar sandbox Node (possível loop infinito/anti-debug).", file=sys.stderr)
        return None
    finally:
        Path(caminho).unlink(missing_ok=True)


# ---------------------------------------------------------------------------
# 3. ORQUESTRAÇÃO
# ---------------------------------------------------------------------------

def processar_arquivo(caminho: Path) -> tuple[Relatorio, str]:
    src = caminho.read_text(encoding="utf-8", errors="replace")
    relatorio = Relatorio(arquivo=str(caminho), tamanho_bytes=len(src.encode("utf-8")))
    relatorio.deteccoes = identificar(src)

    tecnicas_encontradas = {d.tecnica for d in relatorio.deteccoes}
    atual = src

    if any("Array de strings" in t for t in tecnicas_encontradas):
        novo = desofuscar_string_array(atual)
        if novo is not None:
            atual = novo
            relatorio.acoes_aplicadas.append(
                "Array de strings + decodificador: reconstruído e executado em sandbox Node; "
                "chamadas ao decodificador substituídas pelos literais reais."
            )
        else:
            relatorio.avisos.append(
                "Array de strings detectado, mas não foi possível isolar as 3 peças "
                "(array/stub/shuffle) automaticamente — requer extração manual (ver "
                "desofuscacao-js.md, seção 3.4)."
            )

    if any("Dean Edwards" in t for t in tecnicas_encontradas):
        atual = desofuscar_dean_edwards(atual)
        relatorio.acoes_aplicadas.append(
            "Packer Dean Edwards: descompactador executado isoladamente em sandbox Node "
            "(sem o eval final), código real anotado inline."
        )

    if any("hex escapes" in t for t in tecnicas_encontradas):
        atual = desofuscar_hex_escapes(atual)
        relatorio.acoes_aplicadas.append("Hex escapes (\\xHH) decodificados dentro de literais de string.")

    if any("unicode escapes" in t for t in tecnicas_encontradas):
        atual = desofuscar_unicode_escapes(atual)
        relatorio.acoes_aplicadas.append("Unicode escapes (\\uHHHH) decodificados dentro de literais de string.")

    if any("Base64" in t and "customizado" not in t for t in tecnicas_encontradas):
        atual = desofuscar_base64(atual)
        relatorio.acoes_aplicadas.append("Literais Base64 em atob(...) anotados com o valor decodificado.")

    for d in relatorio.deteccoes:
        if not d.desofuscavel_automatico:
            relatorio.avisos.append(
                f"'{d.tecnica}' requer análise manual (ver desofuscacao-js.md) — não aplicado automaticamente."
            )

    return relatorio, atual


def imprimir_relatorio_humano(relatorio: Relatorio) -> None:
    print(f"\n=== Relatório de identificação — {relatorio.arquivo} ===")
    print(f"Tamanho: {relatorio.tamanho_bytes} bytes\n")

    if not relatorio.deteccoes:
        print("Nenhuma técnica de ofuscação conhecida foi identificada.")
    else:
        print("Técnicas identificadas:")
        for d in relatorio.deteccoes:
            marca = "automática" if d.desofuscavel_automatico else "MANUAL"
            print(f"  [{d.confianca.upper():6}] {d.tecnica}  (desofuscação: {marca})")
            print(f"           evidência: {d.evidencia}")

    if relatorio.acoes_aplicadas:
        print("\nAções de desofuscação aplicadas:")
        for a in relatorio.acoes_aplicadas:
            print(f"  - {a}")

    if relatorio.avisos:
        print("\nAvisos / pontos que exigem revisão manual:")
        for a in relatorio.avisos:
            print(f"  ! {a}")
    print()


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Identifica e desofusca um arquivo JavaScript (ver desofuscacao-js.md)."
    )
    parser.add_argument("arquivo", type=Path, help="Caminho do arquivo .js a analisar")
    parser.add_argument("-o", "--saida", type=Path, help="Caminho para salvar o JS desofuscado")
    parser.add_argument("--relatorio-json", type=Path, help="Caminho para salvar o relatório em JSON")
    parser.add_argument(
        "--apenas-identificar", action="store_true",
        help="Só roda a identificação, sem tentar desofuscar nem gerar saída"
    )
    args = parser.parse_args()

    if not args.arquivo.exists():
        print(f"Erro: arquivo não encontrado: {args.arquivo}", file=sys.stderr)
        sys.exit(1)

    if args.apenas_identificar:
        src = args.arquivo.read_text(encoding="utf-8", errors="replace")
        relatorio = Relatorio(arquivo=str(args.arquivo), tamanho_bytes=len(src.encode("utf-8")))
        relatorio.deteccoes = identificar(src)
    else:
        relatorio, resultado = processar_arquivo(args.arquivo)
        if args.saida:
            args.saida.write_text(resultado, encoding="utf-8")
            print(f"Arquivo desofuscado salvo em: {args.saida}")

    imprimir_relatorio_humano(relatorio)

    if args.relatorio_json:
        args.relatorio_json.write_text(
            json.dumps(relatorio.to_dict(), indent=2, ensure_ascii=False), encoding="utf-8"
        )
        print(f"Relatório JSON salvo em: {args.relatorio_json}")


if __name__ == "__main__":
    main()
