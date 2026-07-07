# =============================================================================
# download_kpi / download_kpi_range: orquestracao idempotente
#
# download_kpi() baixa UM mes de UM KPI apenas se ainda nao existir no destino,
# grava em parquet/CSV e retorna o caminho. Como a API do DECEA e instavel,
# ser idempotente evita rebaixar meses ja obtidos.
#
# download_kpi_range() percorre um intervalo de meses ("YYYY-MM" ate "YYYY-MM").
#
# Requer: fs  (+ fetch_kpi.R e save_kpi.R carregados antes)
# =============================================================================

library(fs)

# -----------------------------------------------------------------------------
# download_kpi(kpi, year, month, out_dir, ...)
#   overwrite : TRUE refaz mesmo que o arquivo ja exista (default FALSE)
#   ...       : repassado a fetch_kpi() (airports, timeout, verbose)
# -----------------------------------------------------------------------------
download_kpi <- function(kpi, year, month, out_dir,
                         airports  = .airports_brazil,
                         formats   = c("parquet", "csv"),
                         overwrite = FALSE,
                         ...) {

  stamp   <- sprintf("%04d-%02d", year, month)
  pq_path <- fs::path(out_dir, kpi_folder(kpi), paste0(stamp, ".parquet"))

  if (!overwrite && fs::file_exists(pq_path)) {
    message(sprintf("Ja existe %s %s -- pulando (overwrite=TRUE para refazer).",
                    kpi, stamp))
    return(invisible(pq_path))
  }

  df <- fetch_kpi(kpi, year, month, airports = airports, ...)

  if (nrow(df) == 0) {
    warning(sprintf("%s %s retornou 0 linhas -- nada gravado.", kpi, stamp))
    return(invisible(NULL))
  }

  save_kpi(df, kpi, year, month, out_dir, formats = formats)
}

# -----------------------------------------------------------------------------
# download_kpi_range(kpi, from, to, out_dir, ...)
#   from, to : "YYYY-MM" (inclusive nas duas pontas)
# -----------------------------------------------------------------------------
download_kpi_range <- function(kpi, from, to, out_dir, ...) {

  months <- seq(as.Date(paste0(from, "-01")),
                as.Date(paste0(to,   "-01")),
                by = "month")

  for (i in seq_along(months)) {
    d <- months[i]
    download_kpi(kpi,
                 year    = as.integer(format(d, "%Y")),
                 month   = as.integer(format(d, "%m")),
                 out_dir = out_dir,
                 ...)
  }
  invisible(NULL)
}
