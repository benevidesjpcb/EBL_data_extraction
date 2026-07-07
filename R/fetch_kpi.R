# =============================================================================
# fetch_kpi: engine generica de extracao das APIs de KPI do ODIN/ICEA (DECEA)
#
# Uma unica funcao busca qualquer KPI descrito em kpi_specs (R/kpi_specs.R).
# As diferencas entre KPIs (endpoint, campo de tempo, campos de filtro, dedup,
# regra de "voos entre aeroportos") vivem no spec, nao no codigo.
#
# Robustez: req_retry() com backoff exponencial, re-tentando tanto os erros
# transitorios da API (HTTP 503 PGRST002 "schema cache") quanto falhas de
# conexao (timeout / conexao caida). A API do DECEA e instavel, entao isso e
# essencial.
#
# Requer: httr2, jsonlite, purrr, dplyr
# =============================================================================

library(httr2)
library(jsonlite)
library(purrr)
library(dplyr)

.BASE_URL <- "https://odin-ms.icea.decea.mil.br/api"

# -----------------------------------------------------------------------------
# fetch_kpi(kpi, year, month, ...)
#   kpi      : nome do KPI (chave em kpi_specs), ex.: "kpi04"
#   year     : ano  (ex.: 2025)
#   month    : mes  (1-12)
#   airports : vetor de codigos ICAO (default: 12 maiores do Brasil)
#   timeout  : timeout por request, em segundos (default: 120)
#   verbose  : imprime progresso (default: TRUE)
#
# Retorna um data frame (todas as colunas como character, cru).
# -----------------------------------------------------------------------------
fetch_kpi <- function(kpi,
                      year,
                      month,
                      airports = .airports_brazil,
                      spec     = kpi_specs[[kpi]],
                      timeout  = 120,
                      verbose  = TRUE) {

  if (is.null(spec))
    stop(sprintf("KPI '%s' nao encontrado em kpi_specs.", kpi))

  start_date <- as.Date(sprintf("%04d-%02d-01", year, month))
  end_date   <- as.Date(format(start_date + 32, "%Y-%m-01")) - 1
  dates      <- seq(start_date, end_date, by = "day")

  if (verbose) cat("Fetching", kpi, "-", format(start_date, "%B/%Y"),
                   "-", length(dates), "dias\n")

  # Divide os aeroportos em grupos (kpi04 usa 3; demais, todos de uma vez)
  gsize  <- if (is.null(spec$group_size)) Inf else spec$group_size
  groups <- if (is.infinite(gsize)) list(airports)
            else split(airports, ceiling(seq_along(airports) / gsize))

  # --- uma requisicao, com retry e parse ------------------------------------
  fetch_one <- function(url) {
    tryCatch({
      resp <- request(url) |>
        req_timeout(timeout) |>
        req_retry(
          max_tries        = 6,
          retry_on_failure = TRUE,   # re-tenta timeout / conexao caida tambem
          is_transient     = ~ resp_status(.x) %in% c(429, 500, 502, 503),
          backoff          = ~ min(2 ^ .x, 60)
        ) |>
        req_perform()

      body <- resp_body_string(resp)
      if (is.na(body) || nchar(body) < 3) return(NULL)

      df <- fromJSON(body, flatten = TRUE)
      if (!is.data.frame(df) || nrow(df) == 0) return(NULL)

      df |> mutate(across(everything(), as.character))
    }, error = function(e) {
      if (verbose) cat("\n   ERRO:", conditionMessage(e), "\n")
      NULL
    })
  }

  # --- um dia ----------------------------------------------------------------
  fetch_day <- function(date) {
    d0 <- format(date, "%Y-%m-%d")
    d1 <- format(date + 1, "%Y-%m-%d")
    if (verbose) cat("  ", d0, "... ")

    urls <- groups |>
      map(function(grp) {
        filt <- paste0("in.(", paste(grp, collapse = ","), ")")
        map_chr(spec$query_fields, function(field) {
          u <- paste0(.BASE_URL, "/", spec$endpoint, "?",
                      spec$time_field, "=gte.", d0, "&",
                      spec$time_field, "=lt.",  d1, "&",
                      field, "=", filt)
          if (!is.null(spec$limit)) u <- paste0(u, "&limit=", spec$limit)
          u
        })
      }) |>
      unlist()

    df_day <- urls |> map(fetch_one) |> compact() |> bind_rows()

    # dedup opcional
    if (!is.null(spec$dedup_key) && nrow(df_day) > 0 &&
        spec$dedup_key %in% colnames(df_day)) {
      df_day <- df_day |> distinct(.data[[spec$dedup_key]], .keep_all = TRUE)
    }

    # keep: voos "entre" os aeroportos selecionados
    if (nrow(df_day) > 0 && spec$keep_mode != "none") {
      fields <- intersect(spec$query_fields, colnames(df_day))
      if (length(fields) == 0) {
        if (verbose) cat("(sem colunas ", paste(spec$query_fields, collapse = "/"),
                         " no retorno) ", sep = "")
      } else {
        in_list <- map(fields, ~ df_day[[.x]] %in% airports)
        keep <- if (spec$keep_mode == "all") reduce(in_list, `&`)
                else                          reduce(in_list, `|`)
        df_day <- df_day[keep, , drop = FALSE]
      }
    }

    if (verbose) cat(nrow(df_day), "records\n")
    df_day
  }

  df <- dates |> map(fetch_day) |> compact() |> bind_rows()
  if (verbose) cat("Total:", nrow(df), "records em", format(start_date, "%B/%Y"), "\n\n")
  df
}
