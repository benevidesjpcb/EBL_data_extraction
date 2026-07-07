# =============================================================================
# 3_read.R  --  LEITURA: junta os meses (e, se quiser, gera o arquivo do ano)
#
# read_kpi(kpi, config, ...) le todos os parquet mensais da pasta do KPI e
# devolve UM data frame (ano inteiro empilhado). Opcionalmente grava tambem um
# arquivo consolidado unico em out_dir/_consolidado/.
#
# Requer: arrow, readr, fs, purrr, dplyr
# =============================================================================

library(arrow)
library(readr)
library(fs)
library(purrr)
library(dplyr)

# -----------------------------------------------------------------------------
# read_kpi(kpi, config, year, from, to, consolidate)
#   year        : (opcional) le so aquele ano (ex.: 2026)
#   from, to    : (opcional) intervalo "YYYY-MM" (ignorado se 'year' for dado)
#   consolidate : TRUE grava tambem UM arquivo unico em _consolidado/
#                 (nomeado <out_name>_<ano>.parquet/.csv). Requer 'year'.
#
# Retorna sempre o data frame juntado (invisivel nao; retorna visivel).
# -----------------------------------------------------------------------------
read_kpi <- function(kpi, config,
                     year        = NULL,
                     from        = NULL,
                     to          = NULL,
                     consolidate = FALSE) {

  spec <- config$kpis[[kpi]]
  if (is.null(spec)) stop(sprintf("KPI '%s' nao existe no config.", kpi))

  dir <- fs::path(config$out_dir, spec$out_name)
  if (!fs::dir_exists(dir))
    stop(sprintf("Sem dados para '%s' em %s", kpi, dir))

  files <- fs::dir_ls(dir, glob = "*.parquet")
  if (length(files) == 0)
    stop(sprintf("Nenhum parquet encontrado em %s", dir))

  # filtro por ano ou intervalo (pelo nome YYYY-MM.parquet)
  if (!is.null(year)) {
    from <- sprintf("%04d-01", year)
    to   <- sprintf("%04d-12", year)
  }
  stamps <- fs::path_ext_remove(fs::path_file(files))
  if (!is.null(from)) files <- files[stamps >= from]
  if (!is.null(to))   files <- files[stamps <= to]

  if (length(files) == 0)
    stop("Nenhum arquivo no intervalo pedido.")

  df <- files |> map(arrow::read_parquet) |> bind_rows()

  # --- opcional: gravar o arquivo consolidado do ano -----------------------
  if (isTRUE(consolidate)) {
    if (is.null(year))
      stop("Para consolidar, informe 'year' (ex.: read_kpi(..., year = 2026, consolidate = TRUE)).")

    cons_dir <- fs::path(config$out_dir, config$consolidated_dir)
    fs::dir_create(cons_dir)
    label <- sprintf("%s_%d", spec$out_name, year)

    if ("parquet" %in% config$formats)
      arrow::write_parquet(df, fs::path(cons_dir, paste0(label, ".parquet")))
    if ("csv" %in% config$formats)
      readr::write_csv(df, fs::path(cons_dir, paste0(label, ".csv")))

    message(sprintf("Consolidado %s: %d linhas -> %s/",
                    label, nrow(df), config$consolidated_dir))
  }

  df
}
