# =============================================================================
# 00_load.R: carrega pacotes e todas as funcoes da engine de uma vez
#
# Uso:  source("R/00_load.R")
# =============================================================================

# Pacotes necessarios (instale uma vez, se preciso):
#   install.packages(c("httr2", "jsonlite", "purrr", "dplyr",
#                      "arrow", "readr", "fs"))

.this_dir <- if (requireNamespace("here", quietly = TRUE)) here::here("R") else "R"

source(file.path(.this_dir, "kpi_specs.R"))
source(file.path(.this_dir, "fetch_kpi.R"))
source(file.path(.this_dir, "save_kpi.R"))
source(file.path(.this_dir, "download_kpi.R"))
source(file.path(.this_dir, "read_kpi.R"))

message("Engine de extracao carregada. KPIs disponiveis: ",
        paste(names(kpi_specs), collapse = ", "))
