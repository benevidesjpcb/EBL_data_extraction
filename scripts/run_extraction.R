# =============================================================================
# run_extraction.R: exemplo de uso da engine
#
# Ajuste OUT_DIR para a sua pasta do SharePoint sincronizada pelo OneDrive.
# =============================================================================

source("R/00_load.R")

# >>> AJUSTE AQUI <<< pasta do SharePoint (sincronizada localmente pelo OneDrive)
OUT_DIR <- "C:/Users/jbenevid/<PASTA_SHAREPOINT>/dados_crus"

# -----------------------------------------------------------------------------
# 1) Um mes de um KPI
# -----------------------------------------------------------------------------
download_kpi("kpi04", 2025, 1, out_dir = OUT_DIR)

# -----------------------------------------------------------------------------
# 2) Varios meses de um KPI (idempotente: pula os que ja existem)
# -----------------------------------------------------------------------------
download_kpi_range("kpi04", from = "2025-01", to = "2025-06", out_dir = OUT_DIR)

# -----------------------------------------------------------------------------
# 3) Todos os KPIs para um mes
# -----------------------------------------------------------------------------
for (k in names(kpi_specs)) {
  download_kpi(k, 2025, 1, out_dir = OUT_DIR)
}

# -----------------------------------------------------------------------------
# 4) Ler tudo junto (todos os meses ja baixados) para usar no relatorio
# -----------------------------------------------------------------------------
df_kpi04 <- read_kpi("kpi04", OUT_DIR)                       # tudo
df_1sem  <- read_kpi("kpi04", OUT_DIR, from = "2025-01", to = "2025-06")

# -----------------------------------------------------------------------------
# 5) Refazer um mes especifico (forcar novo download)
# -----------------------------------------------------------------------------
# download_kpi("kpi04", 2025, 1, out_dir = OUT_DIR, overwrite = TRUE)

# -----------------------------------------------------------------------------
# 6) Aeroportos customizados / so parquet
# -----------------------------------------------------------------------------
# download_kpi("kpi04", 2025, 1, out_dir = OUT_DIR,
#              airports = c("SBGR", "SBSP"), formats = "parquet")
