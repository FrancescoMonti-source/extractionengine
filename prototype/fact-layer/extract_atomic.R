# PROTOTYPE -- throwaway. Asks the local model served by llama-server for
# atomic aggression facts on the 64 test stays, one stay at a time, and writes
# a checkpoint after each, so an interrupted run resumes where it stopped.
# Prints counts and timings only: no identifier, no text.
#
#   Rscript extract_atomic.R smoke   # stays #47 and #2 first
#   Rscript extract_atomic.R all
#
# Sampling and thinking are the bonsai runs' own (seed 1, temperature 1,
# top_p 0.95, top_k 20, min_p 0.05, 2048 thinking tokens), so the one thing
# that differs from them is the question: list facts, instead of judge.

loc <- Sys.setlocale("LC_ALL", "English_United States.utf8")
options(warn = 1, ellmer_timeout_s = 1200)
mode <- commandArgs(trailingOnly = TRUE)[1]
stopifnot(mode %in% c("smoke", "all"))
here <- dirname(normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))))
src <- Sys.getenv("REDSANCODING_SRC")
od <- "C:/Users/franc/AppData/Roaming/R/data/R/redsancoding/denut"
out_dir <- file.path(tools::R_user_dir("extractionengine", "data"), "fact-layer-prototype")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

assignInNamespace("doceds_onnx_spec", function(model_dir = NULL) list(package = "redsan", digest = NA_character_), ns = "redsan")
pkgload::load_all(src, export_all = TRUE, helpers = FALSE, quiet = TRUE)
for (f in c("facts.R", "atomic.R")) source(file.path(here, f))
source(file.path(od, "aggression-b1-batch-ids-20261001.R"))
corpus <- readRDS("C:/Users/franc/Documents/Datasets/denut/denut_trimmed_v1.2.0_fiche_cora_2026-09-23.rds")
bundles <- corpus[batch_ids]
rm(corpus)
invisible(gc())

props <- httr2::resp_body_json(httr2::req_perform(httr2::request("http://localhost:8080/props")))
model <- sub("[.]gguf$", "", basename(gsub("\\\\", "/", props$model_path)))
stopifnot(props$default_generation_settings$n_ctx >= 65536)
chat <- ellmer::chat_openai_compatible(
  base_url = "http://localhost:8080/v1", model = model,
  params = ellmer::params(temperature = 1, top_p = 0.95, top_k = 20L, seed = 1L,
    presence_penalty = 0, reasoning_effort = "budget2048"),
  api_args = list(reasoning_effort = "medium", thinking_budget_tokens = 2048L, min_p = 0.05,
    max_tokens = 16384L),
  echo = "none"
)
identity <- list(
  model = model, build = props$build_info,
  chat_digest = suppressWarnings(.chat_identity(chat)$digest),
  question_digest = .json_digest(list(ATOMIC_SYSTEM_PROMPT, ATOMIC_CONCEPTS,
    deparse(atomic_type), deparse(atomic_request)))
)
path <- file.path(out_dir, "atomic-bonsai-64.rds")
state <- if (file.exists(path)) readRDS(path) else list(identity = identity, stays = list())
# One file, one question asked of one model: a checkpoint written under another
# identity is refused rather than continued.
stopifnot(identical(state$identity[c("model", "chat_digest", "question_digest")],
  identity[c("model", "chat_digest", "question_digest")]))
cat("server", model, props$build_info, "| chat", substr(identity$chat_digest, 1, 8),
  "| question", substr(identity$question_digest, 1, 8), "| done before", length(state$stays), "\n")

ids <- if (mode == "smoke") batch_ids[c(47L, 2L)] else batch_ids
for (id in ids) {
  if (!is.null(state$stays[[id]]$response)) next
  stay <- stay_of(bundles[[id]])
  req <- atomic_request(bundles[[id]], stay)
  t0 <- Sys.time()
  iso <- chat$clone(deep = TRUE)
  iso$set_turns(list())
  iso$set_system_prompt(ATOMIC_SYSTEM_PROMPT)
  res <- tryCatch(
    withCallingHandlers(
      iso$chat_structured(req$prompt, type = req$type, convert = FALSE),
      warning = function(w) if (grepl("Ignoring unsupported parameters", conditionMessage(w))) invokeRestart("muffleWarning")
    ),
    error = function(e) e
  )
  ok <- !inherits(res, "error")
  tokens <- tryCatch(iso$get_tokens(), error = function(e) NULL)
  state$stays[[id]] <- list(
    response = if (ok) res else NULL, error = if (ok) NA_character_ else class(res)[[1L]],
    message = if (ok) NA_character_ else conditionMessage(res),
    seconds = as.numeric(difftime(Sys.time(), t0, units = "secs")), tokens = tokens,
    n_fragments = nrow(req$index), prompt_chars = nchar(req$prompt), at = Sys.time()
  )
  tmp <- paste0(path, ".tmp")
  saveRDS(state, tmp)
  stopifnot(file.rename(tmp, path))
  concepts <- if (ok) vapply(res$facts, `[[`, "", "concept") else character()
  cat(sprintf("#%d %s %.0fs fragments=%d facts=%s | %s\n", match(id, batch_ids),
    if (ok) "ok" else class(res)[[1L]], state$stays[[id]]$seconds, nrow(req$index),
    if (ok) length(concepts) else "-", paste(names(table(concepts)), table(concepts), sep = ":", collapse = " ")))
}
done <- vapply(state$stays, function(s) !is.null(s$response), NA)
cat("DONE", mode, "| answered", sum(done), "of", length(batch_ids), "| failed", sum(!done), "\n")
