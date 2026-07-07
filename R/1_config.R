# =============================================================================
# 1_config.R  --  SPECS: defina tudo aqui
#
# Este e o unico arquivo que voce edita no dia a dia. Aqui ficam:
#   - a pasta de saida (SharePoint sincronizado)
#   - os aeroportos
#   - os formatos de arquivo
#   - a definicao de cada KPI (endpoint, filtros, pasta de saida...)
#
# Ordem de uso:  1_config.R  ->  2_extract.R  ->  3_read.R
# =============================================================================

config <- list(

  # --- pasta raiz de saida (OneDrive/SharePoint sincronizado) ---------------
  out_dir = "C:/Users/jbenevid/OneDrive - EUROCONTROL/ANS Performance Benchmarking - 2026",

  # subpasta (dentro de out_dir) onde ficam os arquivos consolidados do ano
  consolidated_dir = "_consolidado",

  # --- aeroportos: 12 maiores do Brasil -------------------------------------
  airports = c("SBSP", "SBGR", "SBKP",
               "SBBR", "SBEG", "SBRF",
               "SBSV", "SBRJ", "SBPA",
               "SBCF", "SBGL", "SBCT"),

  # --- formatos de saida ----------------------------------------------------
  formats = c("parquet", "csv"),

  # --- base da API do ODIN/ICEA (DECEA) -------------------------------------
  base_url = "https://odin-ms.icea.decea.mil.br/api",

  # --- definicao de cada KPI ------------------------------------------------
  # Campos:
  #   out_name     : nome da PASTA de saida (ex.: "KPI04_KEP")
  #   endpoint     : caminho apos /api/    (ex.: "kpi04", "kpi05_cat62")
  #   time_field   : parametro de tempo    (ex.: "time", "aldt")
  #   query_fields : campos de filtro por aeroporto (1 request por campo)
  #   group_size   : aeroportos por request (Inf = todos de uma vez; 3 no kpi04)
  #   dedup_key    : coluna do distinct()  (NULL = sem dedup)
  #   keep_mode    : "all" (todos os campos na lista) | "any" | "none"
  #   limit        : (opcional) valor do &limit= por request
  kpis = list(

    kpi04 = list(
      out_name     = "KPI04_KEP",
      endpoint     = "kpi04",
      time_field   = "time",
      query_fields = c("orig", "dest"),
      group_size   = 3,
      dedup_key    = "indicat",
      keep_mode    = "all"
    ),

    kpi05 = list(
      out_name     = "KPI05_KEA",
      endpoint     = "kpi05_cat62",
      time_field   = "time",
      query_fields = c("plan_dep", "real_arr", "plan_arr"),
      group_size   = Inf,
      dedup_key    = "indicat",
      keep_mode    = "any"
    ),

    kpi08 = list(
      out_name     = "KPI08",
      endpoint     = "kpi08",
      time_field   = "aldt",
      query_fields = c("ades"),
      group_size   = Inf,
      dedup_key    = NULL,
      keep_mode    = "none"
    ),

    kpi17 = list(
      out_name     = "KPI17",
      endpoint     = "kpi17_cat62",
      time_field   = "time",
      query_fields = c("plan_dep"),
      group_size   = Inf,
      dedup_key    = NULL,
      keep_mode    = "none",
      limit        = 10000
    )
  )
)
