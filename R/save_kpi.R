# =============================================================================
# save_kpi: grava um mes de dados crus em parquet e/ou CSV
#
# Layout no destino (out_dir aponta para a pasta sincronizada do SharePoint):
#   out_dir/<kpi>/<YYYY-MM>.parquet
#   out_dir/<kpi>/<YYYY-MM>.csv
#
# Um arquivo por (kpi, mes): imutavel, facil de juntar na leitura e permite a
# extracao ser idempotente (ver download_kpi).
#
# Requer: arrow, readr, fs
# =============================================================================

library(arrow)
library(readr)
library(fs)

save_kpi <- function(df, kpi, year, month, out_dir,
                     formats = c("parquet", "csv")) {

  stopifnot(is.data.frame(df))

  dir   <- fs::path(out_dir, kpi)
  fs::dir_create(dir)
  stamp <- sprintf("%04d-%02d", year, month)

  paths <- character(0)

  if ("parquet" %in% formats) {
    p <- fs::path(dir, paste0(stamp, ".parquet"))
    arrow::write_parquet(df, p)
    paths <- c(paths, p)
  }

  if ("csv" %in% formats) {
    p <- fs::path(dir, paste0(stamp, ".csv"))
    readr::write_csv(df, p)
    paths <- c(paths, p)
  }

  message(sprintf("Salvo %s %s: %d linhas -> %s",
                  kpi, stamp, nrow(df),
                  paste(basename(paths), collapse = ", ")))
  invisible(paths)
}
