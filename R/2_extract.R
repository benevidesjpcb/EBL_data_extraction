# =============================================================================
# 2_extract.R  --  DOWNLOAD do ano (idempotente) + salvamento
#
# Funcao principal:  extract(year, config)
#   - percorre os meses do ano pedido
#   - para cada mes, SE o arquivo ja existe na pasta -> pula (nao vai na API)
#   - senao, baixa da API e salva um arquivo por mes (parquet + csv)
#
# O que ja foi baixado e "sabido" pela simples existencia do arquivo mensal
# na pasta -- nao precisa de registro/banco. Isso deixa a extracao resiliente
# a instabilidade da API do DECEA: rode o ano inteiro quantas vezes quiser,
# que so bate na API nos meses que faltam.
#
# Requer: httr2, jsonlite, purrr, dplyr, arrow, readr, fs
# =============================================================================

library(httr2)
library(jsonlite)
library(purrr)
library(dplyr)
library(arrow)
library(readr)
library(fs)

# -----------------------------------------------------------------------------
# extract(year, config, kpis, months, overwrite, refresh_current)
#   year            : ano a baixar (ex.: 2026)
#   kpis            : quais KPIs (default: todos do config)
#   months          : quais meses (default: 1:12)
#   overwrite       : TRUE re-baixa tudo, mesmo o que ja existe (default FALSE)
#   refresh_current : TRUE re-baixa sempre o mes CORRENTE (ainda incompleto),
#                     mesmo que o arquivo ja exista (default TRUE)
# -----------------------------------------------------------------------------
extract <- function(year, config,
                    kpis            = names(config$kpis),
                    months          = 1:12,
                    overwrite       = FALSE,
                    refresh_current = TRUE) {

  this_year  <- as.integer(format(Sys.Date(), "%Y"))
  this_month <- as.integer(format(Sys.Date(), "%m"))

  for (kpi in kpis) {
    spec   <- config$kpis[[kpi]]
    if (is.null(spec)) { warning(sprintf("KPI '%s' nao existe no config.", kpi)); next }

    folder <- fs::path(config$out_dir, spec$out_name)
    cat(sprintf("\n==== %s (%s) - %d ====\n", kpi, spec$out_name, year))

    for (m in months) {
      stamp      <- sprintf("%04d-%02d", year, m)
      pq_path    <- fs::path(folder, paste0(stamp, ".parquet"))
      is_current <- (year == this_year && m == this_month)

      # decide se pula
      if (fs::file_exists(pq_path) && !overwrite &&
          !(refresh_current && is_current)) {
        cat(sprintf("  %s: ja existe, pulando\n", stamp))
        next
      }

      cat(sprintf("  %s: baixando ... ", stamp))
      df <- .fetch_month(kpi, year, m, config)

      # mes vazio (API fora do ar ou sem dado) -> NAO grava, tenta de novo depois
      if (nrow(df) == 0) {
        cat("0 linhas (nada gravado)\n")
        next
      }

      .write_files(df, folder, stamp, config$formats)
      cat(sprintf("%d linhas salvas\n", nrow(df)))
    }
  }
  invisible(NULL)
}

# =============================================================================
# HELPERS INTERNOS (voce nao precisa chamar diretamente)
# =============================================================================

# --- baixa UM mes da API (loop de dias + retry + parse) ----------------------
.fetch_month <- function(kpi, year, month, config, timeout = 120) {

  spec <- config$kpis[[kpi]]

  start_date <- as.Date(sprintf("%04d-%02d-01", year, month))
  end_date   <- as.Date(format(start_date + 32, "%Y-%m-01")) - 1
  dates      <- seq(start_date, end_date, by = "day")

  gsize  <- if (is.null(spec$group_size)) Inf else spec$group_size
  groups <- if (is.infinite(gsize)) list(config$airports)
            else split(config$airports,
                       ceiling(seq_along(config$airports) / gsize))

  # uma requisicao, com retry (503 PGRST002 e timeout) e parse
  fetch_one <- function(url) {
    tryCatch({
      resp <- request(url) |>
        req_timeout(timeout) |>
        req_retry(
          max_tries        = 6,
          retry_on_failure = TRUE,
          is_transient     = ~ resp_status(.x) %in% c(429, 500, 502, 503),
          backoff          = ~ min(2 ^ .x, 60)
        ) |>
        req_perform()

      body <- resp_body_string(resp)
      if (is.na(body) || nchar(body) < 3) return(NULL)

      df <- fromJSON(body, flatten = TRUE)
      if (!is.data.frame(df) || nrow(df) == 0) return(NULL)

      df |> mutate(across(everything(), as.character))
    }, error = function(e) NULL)
  }

  # um dia: monta as URLs (por grupo de aeroportos x campo de filtro)
  fetch_day <- function(date) {
    d0 <- format(date, "%Y-%m-%d")
    d1 <- format(date + 1, "%Y-%m-%d")

    urls <- groups |>
      map(function(grp) {
        filt <- paste0("in.(", paste(grp, collapse = ","), ")")
        map_chr(spec$query_fields, function(field) {
          u <- paste0(config$base_url, "/", spec$endpoint, "?",
                      spec$time_field, "=gte.", d0, "&",
                      spec$time_field, "=lt.",  d1, "&",
                      field, "=", filt)
          if (!is.null(spec$limit)) u <- paste0(u, "&limit=", spec$limit)
          u
        })
      }) |>
      unlist()

    urls |> map(fetch_one) |> compact() |> bind_rows()
  }

  df <- dates |> map(fetch_day) |> compact() |> bind_rows()

  # dedup opcional
  if (!is.null(spec$dedup_key) && nrow(df) > 0 &&
      spec$dedup_key %in% colnames(df)) {
    df <- df |> distinct(.data[[spec$dedup_key]], .keep_all = TRUE)
  }

  # keep: voos "entre" os aeroportos
  if (nrow(df) > 0 && spec$keep_mode != "none") {
    fields <- intersect(spec$query_fields, colnames(df))
    if (length(fields) > 0) {
      in_list <- map(fields, ~ df[[.x]] %in% config$airports)
      keep <- if (spec$keep_mode == "all") reduce(in_list, `&`)
              else                          reduce(in_list, `|`)
      df <- df[keep, , drop = FALSE]
    }
  }

  df
}

# --- grava um data frame em parquet/csv --------------------------------------
.write_files <- function(df, dir, stamp, formats) {
  fs::dir_create(dir)
  if ("parquet" %in% formats)
    arrow::write_parquet(df, fs::path(dir, paste0(stamp, ".parquet")))
  if ("csv" %in% formats)
    readr::write_csv(df, fs::path(dir, paste0(stamp, ".csv")))
  invisible(NULL)
}
