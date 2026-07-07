# =============================================================================
# run_extraction.R  --  fluxo completo em 3 passos
# =============================================================================

# 1) SPECS: carrega o config (edite R/1_config.R para mudar pasta, aeroportos...)
source("R/1_config.R")
source("R/2_extract.R")
source("R/3_read.R")

# -----------------------------------------------------------------------------
# 2) DOWNLOAD do ano (idempotente: pula os meses que ja existem)
# -----------------------------------------------------------------------------
extract(2026, config)                       # todos os KPIs, ano inteiro
# extract(2026, config, kpis = "kpi04")     # so um KPI
# extract(2026, config, months = 1:6)       # so jan-jun
# extract(2026, config, overwrite = TRUE)   # forca re-baixar tudo

# -----------------------------------------------------------------------------
# 3) LEITURA / CONSOLIDACAO
# -----------------------------------------------------------------------------

# (a) juntar na memoria para usar no relatorio
df_kpi04 <- read_kpi("kpi04", config)                    # tudo que existe
df_2026  <- read_kpi("kpi04", config, year = 2026)       # so 2026

# (b) gerar o arquivo unico do ano em _consolidado/
read_kpi("kpi04", config, year = 2026, consolidate = TRUE)

# (c) consolidar TODOS os KPIs de um ano de uma vez
for (k in names(config$kpis)) {
  read_kpi(k, config, year = 2026, consolidate = TRUE)
}

# -----------------------------------------------------------------------------
# Estrutura resultante em out_dir:
#   KPI04_KEP/2026-01.parquet (+ .csv)   <- mensais (fonte da verdade)
#   KPI04_KEP/2026-02.parquet ...
#   KPI05_KEA/ ...
#   _consolidado/KPI04_KEP_2026.parquet (+ .csv)   <- ano inteiro num arquivo
#   _consolidado/KPI05_KEA_2026.parquet ...
# -----------------------------------------------------------------------------
