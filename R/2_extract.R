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
                    refresh_current = TRUE,
                    verbose         = TRUE,
                    check_api       = TRUE) {

  # --- pre-check: a API esta no ar? -----------------------------------------
  # Evita varrer o mes inteiro (dezenas de requisicoes) quando a API do DECEA
  # esta fora (HTTP 503 PGRST002). Uma unica requisicao leve resolve.
  if (check_api) {
    h <- .api_up(config, kpi = kpis[1])
    if (!isTRUE(h$up)) {
      cat(sprintf("\n*** API indisponivel (status: %s). %s ***\n",
                  as.character(h$status), if (!is.null(h$msg)) h$msg else ""))
      cat("Nada foi baixado. Tente novamente mais tarde.\n")
      return(invisible(FALSE))
    }
    if (verbose) cat("API OK - iniciando extracao.\n")
  }

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

      cat(sprintf("  %s: baixando (dia: registros)...\n", stamp))
      t0 <- Sys.time()
      df <- .fetch_month(kpi, year, m, config, verbose = verbose)
      secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")))

      # mes vazio (API fora do ar ou sem dado) -> NAO grava, tenta de novo depois
      if (nrow(df) == 0) {
        cat(sprintf("  %s: 0 linhas (nada gravado, %ds)\n", stamp, secs))
        next
      }

      .write_files(df, folder, stamp, config$formats)
      cat(sprintf("  %s: %d linhas salvas (%ds)\n", stamp, nrow(df), secs))
    }
  }
  invisible(NULL)
}

# =============================================================================
# HELPERS INTERNOS (voce nao precisa chamar diretamente)
# =============================================================================

# --- pre-check: a API responde? ----------------------------------------------
# Faz UMA requisicao leve (limit=1). Retorna lista com $up (TRUE/FALSE),
# $status (codigo HTTP) e $msg (corpo/erro). Status >= 500 ou falha de
# conexao = fora do ar.
.api_up <- function(config, kpi = names(config$kpis)[1], timeout = 30) {
  spec <- config$kpis[[kpi]]
  url  <- paste0(config$base_url, "/", spec$endpoint, "?limit=1")
  tryCatch({
    resp   <- request(url) |>
      req_timeout(timeout) |>
      req_error(is_error = ~ FALSE) |>   # nao lanca erro em HTTP >= 400
      req_perform()
    status <- resp_status(resp)
    if (status >= 500) {
      list(up = FALSE, status = status,
           msg = substr(resp_body_string(resp), 1, 200))
    } else {
      list(up = TRUE, status = status, msg = NULL)
    }
  }, error = function(e) {
    list(up = FALSE, status = NA, msg = conditionMessage(e))
  })
}

# --- baixa UM mes da API (loop de dias + retry + parse) ----------------------
#   timeout   : timeout por requisicao, em segundos (default 60)
#   max_tries : tentativas por requisicao (default 4)
#   verbose   : imprime progresso por dia (default TRUE)
.fetch_month <- function(kpi, year, month, config,
                         timeout = 60, max_tries = 4, verbose = TRUE) {

  spec <- config$kpis[[kpi]]

  start_date <- as.Date(sprintf("%04d-%02d-01", year, month))
  end_date   <- as.Date(format(start_date + 32, "%Y-%m-01")) - 1
  dates      <- seq(start_date, end_date, by = "day")

  gsize  <- if (is.null(spec$group_size)) Inf else spec$group_size
  groups <- if (is.infinite(gsize)) list(config$airports)
            else split(config$airports,
                       ceiling(seq_along(config$airports) / gsize))

  # uma requisicao, com retry (503 PGRST002 e timeout) e parse.
  # backoff limitado a ~8s por tentativa para nao emperrar o mes inteiro
  # quando a API esta instavel (falha rapido e segue).
  fetch_one <- function(url) {
    tryCatch({
      resp <- request(url) |>
        req_timeout(timeout) |>
        req_retry(
          max_tries        = max_tries,
          retry_on_failure = TRUE,
          is_transient     = ~ resp_status(.x) %in% c(429, 500, 502, 503),
          backoff          = ~ min(2 ^ .x, 8)
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

    df_d <- urls |> map(fetch_one) |> compact() |> bind_rows()
    if (verbose) cat(sprintf("      %s: %d\n", d0, nrow(df_d)))
    df_d
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
