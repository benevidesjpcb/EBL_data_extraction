# EBL-data-extraction

Extração de dados crus das APIs de KPI do **ODIN/ICEA (DECEA)**.

Uma **engine genérica** (`fetch_kpi`) busca qualquer KPI descrito em
`R/kpi_specs.R`; a escrita é **idempotente**, salvando **um arquivo por mês**
(parquet + CSV) numa pasta do **SharePoint**. Este repositório guarda apenas o
**código** — os dados crus não são versionados (ver `.gitignore`).

## Estrutura

```
R/
  kpi_specs.R      # config por KPI (endpoint, campos, dedup, filtro)
  fetch_kpi.R      # engine genérica (loop de dias + retry + parse)
  save_kpi.R       # grava parquet + CSV, um arquivo por mês
  download_kpi.R   # orquestração idempotente (pula mês já baixado) + range
  read_kpi.R       # lê e junta todos os meses de um KPI
  00_load.R        # carrega tudo de uma vez
scripts/
  run_extraction.R # exemplo de uso
```

## Instalação (uma vez)

```r
install.packages(c("httr2", "jsonlite", "purrr", "dplyr",
                   "arrow", "readr", "fs"))
```

## Uso

```r
source("R/00_load.R")

OUT_DIR <- "C:/Users/jbenevid/<PASTA_SHAREPOINT>/dados_crus"

# um mês
download_kpi("kpi04", 2025, 1, out_dir = OUT_DIR)

# vários meses (pula os que já existem)
download_kpi_range("kpi04", from = "2025-01", to = "2025-06", out_dir = OUT_DIR)

# todos os KPIs de um mês
for (k in names(kpi_specs)) download_kpi(k, 2025, 1, out_dir = OUT_DIR)

# ler tudo junto para o relatório
df <- read_kpi("kpi04", OUT_DIR)
```

Saída no destino:

```
<OUT_DIR>/kpi04/2025-01.parquet
<OUT_DIR>/kpi04/2025-01.csv
<OUT_DIR>/kpi04/2025-02.parquet
...
```

## Adicionar um KPI novo

Basta acrescentar um item em `R/kpi_specs.R` — sem tocar na engine:

```r
kpiXX = list(
  endpoint     = "kpiXX",           # caminho após /api/
  time_field   = "time",            # nome do parâmetro de tempo
  query_fields = c("orig", "dest"), # campos de filtro por aeroporto
  group_size   = Inf,               # aeroportos por request (3 no kpi04)
  dedup_key    = "indicat",         # coluna do distinct (NULL = sem dedup)
  keep_mode    = "all"              # "all" | "any" | "none"
  # limit      = 10000              # opcional
)
```

## Notas sobre a API do DECEA

- É instável: alterna entre `HTTP 503 PGRST002` ("schema cache"), respostas
  vazias e timeouts. A engine já re-tenta 503 **e** timeouts com backoff
  exponencial (`req_retry(..., retry_on_failure = TRUE)`).
- Se, mesmo assim, um mês vier vazio, teste a URL no navegador — se ela também
  falhar, a API está fora do ar; é aguardar e rodar de novo (a idempotência
  garante que você só rebaixa o que faltou).
