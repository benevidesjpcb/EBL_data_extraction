# EBL_data_extraction

Extração de dados crus das APIs de KPI do **ODIN/ICEA (DECEA)**, em **3 passos**:

```
1_config.R   →   2_extract.R   →   3_read.R
  (specs)         (download)        (leitura / consolidação)
```

O repositório guarda apenas o **código**. Os dados crus vão para uma pasta do
**SharePoint** (sincronizada pelo OneDrive) e não são versionados no git.

## Estrutura

```
R/
  1_config.R   # SPECS: pasta de saída, aeroportos, formatos e os KPIs
  2_extract.R  # DOWNLOAD do ano (idempotente) + salva 1 arquivo por mês
  3_read.R     # LEITURA: junta os meses; opcionalmente gera o arquivo do ano
scripts/
  run_extraction.R  # exemplo do fluxo completo
```

## Instalação (uma vez)

```r
install.packages(c("httr2", "jsonlite", "purrr", "dplyr",
                   "arrow", "readr", "fs"))
```

## Uso — os 3 passos

```r
# 1) specs
source("R/1_config.R")
source("R/2_extract.R")
source("R/3_read.R")

# 2) baixa o ano (só bate na API nos meses que faltam)
extract(2026, config)

# 3) usa os dados
df <- read_kpi("kpi04", config, year = 2026)                 # junta na memória
read_kpi("kpi04", config, year = 2026, consolidate = TRUE)   # gera o arquivo do ano
```

## Como funciona a idempotência

`extract()` percorre os meses e, **antes de cada um**, verifica se o arquivo
mensal já existe na pasta:

- **existe** → pula, não vai na API (já tem o dado);
- **não existe** → baixa e salva.

Assim você pode rodar `extract(2026, config)` quantas vezes quiser: ele só
baixa o que falta — essencial dado que a API do DECEA é instável.

- **Mês corrente** (ainda incompleto) é **re-baixado sempre** por padrão
  (`refresh_current = TRUE`), para ir completando o mês em andamento.
- **Mês vazio** (API fora do ar / sem dado) **não gera arquivo**, então na
  próxima execução ele é tentado de novo.
- Para forçar tudo: `extract(2026, config, overwrite = TRUE)`.

## Estrutura de saída (na pasta do SharePoint)

```
<out_dir>/
├── KPI04_KEP/                 ← mensais (fonte da verdade, idempotência)
│   ├── 2026-01.parquet + .csv
│   ├── 2026-02.parquet + .csv
│   └── ...
├── KPI05_KEA/ ...
├── KPI08/ ...
├── KPI17/ ...
└── _consolidado/              ← ano inteiro num arquivo só, por KPI
    ├── KPI04_KEP_2026.parquet + .csv
    └── KPI05_KEA_2026.parquet + .csv
```

O consolidado é **derivado** dos mensais (regenerável a qualquer momento); os
arquivos mensais continuam sendo a fonte da verdade.

## Configuração — pastas por KPI

Em `R/1_config.R`, cada KPI tem um `out_name` (nome da pasta de saída),
separado do nome interno usado na URL da API:

| KPI (interno / URL) | pasta de saída |
|---------------------|----------------|
| kpi04               | `KPI04_KEP`    |
| kpi05               | `KPI05_KEA`    |
| kpi08               | `KPI08`        |
| kpi17               | `KPI17`        |

## Adicionar um KPI novo

Acrescente um item em `config$kpis` (em `R/1_config.R`) — sem tocar na engine:

```r
kpiXX = list(
  out_name     = "KPIXX",           # nome da pasta de saída
  endpoint     = "kpiXX",           # caminho após /api/
  time_field   = "time",            # parâmetro de tempo
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
- Se um mês vier vazio, teste a URL no navegador — se ela também falhar, a API
  está fora do ar; é aguardar e rodar de novo (a idempotência garante que você
  só rebaixa o que faltou).
