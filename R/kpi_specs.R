# =============================================================================
# kpi_specs: configuracao por KPI
#
# A engine (fetch_kpi) e generica; tudo que muda entre uma API e outra fica
# descrito aqui. Para incluir uma API nova, basta adicionar um item nesta lista
# -- nao precisa duplicar loop, retry nem parsing.
#
# Campos do spec:
#   endpoint     : caminho apos /api/  (ex.: "kpi04", "kpi05_cat62")
#   out_name     : nome da PASTA de saida no destino (ex.: "KPI04_KEP").
#                  Separa o nome interno (usado na URL) do nome da pasta.
#                  Se ausente, usa a propria chave do KPI (ex.: "kpi04").
#   time_field   : nome do parametro de tempo na query (ex.: "time", "aldt")
#   query_fields : campos usados no filtro por aeroporto (um request por campo)
#   group_size   : tamanho do grupo de aeroportos por request (Inf = todos juntos)
#   dedup_key    : coluna para distinct() apos juntar (NULL = sem dedup)
#   keep_mode    : quais voos manter apos baixar:
#                    "all"  -> TODOS os query_fields dentro dos aeroportos (E)
#                    "any"  -> QUALQUER query_field dentro dos aeroportos (OU)
#                    "none" -> nao filtra
#   limit        : (opcional) valor do parametro &limit= por request
# =============================================================================

# 12 maiores aeroportos do Brasil (default)
.airports_brazil <- c("SBSP", "SBGR", "SBKP",
                      "SBBR", "SBEG", "SBRF",
                      "SBSV", "SBRJ", "SBPA",
                      "SBCF", "SBGL", "SBCT")

kpi_specs <- list(

  kpi04 = list(
    out_name     = "KPI04_KEP",
    endpoint     = "kpi04",
    time_field   = "time",
    query_fields = c("orig", "dest"),
    group_size   = 3,
    dedup_key    = "indicat",
    keep_mode    = "all"        # voos ENTRE os aeroportos (orig E dest na lista)
  ),

  kpi05 = list(
    out_name     = "KPI05_KEA",
    endpoint     = "kpi05_cat62",
    time_field   = "time",
    query_fields = c("plan_dep", "real_arr", "plan_arr"),
    group_size   = Inf,
    dedup_key    = "indicat",
    keep_mode    = "any"        # pelo menos um campo na lista
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

# -----------------------------------------------------------------------------
# kpi_folder(kpi): nome da pasta de saida para um KPI.
# Usa spec$out_name; se ausente, a propria chave (ex.: "kpi04").
# -----------------------------------------------------------------------------
kpi_folder <- function(kpi) {
  nm <- kpi_specs[[kpi]]$out_name
  if (is.null(nm)) kpi else nm
}
