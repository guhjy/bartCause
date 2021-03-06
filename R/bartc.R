flattenSamples <- function(y) {
  x <- NULL ## R CMD check
  if (!is.null(dim(y)) && length(dim(y)) > 2L) evalx(dim(y), matrix(y, nrow = x[1L], ncol = x[2L] * x[3L])) else y
}

bartc <- function(
  response, treatment, confounders, data, subset, weights,
  method.rsp = c("bart", "pweight", "tmle"),
  method.trt = c("none", "glm", "bart", "bart.xval"),
  estimand   = c("ate", "att", "atc"),
  group.by = NULL,
  commonSup.rule = c("none", "sd", "chisq"),
  commonSup.cut  = c(NA_real_, 1, 0.05),
  propensityScoreAsCovariate = TRUE, use.rbart = FALSE,
  keepCall = TRUE, verbose = TRUE,
  ...
)
{
  matchedCall <- match.call()
  callingEnv <- parent.frame(1L)
  
  verbose <- verbose
  givenCall <- if (keepCall) matchedCall else call("NULL")
  
  group.by <- eval(redirectCall(matchedCall, quoteInNamespace(getGroupBy)), envir = callingEnv)
  
  matchedCall$group.by <- group.by
  matchedCall$verbose <- NULL
  
  ## check validity of character vector arguments by comparing to function prototype
  for (argName in c("method.rsp", "estimand", "commonSup.rule")) {
    arg <- get(argName)
    if (!is.character(arg) || arg[1L] %not_in% eval(formals(bartCause::bartc)[[argName]]))
      stop(argName, " must be in '", paste0(eval(formals(bartCause::bartc)[[argName]]), collapse = "', '"), "'")
    assign(argName, arg[1L])
  }
    
  fit.trt <- p.score <- samples.p.score <- NULL
  if (is.numeric(method.trt)) {
    if (!is.null(dim(method.trt))) {
      samples.p.score <- method.trt
      p.score <- apply(samples.p.score, 1L, mean)
    } else  {
      p.score <- method.trt
    }
    method.trt <- "given"
  } else if (is.character(method.trt)) {
    method.trt <- method.trt[1L]
    if (method.trt %not_in% eval(formals(bartCause::bartc)$method.trt))
      stop("method.trt must be in '", paste0(eval(formals(bartCause::bartc)$method.trt), collapse = "', '"), "'")
    
    
    treatmentCall <- switch(method.trt,
      glm       = redirectCall(matchedCall, quoteInNamespace(getGLMTreatmentFit)),
      bart      = redirectCall(matchedCall, quoteInNamespace(getBartTreatmentFit)),
      bart.xval = redirectCall(matchedCall, quoteInNamespace(getBartXValTreatmentFit)),
      none      = NULL)
    
    
    if (!is.null(treatmentCall)) {
      
      if (verbose) cat("fitting treatment model via method '", method.trt, "'\n", sep = "")
      
      massign[fit.trt, p.score, samples.p.score] <- eval(treatmentCall, envir = callingEnv)
    }
  } else {
    stop("method.trt must be in '", paste0(eval(formals(bartCause::bartc)$method.trt), collapse = "', '"), "' or a fixed vector")
  }
    
  if (is.na(propensityScoreAsCovariate))
    stop("propensityScoreAsCovariate must be TRUE or FALSE")
  if (method.rsp %in% c("pweight", "tmle") && method.trt == "none")
    stop("response method '", method.rsp, "' requires propensity score estimation")
  if (method.rsp == "bart" && propensityScoreAsCovariate == FALSE && method.trt != "none")
    warning("for response method 'bart', propensity score not used unless included as covariate")
  
  responseCall <- switch(method.rsp,
    bart    = redirectCall(matchedCall, quoteInNamespace(getBartResponseFit)),
    pweight = redirectCall(matchedCall, quoteInNamespace(getPWeightResponseFit)),
    tmle    = redirectCall(matchedCall, quoteInNamespace(getTMLEResponseFit)))
  
  if (!is.null(matchedCall$commonSup.rule)) {
     if (is.null(matchedCall$commonSup.cut))
       commonSup.cut <- eval(formals(bartc)$commonSup.cut)[match(commonSup.rule, eval(formals(bartc)$commonSup.rule))]
    responseCall$commonSup.rule <- commonSup.rule[1L]
    responseCall$commonSup.cut <- commonSup.cut[1L]
  } else {
    responseCall$commonSup.rule <- "none"
    responseCall$commonSup.cut  <- NA_real_
  }

  responseCall <- addCallDefaults(responseCall, bartCause::bartc)
  
  evalEnv <- callingEnv
  if (propensityScoreAsCovariate && !is.null(p.score)) {
    evalEnv <- new.env(parent = callingEnv)
    pScoreArgName <- "ps"
    if (!is.null(matchedCall$data))
      while (pScoreArgName %in% names(data)) pScoreArgName <- paste0(pScoreArgName, "ps")
    evalEnv[[pScoreArgName]] <- p.score
    
    responseCall$p.score <- as.symbol(pScoreArgName)
    
    if ("samples.p.score" %in% names(formals(eval(responseCall[[1L]])))) {
      evalEnv$samples.p.score <- samples.p.score
      responseCall$samples.p.score <- quote(samples.p.score)
    }
  }
  
  if (verbose) cat("fitting response model via method '", method.rsp, "'\n", sep = "")
  
  fit.rsp <- data.rsp <- yhat.obs <- yhat.cf <- samples.est <- name.trt <- trt <- sd.obs <-
    sd.cf <- commonSup.sub <- missingRows <- NULL
  massign[fit.rsp, data.rsp, yhat.obs, yhat.cf, samples.est, name.trt, trt, sd.obs, sd.cf, commonSup.sub, missingRows] <-
    eval(responseCall, envir = evalEnv)
  
  
  result <- namedList(fit.rsp, data.rsp, fit.trt, yhat.obs, yhat.cf, samples.est, p.score, samples.p.score,
                      method.rsp, method.trt, estimand, group.by,
                      commonSup.rule, commonSup.cut,
                      name.trt, trt,
                      sd.obs, sd.cf, commonSup.sub, missingRows,
                      call = givenCall)
  result$n.chains <- if (!is.null(dim(fit.rsp$sigma))) nrow(fit.rsp$sigma) else 1L
  
  class(result) <- "bartcFit"
  result
}

