lab_fixture <- function() {
    tibble::tibble(
        PATID = "P1",
        EVTID = c("E1", "E1", "E2", "E2", "E3"),
        ELTID = paste0("L", 1:5),
        DATEXAM = as.Date("2026-01-01") + 0:4,
        TYPEANA = c("K.K", "K.K", "K.K", "ONE", "EMPTY"),
        NUMRES = c(4.2, NA, 5.1, 2, NA),
        STRRES = c(NA, "negatif", "legacy-code", NA, NA),
        LOWER = c(3.5, 3.5, 3.5, 1, NA),
        UPPER = c(5, 5, 5, 3, NA),
        WEIGHT = c(1, 2, 3, 1, 1))
}

lab_variable <- function(code, value, ptype) {
    value <- rlang::enquo(value)
    concept <- concept_spec(
        paste("lab", code),
        channels = list(result = lab_channel(selector = analyte(code))))
    variable_spec(
        name = paste0(code, "_value"),
        channels = list(result = use_channel(
            channel = "result", concept = concept,
            search_within = "PATID")),
        output = from_channel(
            "result", group_by = "PATID", value = !!value, ptype = ptype))
}

test_that("data-masked values preserve aligned source rows and one-cell output", {
    biology <- lab_fixture()
    cohort <- tibble::tibble(PATID = "P1")

    numeric_variable <- lab_variable(
        "K.K", max(NUMRES, na.rm = TRUE), double())
    numeric_run <- run_variable(
        numeric_variable, cohort,
        sources = list(biology = biology))
    character_run <- run_variable(
        lab_variable(
            "K.K", paste(STRRES[!is.na(STRRES)], collapse = "|"),
            character()), cohort,
        sources = list(biology = biology))
    date_run <- run_variable(
        lab_variable(
            "K.K", max(DATEXAM),
            as.POSIXct(character(), tz = "Europe/Paris")), cohort,
        sources = list(biology = biology))
    empty_run <- run_variable(
        lab_variable("ABSENT", mean(NUMRES, na.rm = TRUE), double()), cohort,
        sources = list(biology = biology))
    weight_options <- list(remove_missing = TRUE)
    weighted_run <- run_variable(
        lab_variable(
            "K.K", stats::weighted.mean(
                NUMRES, WEIGHT, na.rm = .env$weight_options$remove_missing),
            double()),
        cohort, sources = list(biology = biology))
    latest_class_run <- run_variable(
        lab_variable("K.K", {
            if (all(is.na(NUMRES))) {
                result <- NA_character_
            } else {
                i <- which.max(DATEXAM)
                result <- dplyr::case_when(
                    NUMRES[[i]] < LOWER[[i]] ~ "low",
                    NUMRES[[i]] > UPPER[[i]] ~ "high",
                    .default = "normal")
            }
            result
        }, character()),
        cohort, sources = list(biology = biology))

    # Engine invariant: one data-masked expression sees complete, aligned source
    # columns. Missing values are handled explicitly by the author.
    expect_identical(
        list(
            numeric = numeric_run$values$value,
            character = character_run$values$value,
            date = date_run$values$value,
            weighted = weighted_run$values$value,
            latest_class = latest_class_run$values$value),
        list(
            numeric = 5.1,
            character = "negatif|legacy-code",
            date = as.POSIXct("2026-01-03", tz = "Europe/Paris"),
            weighted = 4.875,
            latest_class = "high"))

    # With no candidate rows the expression is not evaluated and the task gets
    # one stable missing cell. Multiple returned cells remain a loud error.
    expect_identical(empty_run$values$value, NA_real_)
    expect_false("channel_coverage" %in% names(numeric_run$values))

    # Channel status keeps row selection separate from model processing. A
    # deterministic channel never needs model processing, whether or not its
    # selector matched a candidate row.
    expect_identical(
        c(
            matched_selection = numeric_run$channel_status$selection_status,
            matched_processing = numeric_run$channel_status$processing_status,
            empty_selection = empty_run$channel_status$selection_status,
            empty_processing = empty_run$channel_status$processing_status),
        c(
            matched_selection = "matched",
            matched_processing = "not_required",
            empty_selection = "no_match",
            empty_processing = "not_required"))
    expect_length(
        intersect(
            c("status", "hit", "processing_state", "contribution", "error"),
            names(numeric_run$channel_status)),
        0L)
    expect_identical(
        intersect(
            c("call_status", "response_status", "transport_attempts",
              "attempt_status", "processing_status", "n_tries", "definition"),
            names(numeric_run$audit$llm_calls)),
        c("call_status", "response_status", "transport_attempts"))

    # Reading NUMRES does not erase sibling payload or rows with missing NUMRES.
    expect_identical(
        numeric_run$evidence |>
            dplyr::arrange(evidence_ref) |>
            dplyr::select(source_EVTID, NUMRES, STRRES),
        tibble::tibble(
            source_EVTID = c("E1", "E1", "E2"),
            NUMRES = c(4.2, NA, 5.1),
            STRRES = c(NA, "negatif", "legacy-code")))
    expect_identical(character_run$evidence$ELTID, paste0("L", 1:3))
    expect_identical(unique(numeric_run$evidence$evidence_kind), "source_row")
    expect_identical(
        intersect(c("evidence_ref", "source_row_id", "hit_ref"),
                  names(numeric_run$evidence)),
        "evidence_ref")

    # Phase 4 nucleus: structured eligibility, selection, and contribution use
    # one coordinate-only lineage relation. Non-matching rows stop at the
    # pre-selector boundary; source payload is not copied into audit.
    expect_identical(
        numeric_run$audit$lineage |>
            dplyr::select(
                furthest_stage, artifact_type, artifact_id,
                source_row_ref, source_ELTID),
        tibble::tibble(
            furthest_stage = c(rep("used", 3), rep("pre_selector", 2)),
            artifact_type = "source_row",
            artifact_id = sprintf("biology:%08d", 1:5),
            source_row_ref = sprintf("biology:%08d", 1:5),
            source_ELTID = paste0("L", 1:5)))
    expect_false("internal" %in% names(numeric_run$audit))

    # A structured activation has no coverage frame at all: its total task
    # relation is the lineage, so a result that lost it must fail loudly instead
    # of reporting every task as unavailable.
    expect_error(
        getFromNamespace(".channel_status_rows", "extractionengine")(
            resolve_variable_spec(numeric_variable), "result",
            list(candidates = tibble::tibble(), executed_tasks = "P1"), "P1"),
        "missing its activation lineage")


    expect_error(
        run_variable(
            lab_variable("K.K", NUMRES, double()), cohort,
            sources = list(biology = biology)),
        "must return exactly one scalar or one list cell")

    # Data masks expose prepared-source columns only, and invalid references are
    # rejected even when the selector happens to produce no target row.
    absent_concept <- concept_spec(
        "absent lab",
        channels = list(result = lab_channel(selector = analyte("ABSENT"))))
    invalid_filter <- variable_spec(
        name = "invalid_filter",
        channels = list(result = use_channel(
            channel = "result",
            concept = absent_concept,
            search_within = "PATID",
            filter_rows = {
                if (FALSE) conditional_name <- 1
                NUMREZ <- replace(NUMREZ, 1L, 0)
                task_id == "internal-task" | conditional_name > 0
            })),
        output = bin_output(group_by = "PATID"))
    expect_error(
        run_variable(
            invalid_filter, cohort,
            sources = list(biology = biology)),
        "missing prepared-source column.*NUMREZ, task_id, conditional_name")
    expect_error(
        run_variable(
            lab_variable("K.K", task_id[[1L]], character()), cohort,
            sources = list(biology = biology)),
        "missing prepared-source column.*task_id")

    # A bare name is a prepared-source column even when the calling session
    # happens to bind that name. A typo for NUMRES used to publish the session
    # object as the variable's value, with genuine laboratory rows attached to
    # it as its evidence.
    NUMRE5 <- -1
    expect_error(
        run_variable(
            lab_variable("K.K", mean(NUMRE5), double()), cohort,
            sources = list(biology = biology)),
        "missing prepared-source column.*NUMRE5")

    # Functions are the single exception, so an authored helper passed by value
    # stays author code and the mean-of-per-stay-means idiom still compiles.
    stay_mean <- function(x) base::mean(x, na.rm = TRUE)
    stay_means_run <- run_variable(
        lab_variable(
            "K.K",
            mean(vapply(split(NUMRES, EVTID), stay_mean, numeric(1))),
            double()),
        cohort, sources = list(biology = biology))
    expect_identical(stay_means_run$values$value, base::mean(c(4.2, 5.1)))

    # Function lookup must respect the nearest binding. `exists(...,
    # mode = "function")` incorrectly skips this scalar and finds base::mean.
    mean <- -1
    expect_error(
        run_variable(
            lab_variable("K.K", mean, double()), cohort,
            sources = list(biology = biology)),
        "missing prepared-source column.*mean")

    expect_error(
        variable_spec(
            name = "missing_scope",
            channels = list(result = use_channel(
                "result", concept = absent_concept)),
            output = bin_output(group_by = "PATID")),
        "requires search_within = 'PATID' or 'EVTID'")
    expect_error(
        variable_spec(
            name = "missing_ptype",
            channels = list(result = use_channel(
                "result", concept = absent_concept,
                search_within = "PATID")),
            output = from_channel(
                "result", group_by = "PATID", value = mean(NUMRES))),
        "must declare ptype")
})

test_that("data-mask validation does not execute active bindings", {
    reads <- 0L
    env <- rlang::env(parent = baseenv())
    rlang::env_bind_active(
        env,
        active_helper = function(value) {
            reads <<- reads + 1L
            base::mean
        })
    expression <- rlang::new_quosure(
        quote(vapply(NUMRES, active_helper, numeric(1))), env)
    references <- getFromNamespace(
        ".data_mask_references", "extractionengine")(expression)

    expect_identical(
        list(
            columns = references$columns,
            external = references$external,
            active_binding_reads = reads),
        list(
            columns = c("NUMRES", "active_helper"),
            external = character(),
            active_binding_reads = 0L))
})

test_that("relational keys control qualification, evidence, and broadcast", {
    biology <- tibble::tibble(
        PATID = "P1",
        EVTID = c("E1", "E1", "E1", "E2", "E2", "E2"),
        ELTID = paste0("L", 1:6),
        DATEXAM = as.Date("2026-02-01") + c(0, 1, 1, 2, 3, 5),
        TYPEANA = c("HB.HB", "HB.HB", "OTHER", "HB.HB", "HB.HB", "HB.HB"),
        NUMRES = c(9, 10, 99, 14, 16, 7),
        STRRES = NA_character_)
    hemoglobin <- concept_spec(
        "hemoglobin",
        channels = list(hb = lab_channel(selector = analyte("HB.HB"))))

    make_variable <- function(filter_by) {
        low_threshold <- 12
        variable_spec(
            name = paste0("mean_hb_filtered_by_", filter_by),
            anchor = "anchor_date",
            channels = list(
                hb_low = use_channel(
                    channel = "hb",
                    concept = hemoglobin,
                    search_within = "PATID",
                    filter_rows = .data$NUMRES < .env$low_threshold,
                    window = c(-Inf, 0)),
                hb_group = use_channel(
                    channel = "hb",
                    concept = hemoglobin,
                    search_within = "PATID",
                    group_by = "EVTID",
                    filter_groups = mean(NUMRES, na.rm = TRUE) < 12,
                    window = c(-Inf, 0)),
                hb_payload = use_channel(
                    channel = "hb",
                    concept = hemoglobin,
                    search_within = "PATID",
                    window = c(-Inf, 0))),
            combine = combine_channels("hb_low & hb_group", by = "EVTID"),
            output = from_channel(
                "hb_payload", group_by = "PATID",
                value = mean(NUMRES, na.rm = TRUE),
                ptype = double(),
                filter_by_qualified = filter_by))
    }

    patient_cohort <- tibble::tibble(
        PATID = c("P1", "P1"),
        EVTID = c("E1", "E2"),
        task_id = c("caller-E1", "caller-E2"),
        anchor_date = as.Date("2026-02-05"))

    protocol_specs <- list(make_variable("EVTID"), make_variable("PATID"))
    protocol_run <- run_protocol(
        protocol_specs,
        cohort = patient_cohort,
        sources = list(biology = biology))
    event_restricted <- protocol_run$mean_hb_filtered_by_EVTID
    patient_restricted <- protocol_run$mean_hb_filtered_by_PATID

    # Engine invariant: the qualified-row key, not an implicit aggregation,
    # determines which raw rows reach the terminal patient reducer.
    expect_identical(
        c(
            filter_by_EVTID = event_restricted$values$value,
            filter_by_PATID = patient_restricted$values$value),
        c(filter_by_EVTID = 9.5, filter_by_PATID = 12.25))
    expect_identical(
        event_restricted$audit$combine_keys$EVTID[
            event_restricted$audit$combine_keys$qualifies],
        "E1")
    expect_false("channel_coverage" %in% names(event_restricted$values))
    expect_false("channel_coverage" %in% names(event_restricted$audit$overlap))
    # Audit stages describe one relational funnel instead of exposing helper
    # names. The window remains a separate stage between the pre-selector rows
    # and the selector itself.
    hb_low_counts <- event_restricted$audit$counts |>
        dplyr::filter(channel == "hb_low")
    expected_counts <- c(
        pre_selector = 6L, window = 5L, selector = 4L,
        filtered_selector = 2L)
    expect_identical(
        hb_low_counts$n[match(names(expected_counts), hb_low_counts$stage)],
        unname(expected_counts))
    # Lineage buckets stay disjoint and now separate the two rows an activation
    # filter demoted, which stop at `selector`, from the row that never matched
    # the selector at all.
    expect_identical(
        event_restricted$audit$lineage |>
            dplyr::filter(channel == "hb_low") |>
            dplyr::count(furthest_stage, name = "n") |>
            dplyr::arrange(furthest_stage),
        tibble::tibble(
            furthest_stage = c("pre_selector", "selector", "used", "window"),
            n = c(1L, 2L, 2L, 1L)))
    expect_length(
        intersect(
            unique(event_restricted$audit$counts$stage),
            c("task_join", "filter_rows", "filter_groups")),
        0L)
    # Known regression: the payload evidence follows the qualifying rows while
    # gate evidence remains the complete observed signal.
    expect_identical(
        event_restricted$evidence |>
            dplyr::filter(channel == "hb_payload") |>
            dplyr::arrange(evidence_ref) |>
            dplyr::select(source_EVTID, NUMRES),
        tibble::tibble(
            source_EVTID = c("E1", "E1"),
            NUMRES = c(9, 10)))
    expect_identical(
        sort(event_restricted$evidence$source_EVTID[
            event_restricted$evidence$channel == "hb_group"]),
        c("E1", "E1"))

    broadcast <- variable_spec(
        name = "hb_patient_gate_broadcast_to_events",
        anchor = "anchor_date",
        channels = list(
            hb_gate = use_channel(
                channel = "hb",
                concept = hemoglobin,
                search_within = "PATID",
                window = c(-Inf, 0)),
            hb_low = use_channel(
                channel = "hb",
                concept = hemoglobin,
                search_within = "PATID",
                filter_rows = NUMRES < 12,
                window = c(-Inf, 0))),
        combine = combine_channels("hb_gate & hb_low", by = "PATID"),
        output = bin_output(group_by = "EVTID"))
    broadcast_run <- run_variable(
        broadcast,
        tibble::tibble(
            PATID = c("P1", "P1", "P2"),
            EVTID = c("E1", "E2", "E3"),
            anchor_date = as.Date("2026-02-05")),
        sources = list(biology = biology))

    # Coarse qualification broadcasts to declared descendant output units; the
    # public relation remains at the authored combine key.
    expect_identical(broadcast_run$values$value, c(1L, 1L, 0L))
    expect_identical(
        broadcast_run$audit$combine_keys |>
            dplyr::arrange(PATID),
        tibble::tibble(
            PATID = c("P1", "P2"),
            hb_gate = c(TRUE, FALSE),
            hb_low = c(TRUE, FALSE),
            qualifies = c(TRUE, FALSE)))
    expect_identical(
        broadcast_run$audit$counts$n[
            broadcast_run$audit$counts$PATID == "P2" &
            broadcast_run$audit$counts$channel == "hb_gate" &
            broadcast_run$audit$counts$stage == "pre_selector"],
        0L)

    # Identical text in two source documents is not duplicate relational
    # evidence: both native stay/document keys must survive real retrieval.
    documents <- data.frame(
        ELTID = c("D1", "D2"),
        RECTXT = c("Alpha marker.", "Alpha marker. Beta marker."),
        PATID = c("P1", "P1"),
        EVTID = c("E1", "E2"),
        RECDATE = as.Date(c("2026-01-01", "2026-01-02")),
        RECTYPE = c("CR", "CR"))
    corpus <- corpustools::create_tcorpus(
        documents,
        text_columns = "RECTXT", doc_column = "ELTID",
        split_sentences = TRUE, remember_spaces = FALSE, verbose = FALSE)
    alpha_signal <- concept_spec(
        "alpha_signal",
        channels = list(text = text_channel(lucene_query("alpha"))))
    beta_signal <- concept_spec(
        "beta_signal",
        channels = list(text = text_channel(lucene_query("beta"))))
    text_variable <- function(by) variable_spec(
        name = paste0("same_unit_text_intersection_", by),
        channels = list(
            alpha = use_channel(
                "text", concept = alpha_signal,
                search_within = "PATID", method = "lucene",
                filter_rows = !is.na(RECDATE)),
            beta = use_channel(
                "text", concept = beta_signal,
                search_within = "PATID", method = "lucene")),
        combine = combine_channels("alpha & beta", by = by),
        output = bin_output(group_by = "PATID"))

    text_runs <- run_protocol(
        list(text_variable("EVTID"), text_variable("ELTID")),
        cohort = tibble::tibble(PATID = "P1"),
        sources = list(documents = corpus))
    expect_identical(
        vapply(text_runs, function(run) run$values$value, integer(1)),
        c(same_unit_text_intersection_EVTID = 1L,
          same_unit_text_intersection_ELTID = 1L))
    event_text_run <- text_runs$same_unit_text_intersection_EVTID
    document_text_run <- text_runs$same_unit_text_intersection_ELTID
    expect_identical(
        c(
            EVTID = event_text_run$audit$combine_keys$EVTID[
                event_text_run$audit$combine_keys$qualifies],
            ELTID = document_text_run$audit$combine_keys$ELTID[
                document_text_run$audit$combine_keys$qualifies]),
        c(EVTID = "E2", ELTID = "D2"))
    expect_identical(
        event_text_run$audit$lineage |>
            dplyr::filter(channel == "alpha") |>
            dplyr::count(artifact_type, furthest_stage, name = "n") |>
            dplyr::arrange(artifact_type, furthest_stage),
        tibble::tibble(
            artifact_type = c("document", "snippet"),
            furthest_stage = c("pre_selector", "used"),
            n = c(2L, 2L)))
    expect_identical(
        sort(event_text_run$evidence$source_EVTID[
            event_text_run$evidence$channel == "alpha"]),
        c("E1", "E2"))
    expect_identical(
        unique(event_text_run$evidence$evidence_kind),
        "lucene_hit")
    # Each activation carries its own catalog origin. Different concepts may
    # reuse the same origin-channel name without creating a composite concept.
    expect_identical(
        lapply(
            event_text_run$audit$execution_manifest$spec$channels,
            \(channel) channel[c("origin_concept", "origin_channel")]),
        list(
            alpha = list(
                origin_concept = "alpha_signal", origin_channel = "text"),
            beta = list(
                origin_concept = "beta_signal", origin_channel = "text")))

    # ELTID is one predicate domain only within a source. Distinct selectors
    # from that source may combine at element level; cross-source relations must
    # first project to the shared EVTID or PATID domain.
    cross_source_variable <- variable_spec(
        name = "cross_source_ELTID_is_invalid",
        channels = list(
            alpha = use_channel(
                "text", concept = alpha_signal,
                search_within = "PATID", method = "lucene"),
            hb = use_channel(
                "hb", concept = hemoglobin, search_within = "PATID")),
        combine = combine_channels("alpha & hb", by = "ELTID"),
        output = bin_output(group_by = "PATID"))
    expect_error(
        resolve_variable_spec(cross_source_variable),
        "cannot place signals on the same element")

    cross_source_payload_variable <- variable_spec(
        name = "cross_source_ELTID_payload_is_invalid",
        channels = list(
            alpha = use_channel(
                "text", concept = alpha_signal,
                search_within = "PATID", method = "lucene"),
            beta = use_channel(
                "text", concept = beta_signal,
                search_within = "PATID", method = "lucene"),
            hb = use_channel(
                "hb", concept = hemoglobin, search_within = "PATID")),
        combine = combine_channels("alpha & beta", by = "ELTID"),
        output = from_channel(
            "hb", group_by = "PATID", value = mean(NUMRES, na.rm = TRUE),
            ptype = double(),
            filter_by_qualified = "ELTID"))
    expect_error(
        resolve_variable_spec(cross_source_payload_variable),
        "cannot apply ELTID-qualified keys")

    # Trust-boundary invariant: select_event may select matched rows, but cannot
    # synthesize a crossed EVTID/date pair that rewrites the clinical clock.
    acts <- tibble::tibble(
        PATID = "P1",
        EVTID = c("A1", "A2"),
        ELTID = c("AD1", "AD2"),
        CODEACTE = c("ABCD001", "ABCD001"),
        DATEACTE = as.Date(c("2026-02-03", "2026-02-05")))
    crossed_anchor <- variable_spec(
        name = "crossed_index_event_is_invalid",
        anchor = index_event(
            "pmsi_actes", ccam("ABCD001"), at = "DATEACTE",
            select_event = function(d) {
                selected <- d[1, , drop = FALSE]
                selected$DATEACTE <- d$DATEACTE[[2]]
                selected
            }),
        channels = list(hb = use_channel(
            "hb", concept = hemoglobin, search_within = "PATID",
            window = c(-Inf, 0))),
        output = from_channel(
            "hb", group_by = "PATID", value = max(NUMRES, na.rm = TRUE),
            ptype = double()))
    expect_error(
        run_variable(
            crossed_anchor,
            cohort = tibble::tibble(PATID = "P1"),
            sources = list(pmsi_actes = acts, biology = biology)),
        "only rows from the matched event set")
})

test_that("fine-grain negation uses the scoped source roster", {
    biology <- tibble::tibble(
        PATID = "P1",
        EVTID = c("E1", "E2", "E3"),
        ELTID = c("L1", "L2", "L3"),
        DATEXAM = as.Date(c("2026-02-01", "2026-02-01", "2020-01-01")),
        TYPEANA = c("A", "B", "OTHER"),
        NUMRES = c(1, 1, 1),
        STRRES = NA_character_)
    marker_a <- concept_spec(
        "marker_a", channels = list(a = lab_channel(selector = analyte("A"))))
    marker_b <- concept_spec(
        "marker_b", channels = list(b = lab_channel(selector = analyte("B"))))
    make_lab_variable <- function(name, window = NULL) variable_spec(
        name = name,
        anchor = "anchor_date",
        channels = list(
            a = use_channel(
                "a", concept = marker_a, search_within = "PATID",
                window = window),
            b = use_channel(
                "b", concept = marker_b, search_within = "PATID",
                window = window)),
        combine = combine_channels("!a & !b", by = "EVTID"),
        output = bin_output(group_by = "PATID"))

    lab_runs <- run_protocol(
        list(
            make_lab_variable("unwindowed_roster_complement"),
            make_lab_variable("windowed_roster_complement", c(-1, 1))),
        cohort = tibble::tibble(
            PATID = "P1", anchor_date = as.Date("2026-02-01")),
        sources = list(biology = biology))

    # E3 exists and neither selector hits it, so it qualifies only without the
    # window that excludes its old source row.
    expect_identical(
        vapply(lab_runs, function(run) run$values$value, integer(1)),
        c(unwindowed_roster_complement = 1L,
          windowed_roster_complement = 0L))
    expect_identical(
        lab_runs$unwindowed_roster_complement$audit$combine_keys$EVTID[
            lab_runs$unwindowed_roster_complement$audit$combine_keys$qualifies],
        "E3")
    expect_identical(
        lab_runs$unwindowed_roster_complement$audit$execution_manifest$roster |>
            dplyr::filter(source == "biology") |>
            dplyr::select(level, n_units, enumerated),
        tibble::tibble(
            level = c("PATID", "EVTID", "ELTID"),
            n_units = c(1L, 3L, 3L),
            enumerated = TRUE))

    documents <- data.frame(
        ELTID = c("D1", "D2"),
        RECTXT = c("Alpha marker.", "Beta marker."),
        PATID = "P1", EVTID = c("E1", "E2"),
        RECDATE = as.Date(c("2026-02-01", "2026-02-01")),
        RECTYPE = "CR")
    corpus <- corpustools::create_tcorpus(
        documents, text_columns = "RECTXT", doc_column = "ELTID",
        split_sentences = TRUE, remember_spaces = FALSE, verbose = FALSE)
    alpha <- concept_spec(
        "alpha", channels = list(text = text_channel(lucene_query("alpha"))))
    beta <- concept_spec(
        "beta", channels = list(text = text_channel(lucene_query("beta"))))
    document_complement <- variable_spec(
        name = "document_complement",
        channels = list(
            alpha = use_channel(
                "text", concept = alpha, search_within = "PATID",
                method = "lucene"),
            beta = use_channel(
                "text", concept = beta, search_within = "PATID",
                method = "lucene")),
        combine = combine_channels("!alpha & !beta", by = "ELTID"),
        output = bin_output(group_by = "PATID"))
    document_run <- run_variable(
        document_complement, cohort = tibble::tibble(PATID = "P1"),
        sources = list(documents = corpus, biology = biology))

    # Biology contributes to the shared EVTID roster, but its ELTIDs cannot enter
    # the complement of two document channels.
    expect_identical(document_run$values$value, 0L)
    expect_identical(
        sort(document_run$audit$combine_keys$ELTID), c("D1", "D2"))
})

test_that("an incomplete roster fails only when invisible units can qualify", {
    biology <- tibble::tibble(
        PATID = "P1",
        EVTID = c("E1", "E2", "E3"),
        ELTID = c("L1", "L2", "L3"),
        DATEXAM = as.Date("2026-02-01"),
        TYPEANA = c("A", "B", "OTHER"),
        NUMRES = 1,
        STRRES = NA_character_)
    marker_a <- concept_spec(
        "marker_a", channels = list(a = lab_channel(selector = analyte("A"))))
    marker_b <- concept_spec(
        "marker_b", channels = list(b = lab_channel(selector = analyte("B"))))
    make_variable <- function(expr) variable_spec(
        name = "incomplete_roster",
        channels = list(
            a = use_channel(
                "a", concept = marker_a, search_within = "PATID"),
            b = use_channel(
                "b", concept = marker_b, search_within = "PATID")),
        combine = combine_channels(expr, by = "EVTID"),
        output = bin_output(group_by = "PATID"))
    pre_retrieved_documents <- list(
        coverage = tibble::tibble(
            task_id = "P1", PATID = "P1", coverage_state = "no_candidate"),
        candidates = tibble::tibble(
            task_id = character(), snippet_id = character(),
            hit_ref = character(), PATID = character(), EVTID = character(),
            ELTID = character(), snippet_text = character(),
            hit_text = character(), RECDATE = as.Date(character()),
            RECTYPE = character()))
    sources <- list(
        biology = biology, documents = pre_retrieved_documents)

    # The unknown document units cannot satisfy a & !b: with no observed hits,
    # the leading a is FALSE. The enumerable biology roster is sufficient.
    safe <- run_variable(
        make_variable("a & !b"), cohort = tibble::tibble(PATID = "P1"),
        sources = sources)
    expect_identical(
        list(
            value = safe$values$value,
            qualifying_evtid = safe$audit$combine_keys$EVTID[
                safe$audit$combine_keys$qualifies]),
        list(value = 1L, qualifying_evtid = "E1"))

    # With !a & !b, an unseen document EVTID would qualify precisely because it
    # has no observed hits. The same incomplete roster must remain fatal.
    expect_error(
        run_variable(
            make_variable("!a & !b"),
            cohort = tibble::tibble(PATID = "P1"), sources = sources),
        "cannot enumerate source snapshot\\(s\\): documents")
})

test_that("LLM boundary stays grounded, isolated, and fail closed", {
    new_engine_fields <- c(
        "selection_status", "evidence_kind", "call_status",
        "response_status", "transport_attempts")
    collision_rejected <- vapply(new_engine_fields, function(field) {
        authored <- do.call(
            ellmer::type_object,
            c(list("Invalid engine-owned response field."),
              stats::setNames(
                  list(ellmer::type_string("Must be rejected.")), field)))
        inherits(
            try(
                use_channel(
                    channel = text_channel(lucene_query("taba*")),
                    search_within = "PATID",
                    method = "lucene_llm", response = authored),
                silent = TRUE),
            "try-error")
    }, logical(1))
    expect_true(all(collision_rejected))

    response <- ellmer::type_object(
        "Extraction structurée du statut tabagique.",
        statut_tabagique = ellmer::type_enum(
            c("fumeur", "non_fumeur"),
            "Statut explicitement documenté; ne jamais déduire du silence."),
        temporalite = ellmer::type_string(
            "Temporalité explicitement documentée."))
    smoking <- concept_spec(
        "tabagisme",
        channels = list(text = text_channel(selector = lucene_query("taba*"))))
    make_variable <- function(max_candidates = NULL) variable_spec(
        name = "tabagisme",
        channels = list(text_tabagisme = use_channel(
            channel = "text",
            concept = smoking,
            search_within = "PATID",
            method = "lucene_llm",
            response = response,
            max_candidates = max_candidates)),
        output = from_channel("text_tabagisme", group_by = "EVTID"))

    cohort <- tibble::tibble(
        PATID = c("P1", "P2"), EVTID = c("TARGET1", "TARGET2"))
    task_ids <- paste(cohort$PATID, cohort$EVTID, sep = "::")
    documents <- list(
        coverage = tibble::tibble(
            task_id = task_ids,
            PATID = cohort$PATID,
            EVTID = cohort$EVTID,
            coverage_state = c("candidate", "no_candidate")),
        candidates = tibble::tibble(
            task_id = task_ids[[1]], snippet_id = "S001", hit_ref = "H001",
            PATID = "P1", EVTID = "SOURCE_STAY", ELTID = "D001",
            snippet_text = "Tabagisme actif documenté.",
            hit_text = "Tabagisme actif", RECDATE = as.Date("2026-03-01"),
            RECTYPE = "CR"))

    seen <- new.env(parent = emptyenv())
    seen$types <- list()
    seen$snippet_ids <- "S001"
    seen$calls <- 0L
    testthat::local_mocked_bindings(
        .chat_metadata = function(chat) list(
            provider = "test", model = "fake", params = list(),
            temperature = 0, seed = 1L, max_tokens = 100),
        .call_chat = function(chat, prompt, type, system_prompt, metadata) {
            seen$calls <- seen$calls + 1L
            seen$types[[length(seen$types) + 1L]] <- type
            fields <- names(S7::props(type)$properties)
            result <- list(
                statut_tabagique = "fumeur",
                temporalite = "actuel",
                snippet_ids = seen$snippet_ids)
            if ("rationale" %in% fields) {
                result$rationale <- "Le texte documente un tabagisme actif."
            }
            list(
                status = "completed", result = result, error = NA_character_,
                n_tries = 1L, errors = character(), started_at = Sys.time(),
                latency_ms = 0, partial_response = NA_character_,
                output_tokens = 10, inferred_finish_reason = "stop")
        },
        .package = "extractionengine")

    expect_error(
        run_variable(
            make_variable(), cohort,
            sources = list(documents = documents)),
        "LLM execution requires chat = <ellmer Chat>", fixed = TRUE)

    run <- run_variable(
        make_variable(), cohort,
        sources = list(documents = documents), chat = structure(list(), class = "fake"))

    # Public-contract invariant: a candidate publishes the authored frame while
    # no-candidate remains typed missing and does not trigger a model call.
    expect_identical(
        run$values |>
            dplyr::select(
                statut_tabagique, temporalite, rationale, channel_coverage),
        tibble::tibble(
            statut_tabagique = c("fumeur", NA_character_),
            temporalite = c("actuel", NA_character_),
            rationale = c(
                "Le texte documente un tabagisme actif.", NA_character_),
            channel_coverage = c("complete", "partial")))
    expect_identical(seen$calls, 1L)
    expect_false("snippet_ids" %in% names(run$values))

    # Selection describes the Lucene boundary; processing describes the LLM
    # boundary. No candidate therefore means no_match + not_called, whereas a
    # grounded response means matched + completed.
    expect_identical(
        run$channel_status |>
            dplyr::select(selection_status, processing_status),
        tibble::tibble(
            selection_status = c("matched", "no_match"),
            processing_status = c("completed", "not_called")))
    expect_length(
        intersect(
            c("status", "hit", "processing_state", "contribution", "error"),
            names(run$channel_status)),
        0L)

    # Grounded evidence keeps target and native stay identities distinct while
    # exposing only the canonical public coordinate.
    expect_identical(
        run$evidence |>
            dplyr::select(
                EVTID, source_EVTID, evidence_ref, evidence_kind, snippet_id),
        tibble::tibble(
            EVTID = "TARGET1", source_EVTID = "SOURCE_STAY",
            evidence_ref = "H001", evidence_kind = "llm_citation",
            snippet_id = "S001"))
    expect_identical(
        intersect(c("evidence_ref", "source_row_id", "hit_ref"),
                  names(run$evidence)),
        "evidence_ref")
    expect_identical(
        run$audit$lineage |>
            dplyr::select(
                furthest_stage, artifact_type, artifact_id, artifact_position,
                source_row_ref, source_EVTID),
        tibble::tibble(
            furthest_stage = "cited",
            artifact_type = "snippet",
            artifact_id = "S001",
            artifact_position = 1L,
            source_row_ref = "D001",
            source_EVTID = "SOURCE_STAY"))
    expect_false("internal" %in% names(run$audit))
    expect_identical(
        list(
            declared_fields = intersect(
                c("declared_model", "declared_model_params"),
                names(run$audit$execution_manifest$spec$channels$text_tabagisme)),
            observed_model = run$audit$llm_calls$model),
        list(declared_fields = character(), observed_model = "fake"))
    expect_identical(
        intersect(
            c("call_status", "response_status", "transport_attempts",
              "attempt_status", "processing_status", "n_tries", "definition"),
            names(run$audit$llm_calls)),
        c("call_status", "response_status", "transport_attempts"))

    # Schema-boundary invariant: engine-owned fields are injected dynamically,
    # and the citation enum contains only prompt-visible IDs.
    default_properties <- S7::props(seen$types[[1]])$properties
    expect_setequal(
        names(default_properties),
        c("statut_tabagique", "temporalite", "rationale", "snippet_ids"))
    evidence_enum <- S7::props(default_properties$snippet_ids)$items
    expect_identical(S7::props(evidence_enum)$values, "S001")

    # Ratified citation policy: mixed citations keep the grounded value and only
    # materialize the supplied ID.
    seen$snippet_ids <- c("S001", "S999")
    mixed_citations <- run_variable(
        make_variable(), cohort,
        sources = list(documents = documents),
        chat = structure(list(), class = "fake"))
    expect_identical(
        list(
            value = mixed_citations$values$statut_tabagique[[1]],
            warning = mixed_citations$values$citation_warning[[1]],
            evidence = mixed_citations$evidence$snippet_id),
        list(value = "fumeur", warning = TRUE, evidence = "S001"))

    # Invented-only citations cannot publish a value or evidence and remain
    # explicitly reviewable rather than becoming a model transport error.
    seen$snippet_ids <- "S999"
    invented_only <- run_variable(
        make_variable(), cohort,
        sources = list(documents = documents),
        chat = structure(list(), class = "fake"))
    expect_identical(
        list(
            value = invented_only$values$statut_tabagique[[1]],
            coverage = invented_only$values$channel_coverage[[1]],
            needs_review = invented_only$values$needs_review[[1]],
            selection = invented_only$channel_status$selection_status[[1]],
            processing = invented_only$channel_status$processing_status[[1]],
            evidence_rows = nrow(invented_only$evidence)),
        list(
            value = NA_character_, coverage = "partial", needs_review = TRUE,
            selection = "matched", processing = "invalid",
            evidence_rows = 0L))

    # Empty citations exercise the distinct zero-ID path: invalid, not errored.
    seen$snippet_ids <- character()
    uncited <- run_variable(
        make_variable(), cohort,
        sources = list(documents = documents),
        chat = structure(list(), class = "fake"))
    expect_identical(
        list(
            value = uncited$values$statut_tabagique[[1]],
            needs_review = uncited$values$needs_review[[1]],
            task_validity = uncited$audit$llm_calls$task_validity[[1]],
            error = uncited$audit$llm_calls$error[[1]]),
        list(
            value = NA_character_, needs_review = TRUE,
            task_validity = "invalid", error = NA_character_))

    # Native occurrences remain distinct for relational algebra, but repeated
    # normalized hit text consumes only one bounded LLM prompt slot.
    crowded_documents <- documents
    crowded_documents$candidates <- dplyr::bind_rows(
        documents$candidates,
        dplyr::mutate(
            documents$candidates,
            snippet_id = "S002", hit_ref = "H002", ELTID = "D002"),
        dplyr::mutate(
            documents$candidates,
            snippet_id = "S003", hit_ref = "H003", ELTID = "D003",
            hit_text = "Sevrage tabagique",
            snippet_text = "Sevrage tabagique documenté."))
    crowded_documents$candidates$hit_text <- NULL
    seen$snippet_ids <- "S001"
    crowded_run <- run_variable(
        make_variable(max_candidates = 2L), cohort,
        sources = list(documents = crowded_documents),
        chat = structure(list(), class = "fake"))
    prompt_type <- seen$types[[length(seen$types)]]
    prompt_evidence_enum <-
        S7::props(S7::props(prompt_type)$properties$snippet_ids)$items
    expect_identical(
        S7::props(prompt_evidence_enum)$values,
        c("S001", "S003"))
    expect_identical(
        crowded_run$audit$lineage |>
            dplyr::filter(EVTID == "TARGET1") |>
            dplyr::arrange(artifact_id) |>
            dplyr::select(
                artifact_id, furthest_stage, artifact_position, source_row_ref),
        tibble::tibble(
            artifact_id = c("S001", "S002", "S003"),
            furthest_stage = c("cited", "selected", "model_input"),
            artifact_position = c(1L, 2L, 2L),
            source_row_ref = c("D001", "D002", "D003")))
    crowded_counts <- crowded_run$audit$counts |>
        dplyr::filter(
            EVTID == "TARGET1", channel == "text_tabagisme",
            stage %in% c("selector", "model_input"))
    expect_identical(
        crowded_counts$n[match(
            c("selector", "model_input"), crowded_counts$stage)],
        c(3L, 2L))

    # Pre-retrieved fixtures must describe a possible retrieval result. A task
    # cannot claim no candidate while still supplying positive candidate rows.
    contradictory_documents <- documents
    contradictory_documents$coverage$coverage_state[[1]] <- "no_candidate"
    expect_error(
        run_variable(
            make_variable(), cohort,
            sources = list(documents = contradictory_documents),
            chat = structure(list(), class = "fake")),
        "if and only if candidate rows exist")

    # Until hit_when exists, an LLM payload has no implicit membership semantics.
    expect_error(
        variable_spec(
            name = "llm_membership_is_not_implicit",
            channels = list(
                text_llm = use_channel(
                    channel = "text",
                    concept = smoking,
                    search_within = "PATID",
                    method = "lucene_llm",
                    response = response,
                    rationale = FALSE),
                text_lucene = use_channel(
                    channel = "text",
                    concept = smoking,
                    search_within = "PATID",
                    method = "lucene")),
            combine = combine_channels(
                "text_llm & text_lucene", by = "PATID"),
            output = bin_output(group_by = "PATID")),
        "cannot currently use lucene_llm activation\\(s\\): text_llm")

    # The model-call half is a relation with one row per task. A second attempt
    # row for the same task would make the published call state depend on which
    # one happened to be read first.
    llm_call_states <- getFromNamespace(".llm_call_states", "extractionengine")
    expect_error(
        llm_call_states(
            list(attempts = tibble::tibble(
                task_id = c("P1", "P1"), attempt_status = "completed",
                processing_status = "ok", task_validity = "valid")),
            "P1"),
        "at most one row per task_id")

    # A pre-retrieved input declares the one fact it cannot observe about
    # itself, so a declaration that skips a task must fail instead of quietly
    # reading as ineligible.
    activation_eligibility <- getFromNamespace(
        ".activation_eligibility", "extractionengine")
    expect_error(
        activation_eligibility(
            list(
                declared_eligibility = tibble::tibble(
                    task_id = "P1", eligible = TRUE),
                executed_tasks = c("P1", "P2")),
            c("P1", "P2")),
        "must cover every task_id")
})

test_that("a gated payload activation runs only for qualifying tasks", {
    biology <- tibble::tibble(
        PATID = c("P1", "P1", "P2", "P2"),
        EVTID = c("E1", "E1", "E2", "E2"),
        ELTID = paste0("L", 1:4),
        DATEXAM = as.Date("2026-02-01"),
        TYPEANA = c("A", "HB.HB", "OTHER", "HB.HB"),
        NUMRES = c(1, 10, 1, 20),
        STRRES = NA_character_)
    marker <- concept_spec(
        "marker", channels = list(a = lab_channel(selector = analyte("A"))))
    hemoglobin <- concept_spec(
        "hemoglobin",
        channels = list(h = lab_channel(selector = analyte("HB.HB"))))
    cohort <- tibble::tibble(PATID = c("P1", "P2"))
    gate_channels <- list(
        gate_a = use_channel("a", concept = marker, search_within = "PATID"),
        gate_b = use_channel("a", concept = marker, search_within = "PATID"))

    deterministic <- run_variable(
        variable_spec(
            name = "gated_payload",
            channels = c(gate_channels, list(
                payload = use_channel(
                    "h", concept = hemoglobin, search_within = "PATID"))),
            combine = combine_channels("gate_a & gate_b", by = "PATID"),
            output = from_channel(
                "payload", group_by = "PATID", value = mean(NUMRES),
                ptype = double())),
        cohort, sources = list(biology = biology))

    # P2 owns a payload row the selector would have matched, but the gate
    # excludes P2, so the activation never runs there. The skip is published as
    # what it is instead of being reported as a search that found nothing.
    expect_identical(deterministic$values$value, c(10, NA_real_))
    payload_status <- deterministic$channel_status[
        deterministic$channel_status$channel == "payload", ]
    expect_identical(
        payload_status$selection_status[
            match(c("P1", "P2"), payload_status$PATID)],
        c("matched", "not_executed"))
    expect_identical(
        unique(deterministic$audit$lineage$PATID[
            deterministic$audit$lineage$channel == "payload"]),
        "P1")
    expect_false(any(
        deterministic$audit$counts$channel == "payload" &
        deterministic$audit$counts$PATID == "P2" &
        deterministic$audit$counts$stage %in% c("pre_selector", "selector")))

    # The same rule is what keeps a gated model activation from being called for
    # every task and discarded: both tasks have a retrieved snippet, only one
    # qualifies, and exactly one model call is made.
    response <- ellmer::type_object(
        "Extraction structurée du statut tabagique.",
        statut_tabagique = ellmer::type_enum(
            c("fumeur", "non_fumeur"),
            "Statut explicitement documenté."))
    smoking <- concept_spec(
        "tabagisme",
        channels = list(text = text_channel(selector = lucene_query("taba*"))))
    documents <- list(
        coverage = tibble::tibble(
            task_id = c("P1", "P2"), PATID = c("P1", "P2"),
            coverage_state = "candidate"),
        candidates = tibble::tibble(
            task_id = c("P1", "P2"), snippet_id = c("S001", "S001"),
            hit_ref = c("H001", "H002"), PATID = c("P1", "P2"),
            EVTID = c("E1", "E2"), ELTID = c("D001", "D002"),
            snippet_text = "Tabagisme actif documenté.",
            hit_text = "Tabagisme actif", RECDATE = as.Date("2026-02-01"),
            RECTYPE = "CR"))
    calls <- new.env(parent = emptyenv())
    calls$n <- 0L
    testthat::local_mocked_bindings(
        .chat_metadata = function(chat) list(
            provider = "test", model = "fake", params = list(),
            temperature = 0, seed = 1L, max_tokens = 100),
        .call_chat = function(chat, prompt, type, system_prompt, metadata) {
            calls$n <- calls$n + 1L
            list(
                status = "completed",
                result = list(
                    statut_tabagique = "fumeur", snippet_ids = "S001"),
                error = NA_character_, n_tries = 1L, errors = character(),
                started_at = Sys.time(), latency_ms = 0,
                partial_response = NA_character_, output_tokens = 10,
                inferred_finish_reason = "stop")
        },
        .package = "extractionengine")

    gated_llm <- run_variable(
        variable_spec(
            name = "gated_llm_payload",
            channels = c(gate_channels, list(
                text_tabagisme = use_channel(
                    channel = "text", concept = smoking,
                    search_within = "PATID", method = "lucene_llm",
                    response = response, rationale = FALSE))),
            combine = combine_channels("gate_a & gate_b", by = "PATID"),
            output = from_channel("text_tabagisme", group_by = "PATID")),
        cohort,
        sources = list(biology = biology, documents = documents),
        chat = structure(list(), class = "fake"))

    expect_identical(
        list(
            calls = calls$n,
            published = gated_llm$values$statut_tabagique,
            status = gated_llm$channel_status$selection_status[
                gated_llm$channel_status$channel == "text_tabagisme"]),
        list(
            calls = 1L,
            published = c("fumeur", NA_character_),
            status = c("matched", "not_executed")))
})

test_that("the execution manifest mirrors the resolved spec without live objects", {
    biology <- lab_fixture()
    acts <- tibble::tibble(
        PATID = "P1", EVTID = "A1", ELTID = "AD1",
        CODEACTE = "ABCD001", DATEACTE = as.Date("2026-01-03"))
    potassium <- concept_spec(
        "potassium",
        channels = list(result = lab_channel(selector = analyte("K.K"))))
    upper_limit <- 6
    variable <- variable_spec(
        name = "manifest_shape",
        anchor = index_event(
            "pmsi_actes", ccam("ABCD001"),
            select_event = function(rows) rows[1, , drop = FALSE]),
        channels = list(result = use_channel(
            "result", concept = potassium, search_within = "PATID",
            window = c(-Inf, 0),
            filter_rows = NUMRES < .env$upper_limit,
            group_by = "EVTID", filter_groups = any(!is.na(NUMRES)))),
        output = from_channel(
            "result", group_by = "PATID", value = mean(NUMRES, na.rm = TRUE),
            ptype = double()))
    run <- run_variable(
        variable, cohort = tibble::tibble(PATID = "P1"),
        sources = list(pmsi_actes = acts, biology = biology))
    manifest <- run$audit$execution_manifest

    # The manifest walks the resolved spec instead of copying it field by field,
    # so every configured field arrives in its resolved order. A hand-written
    # copy is what lets a new use_channel() argument go unrecorded.
    resolved <- resolve_variable_spec(variable)
    expect_identical(
        names(manifest$spec$channels$result),
        names(Filter(Negate(is.null), unclass(resolved$channels$result))))

    # Author code is recorded as text, and the anchor column is the one that
    # ran: an authored NULL `at` means the source's registered clock.
    expect_identical(
        list(
            filter_rows = manifest$spec$channels$result$filter_rows,
            filter_groups = manifest$spec$channels$result$filter_groups,
            value = manifest$spec$output$value,
            at = manifest$spec$anchor$at,
            select_event_is_text = is.character(
                manifest$spec$anchor$select_event) &&
                grepl("^function", manifest$spec$anchor$select_event)),
        list(
            filter_rows = "NUMRES < .env$upper_limit",
            filter_groups = "any(!is.na(NUMRES))",
            value = "mean(NUMRES, na.rm = TRUE)",
            at = "DATEACTE",
            select_event_is_text = TRUE))

    # Nothing live survives the snapshot, and an environment reached as a value
    # fails rather than riding into the audit trail as a session capsule.
    carries_binding <- function(x) {
        if (is.function(x) || is.environment(x) || rlang::is_quosure(x)) {
            return(TRUE)
        }
        if (!is.list(x)) return(FALSE)
        any(vapply(x, carries_binding, logical(1)))
    }
    expect_false(carries_binding(manifest$spec))
    expect_error(
        .manifest_snapshot(list(session = new.env())),
        "cannot record an environment")

    # The recorded system prompt is the text the executor sent. An activation
    # that authors none is run with the package default, and a manifest that
    # left the field empty would describe the authoring, not the call.
    sent <- new.env(parent = emptyenv())
    testthat::local_mocked_bindings(
        .chat_metadata = function(chat) list(
            provider = "test", model = "fake", params = list(),
            temperature = 0, seed = 1L, max_tokens = 100),
        .call_chat = function(chat, prompt, type, system_prompt, metadata) {
            sent$system_prompt <- system_prompt
            list(
                status = "completed",
                result = list(smoker = "oui", snippet_ids = "S001"),
                error = NA_character_, n_tries = 1L, errors = character(),
                started_at = Sys.time(), latency_ms = 0,
                partial_response = NA_character_, output_tokens = 10,
                inferred_finish_reason = "stop")
        },
        .package = "extractionengine")

    documents <- list(
        coverage = tibble::tibble(
            task_id = "P1", PATID = "P1", EVTID = NA_character_,
            coverage_state = "candidate"),
        candidates = tibble::tibble(
            task_id = "P1", snippet_id = "S001", hit_ref = "H001",
            PATID = "P1", EVTID = "SOURCE_STAY", ELTID = "D001",
            snippet_text = "Tabagisme actif documenté.",
            hit_text = "Tabagisme actif", RECDATE = as.Date("2026-03-01"),
            RECTYPE = "CR"))
    llm_run <- run_variable(
        variable_spec(
            name = "manifest_prompt",
            channels = list(text = use_channel(
                channel = text_channel(selector = lucene_query("taba*")),
                search_within = "PATID", method = "lucene_llm",
                rationale = FALSE,
                response = ellmer::type_object(
                    smoker = ellmer::type_string("Statut documenté.")))),
            output = from_channel("text", group_by = "PATID")),
        cohort = tibble::tibble(PATID = "P1"),
        sources = list(documents = documents),
        chat = structure(list(), class = "fake"))
    expect_identical(
        list(
            recorded = llm_run$audit$execution_manifest$spec$channels$text$
                system_prompt,
            sent_the_package_default = identical(
                sent$system_prompt, DEFAULT_LLM_SYSTEM_PROMPT)),
        list(recorded = sent$system_prompt, sent_the_package_default = TRUE))
})

test_that("the manifest identifies the source snapshot and the runtime", {
    biology <- tibble::tibble(
        PATID = c("P1", "P1", "P2"), EVTID = c("E1", "E1", "E2"),
        ELTID = c("L1", "L2", "L3"),
        DATEXAM = as.Date("2026-01-01") + 0:2,
        TYPEANA = "K.K", NUMRES = c(4.2, 5.1, 3.9), STRRES = NA_character_)
    potassium <- concept_spec(
        "potassium",
        channels = list(result = lab_channel(selector = analyte("K.K"))))
    make_variable <- function(name) variable_spec(
        name = name,
        channels = list(result = use_channel(
            "result", concept = potassium, search_within = "PATID")),
        output = from_channel(
            "result", group_by = "PATID", value = mean(NUMRES),
            ptype = double()))
    cohort <- tibble::tibble(PATID = "P1")
    digest_of <- function(sources) {
        run <- run_variable(make_variable("k_mean"), cohort, sources = sources)
        run$audit$execution_manifest$sources$biology$digest
    }

    # The digest identifies the snapshot the EXECUTOR read, which is the
    # prepared frame: one hash covers the caller's input, the cohort
    # restriction, and the normalization. A row belonging to a patient outside
    # the cohort is therefore invisible to it. It has to be appended after the
    # kept rows: source_row_id carries the original row position, so inserting
    # ahead of them would renumber rows the run really did read.
    baseline <- digest_of(list(cohort = cohort, biology = biology))
    outside <- dplyr::bind_rows(biology, tibble::tibble(
        PATID = "P9", EVTID = "E9", ELTID = "L9",
        DATEXAM = as.Date("2026-02-01"), TYPEANA = "K.K", NUMRES = 1,
        STRRES = NA_character_))
    changed <- biology
    changed$NUMRES[[1]] <- 9.9
    expect_identical(
        list(
            outside_the_cohort = digest_of(
                list(cohort = cohort, biology = outside)) == baseline,
            inside_the_cohort = digest_of(
                list(cohort = cohort, biology = changed)) == baseline),
        list(outside_the_cohort = TRUE, inside_the_cohort = FALSE))

    # A protocol prepares and hashes once, so every variable of a study records
    # the same snapshot: the identity is what makes "the same sources" a fact
    # rather than an assumption.
    protocol <- run_protocol(
        list(make_variable("k_one"), make_variable("k_two")),
        cohort, sources = list(cohort = cohort, biology = biology))
    manifests <- lapply(protocol, function(run) run$audit$execution_manifest)
    expect_identical(
        manifests$k_one$sources$biology$digest,
        manifests$k_two$sources$biology$digest)

    # The declared cohort is supplied and read, and is recorded; it binds no
    # source roles, because it is not a registered EDSAN source.
    expect_identical(
        list(
            names = names(manifests$k_one$sources$cohort),
            n_rows = manifests$k_one$sources$cohort$n_rows),
        list(names = c("class", "n_rows", "digest"), n_rows = 1L))

    # The versions that can change a value without the definition changing:
    # redsan owns normalization, corpustools retrieval, ellmer transport. The
    # list is read from the installed DESCRIPTION, so an empty parse would show
    # up here rather than as a silently version-less manifest.
    runtime <- manifests$k_one$runtime
    expect_identical(
        list(
            engine = runtime$packages[["extractionengine"]],
            owners = all(
                c("redsan", "corpustools", "ellmer") %in%
                    names(runtime$packages)),
            r = runtime$r),
        list(
            engine = as.character(utils::packageVersion("extractionengine")),
            owners = TRUE,
            r = as.character(getRversion())))
})

test_that("simple external parameters are photographed once before execution", {
    biology <- tibble::tibble(
        PATID = c("P1", "P1", "P2"), EVTID = c("E1", "E1", "E2"),
        ELTID = c("L1", "L2", "L3"),
        DATEXAM = as.Date("2026-01-01") + 0:2,
        TYPEANA = "K.K", NUMRES = c(4.2, 5.1, 3.9), STRRES = NA_character_)
    potassium <- concept_spec(
        "potassium",
        channels = list(result = lab_channel(selector = analyte("K.K"))))
    cohort <- tibble::tibble(PATID = c("P1", "P2"))
    run_at <- function(threshold) {
        soglia <- threshold
        run_variable(
            variable_spec(
                name = "k_mean",
                channels = list(result = use_channel(
                    "result", concept = potassium, search_within = "PATID",
                    filter_rows = NUMRES >= .env$soglia)),
                output = from_channel(
                    "result", group_by = "PATID", value = mean(NUMRES),
                    ptype = double())),
            cohort, sources = list(biology = biology))
    }

    # The value that ran is recorded, so two runs of the same definition are
    # distinguishable. The manifest used to be identical for both.
    low <- run_at(4)
    high <- run_at(5)
    expect_identical(
        list(
            values = c(low$values$value[[1]], high$values$value[[1]]),
            recorded = c(
                low$audit$execution_manifest$parameters$captured$soglia,
                high$audit$execution_manifest$parameters$captured$soglia)),
        list(values = c(4.65, 5.1), recorded = c(4, 5)))

    # Once per run, not once per task: an active binding counting its own reads
    # is forced a single time however many tasks the run has. Reading it live
    # returned one read per task, so a value could change mid-run.
    reads <- 0L
    env <- rlang::env(parent = globalenv())
    rlang::env_bind_active(env, live_threshold = function(value) {
        reads <<- reads + 1L
        4
    })
    live <- run_variable(
        variable_spec(
            name = "k_live",
            channels = list(result = use_channel(
                "result", concept = potassium, search_within = "PATID",
                filter_rows = !!rlang::new_quosure(
                    quote(NUMRES >= .env$live_threshold), env))),
            output = from_channel(
                "result", group_by = "PATID", value = mean(NUMRES),
                ptype = double())),
        cohort, sources = list(biology = biology))
    expect_identical(
        list(reads = reads, value = live$values$value[[1]]),
        list(reads = 1L, value = 4.65))

    # An option list is the idiom the data-mask rule requires for external
    # configuration, so it keeps working; it is not photographed, and the
    # manifest names it rather than implying the run was fully captured.
    weight_options <- list(na_rm = TRUE)
    listed <- run_variable(
        variable_spec(
            name = "k_options",
            channels = list(result = use_channel(
                "result", concept = potassium, search_within = "PATID")),
            output = from_channel(
                "result", group_by = "PATID",
                value = mean(NUMRES, na.rm = .env$weight_options$na_rm),
                ptype = double())),
        cohort, sources = list(biology = biology))
    expect_identical(
        list(
            value = listed$values$value[[1]],
            captured = names(
                listed$audit$execution_manifest$parameters$captured),
            named = listed$audit$execution_manifest$parameters$not_captured),
        list(value = 4.65, captured = NULL, named = "weight_options"))

    # One variable is one definition. A name meaning two different values
    # inside it cannot be recorded once, so it fails rather than recording
    # whichever expression happened to be walked last.
    first <- rlang::env(parent = globalenv(), soglia = 4)
    second <- rlang::env(parent = globalenv(), soglia = 5)
    expect_error(
        run_variable(
            variable_spec(
                name = "k_conflict",
                channels = list(result = use_channel(
                    "result", concept = potassium, search_within = "PATID",
                    filter_rows = !!rlang::new_quosure(
                        quote(NUMRES >= .env$soglia), first))),
                output = from_channel(
                    "result", group_by = "PATID",
                    value = !!rlang::new_quosure(
                        quote(mean(NUMRES[NUMRES >= .env$soglia])), second),
                    ptype = double())),
            cohort, sources = list(biology = biology)),
        "two different values")
})
