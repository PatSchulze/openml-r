#' @title Run mlr learner on OpenML task.
#'
#' @description
#' Run task with a specified learner from \pkg{mlr} and produce predictions.
#' By default, the evaluation measure contained in the task is used.
#'
#' @template arg_task
#' @param learner [\code{\link[mlr]{Learner}}]\cr
#'   Learner from package mlr to run the task.
#' @param measures [\code{\link[mlr]{Measure}}]\cr
#'  Additional measures that should be computed.
#' @template arg_verbosity
#' @template arg_seed
#' @param scimark.vector [\code{numeric(6)}]\cr
#'   Optional vector of performance measurements computed by the scientific SciMark
#'   benchmark. May be computed using the \pkg{rscimark} R package.
#'   Default is \code{NULL}, which means no performance measurements.
#' @param models [\code{logical(1)}]\cr
#'   This argument is passed to \code{\link[mlr]{benchmark}}.
#'   Should all fitted models be stored in the \code{\link[mlr]{ResampleResult}}?
#'   Default is \code{TRUE}.
#' @param ... [any]\cr
#'   Further arguments that are passed to \code{\link{convertOMLTaskToMlr}}.
#' @return [\code{list}] Named list with the following components:
#' \describe{
#'   \item{run}{The \code{\link{OMLRun}} object.}
#'   \item{bmr}{Benchmark result returned by \code{\link[mlr]{benchmark}}.}
#'   \item{flow}{The generated \code{\link{OMLFlow}} object.}
#' }
#' @seealso \code{\link{getOMLTask}}, \code{\link[mlr]{makeLearner}}
#' @aliases OMLMlrRun
#' @example /inst/examples/runTaskMlr.R
#' @export
runTaskMlr = function(task, learner, measures = NULL, verbosity = NULL, seed = 1,
  scimark.vector = NULL, models = TRUE, ...) {
  assert(checkString(learner), checkClass(learner, "Learner"))
  if (is.character(learner))
    learner = mlr::makeLearner(learner)
  assertClass(task, "OMLTask")
  assertChoice(task$task.type, c("Supervised Classification", "Supervised Regression"))
  assert(checkIntegerish(seed), checkClass(seed, "OMLSeedParList"))
  if (!is.null(scimark.vector))
    assertNumeric(scimark.vector, lower = 0, len = 6, finite = TRUE, any.missing = FALSE, all.missing = FALSE)

  # create parameter list
  parameter.setting = makeOMLRunParList(learner)
  if (testIntegerish(seed)) {
    seed.setting = makeOMLSeedParList(seed = seed)
  } else {
    seed.setting = seed
  }

  # set default evaluation measure for classification and regression
  if (task$input$evaluation.measures == "") {
    if (task$task.type == "Supervised Classification")
      task$input$evaluation.measures = "predictive_accuracy"
    else
      task$input$evaluation.measures = "root_mean_squared_error"
  }

  # get mlr show.info from verbosity level
  if (is.null(verbosity))
    verbosity = getOMLConfig()$verbosity
  show.info = (verbosity > 0L)

  # create Flow
  flow = convertMlrLearnerToOMLFlow(learner)

  # Create mlr task with estimation procedure and evaluation measure
  z = convertOMLTaskToMlr(task, measures = measures, verbosity = verbosity, ...)

  # Create OMLRun
  setOMLSeedParList(seed.setting, flow = flow)
  bmr = mlr::benchmark(learner, z$mlr.task, z$mlr.rin, measures = z$mlr.measures,
    models = models, show.info = show.info)
  res = bmr$results[[1]][[1]]

  # add error message
  tr.err = unique(res$err.msgs$train)
  pr.err = unique(res$err.msgs$predict)
  if (any(!is.na(tr.err))) {
    tr.msg = paste0("Error in training the model: \n ", collapse(tr.err, sep = "\n "))
  } else {
    tr.msg = NULL
  }
  if (any(!is.na(pr.err))) {
    pr.msg = paste0("Error in making predictions: \n ", collapse(pr.err, sep = "\n "))
  } else {
    pr.msg = NULL
  }
  msg = paste0(tr.msg, pr.msg)

  # create run
  run = makeOMLRun(task.id = task$task.id,
    error.message = ifelse(length(msg) == 0, NA_character_, msg))
  run$predictions = reformatPredictions(res$pred$data, task)

  # Add parameter settings and seed
  run$parameter.setting = append(parameter.setting, seed.setting)
  #run$flow = flow

  par.names = extractSubList(run$parameter.setting, "name")
  if (length(par.names) != length(unique(par.names)))
    stop("duplicated names in 'parameter.setting' and/or 'seed.setting'")
  # run$flow$source.path = createLearnerSourcefile(learner)

  if (!is.null(scimark.vector)) {
    run$scimark.vector = scimark.vector
  }
  makeS3Obj("OMLMlrRun", run = run, bmr = bmr, flow = flow)
}

