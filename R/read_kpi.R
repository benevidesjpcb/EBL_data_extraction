# =============================================================================
# read_kpi: le e junta todos os meses ja baixados de um KPI
#
# Le os parquet salvos em out_dir/<out_name>/*.parquet e concatena num unico
# data frame -- assim voce nunca precisa juntar meses "na mao".
# (out_name vem de kpi_folder(kpi), ex.: "KPI04_KEP" para "kpi04".)
#
# Requer: arrow, fs, purrr, dplyr
# =============================================================================

library(arrow)
library(fs)
library(purrr)
library(dplyr)

# -----------------------------------------------------------------------------
# read_kpi(kpi, out_dir, from = NULL, to = NULL)
#   from, to : (opcional) "YYYY-MM" para limitar o intervalo lido
# -----------------------------------------------------------------------------
read_kpi <- function(kpi, out_dir, from = NULL, to = NULL) {

  dir <- fs::path(out_dir, kpi_folder(kpi))
  if (!fs::dir_exists(dir))
    stop(sprintf("Sem dados para '%s' em %s", kpi, dir))

  files <- fs::dir_ls(dir, glob = "*.parquet")
  if (length(files) == 0)
    stop(sprintf("Nenhum parquet encontrado em %s", dir))

  # Filtra por intervalo pelo nome do arquivo (YYYY-MM.parquet)
  stamps <- fs::path_ext_remove(fs::path_file(files))
  if (!is.null(from)) files <- files[stamps >= from]
  if (!is.null(to))   files <- files[stamps <= to]

  if (length(files) == 0)
    stop("Nenhum arquivo no intervalo pedido.")

  files |> map(arrow::read_parquet) |> bind_rows()
}
