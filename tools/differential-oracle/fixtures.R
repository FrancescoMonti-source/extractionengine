DifferentialFakeChat <- R6::R6Class(
    "DifferentialFakeChat",
    inherit = getFromNamespace("Chat", "ellmer"),
    public = list(
        initialize = function(responder, model = "synthetic-model") {
            if (!is.function(responder)) {
                stop("responder must be a function", call. = FALSE)
            }
            private$responder <- responder
            provider <- getFromNamespace("test_provider", "ellmer")(
                name = "test",
                model = model,
                base_url = "mock://",
                params = list(
                    temperature = 0,
                    seed = 123L,
                    max_tokens = 128L))
            super$initialize(
                provider = provider,
                system_prompt = "Synthetic differential-oracle prompt",
                echo = "none")
        },
        chat_structured = function(..., type, echo = "none", convert = TRUE) {
            inputs <- list(...)
            prompt <- paste(vapply(
                inputs,
                function(x) paste(as.character(x), collapse = ""),
                character(1)), collapse = "\n")
            private$responder(prompt, type, self$get_system_prompt())
        }),
    private = list(responder = NULL))

.differential_fake_chat <- function(responder, ...) {
    DifferentialFakeChat$new(responder = responder, ...)
}

.structured_lab_empty_task <- function() {
    biology <- tibble::tibble(
        PATID = c("P1", "P1", "P2"),
        EVTID = c("E1", "E1", "E2"),
        ELTID = c("BIO-1", "BIO-1", "BIO-2"),
        DATEXAM = as.Date(c("2026-01-01", "2026-01-01", "2026-01-02")),
        TYPEANA = c("K.K", "K.K", "OTHER"),
        NUMRES = c(4.2, 5.1, 99),
        STRRES = NA_character_)
    minimum_value <- 4
    potassium <- concept_spec(
        "synthetic potassium",
        channels = list(result = lab_channel(selector = analyte("K.K"))))
    variable <- variable_spec(
        name = "synthetic_mean_potassium",
        channels = list(result = use_channel(
            "result",
            concept = potassium,
            filter_rows = NUMRES >= .env$minimum_value)),
        output = from_channel(
            "result",
            group_by = "PATID",
            value = mean(NUMRES, na.rm = TRUE)))
    run <- run_variable(
        variable,
        cohort = tibble::tibble(PATID = c("P1", "P2")),
        sources = list(biology = biology))

    list(
        run = run,
        value_columns = "value",
        evidence_columns = c("source_EVTID", "ELTID"))
}

.same_element_combine <- function() {
    biology <- tibble::tibble(
        PATID = c("P1", "P1", "P1", "P2", "P2"),
        EVTID = c("E1", "E1", "E2", "E3", "E3"),
        ELTID = c("BIO-10", "BIO-10", "BIO-11", "BIO-20", "BIO-21"),
        DATEXAM = as.Date(c(
            "2026-02-01", "2026-02-01", "2026-02-02",
            "2026-02-03", "2026-02-03")),
        TYPEANA = c("K.K", "NA.NA", "K.K", "K.K", "NA.NA"),
        NUMRES = c(4.1, 140, 4.4, 4.3, 139),
        STRRES = NA_character_)
    electrolytes <- concept_spec(
        "synthetic electrolytes",
        channels = list(
            potassium = lab_channel(selector = analyte("K.K")),
            sodium = lab_channel(selector = analyte("NA.NA"))))
    variable <- variable_spec(
        name = "synthetic_same_sample_electrolytes",
        channels = list(
            potassium = use_channel("potassium", concept = electrolytes),
            sodium = use_channel("sodium", concept = electrolytes)),
        combine = combine_channels("potassium & sodium", by = "ELTID"),
        output = bin_output(group_by = "PATID"))
    run <- run_variable(
        variable,
        cohort = tibble::tibble(PATID = c("P1", "P2")),
        sources = list(biology = biology))

    list(
        run = run,
        value_columns = "value",
        evidence_columns = c("source_EVTID", "ELTID"))
}

.text_llm_case <- function() {
    response <- ellmer::type_object(
        "Synthetic structured extraction.",
        finding = ellmer::type_enum(
            c("present", "not_present"),
            "Whether the marker is explicitly documented."),
        temporal_context = ellmer::type_string(
            "The explicitly documented temporal context."))
    marker <- concept_spec(
        "synthetic marker",
        channels = list(text = text_channel(lucene_query("marker"))))
    variable <- variable_spec(
        name = "synthetic_text_extraction",
        channels = list(marker = use_channel(
            "text",
            concept = marker,
            search_within = "PATID",
            method = "lucene_llm",
            model = "synthetic-model",
            model_params = list(temperature = 0, seed = 123L),
            response = response)),
        output = from_channel("marker", group_by = "EVTID"))
    cohort <- tibble::tibble(
        PATID = c("P1", "P2"),
        EVTID = c("TARGET-1", "TARGET-2"))
    documents <- list(
        coverage = tibble::tibble(
            task_id = c("P1::TARGET-1", "P2::TARGET-2"),
            PATID = c("P1", "P2"),
            EVTID = c("TARGET-1", "TARGET-2"),
            coverage_state = c("candidate", "no_candidate")),
        candidates = tibble::tibble(
            task_id = "P1::TARGET-1",
            snippet_id = "S001",
            hit_ref = "H001",
            PATID = "P1",
            EVTID = "SOURCE-1",
            ELTID = "DOC-1",
            snippet_text = "Synthetic marker explicitly documented.",
            hit_text = "Synthetic marker",
            RECDATE = as.Date("2026-03-01"),
            RECTYPE = "SYNTHETIC"))
    responder <- function(prompt, type, system_prompt) {
        list(
            finding = "present",
            temporal_context = "current",
            rationale = "The supplied synthetic snippet states the marker.",
            snippet_ids = "S001")
    }
    run <- run_variable(
        variable,
        cohort = cohort,
        sources = list(documents = documents),
        chat = .differential_fake_chat(responder))

    list(
        run = run,
        value_columns = c(
            "finding", "temporal_context", "rationale", "needs_review",
            "citation_warning", "review_reason"),
        evidence_columns = c("source_EVTID", "ELTID", "snippet_id"))
}

.document_date_case <- function() {
    documents <- tibble::tibble(
        PATID = c("P1", "P1", "P1", "P2"),
        EVTID = c("E1", "E2", "E3", "E4"),
        ELTID = c("DOC-10", "DOC-11", "DOC-12", "DOC-20"),
        RECDATE = as.Date(c(
            "2026-04-01", "2026-04-20", "2026-04-05", "2026-03-15")),
        RECTYPE = c("CR-ANES", "CR-ANES", "OTHER", "CR-ANES"))
    preoperative <- concept_spec(
        "synthetic preoperative document",
        channels = list(document = doc_channel(
            source = "documents",
            selector = doc_meta(RECTYPE = "CR-ANES"))))
    variable <- variable_spec(
        name = "synthetic_last_preoperative_document",
        anchor = "anchor_date",
        channels = list(document = use_channel(
            "document",
            concept = preoperative,
            window = c(-30, 0))),
        output = from_channel(
            "document",
            group_by = "PATID",
            value = max(RECDATE)))
    run <- run_variable(
        variable,
        cohort = tibble::tibble(
            PATID = c("P1", "P2", "P3"),
            anchor_date = as.Date("2026-04-10")),
        sources = list(documents = documents))

    list(
        run = run,
        value_columns = "value",
        evidence_columns = c("source_EVTID", "ELTID"))
}

differential_cases <- function() {
    list(
        structured_lab_empty_task = .structured_lab_empty_task(),
        same_element_combine = .same_element_combine(),
        text_llm = .text_llm_case(),
        document_date = .document_date_case())
}
