


# apply a classification impact model
# replace level with stored code
.customCode <- function(col,args, doCollar) {
  col <- .preProcCat(col,args$levRestriction)
  unhandledNovel <- !(col %in% names(args$conditionalScore))
  keys <- col
  pred <- numeric(length(col))
  if(length(args$conditionalScore)>0) {
    keys[unhandledNovel] <- names(args$conditionalScore)[[1]]  # just to prevent bad lookups
    pred <- as.numeric(args$conditionalScore[keys]) 
  }
  pred[unhandledNovel] <- args$missingValueCode
  pred
}

# Make a categorical input custom coder.
#
# @para customCode code name
# @param coder user supplied variable re-coder (see vignette for type signature)
# @param codeSeq argments to custom coder
# @param v variable name
# @param vcolin data column, character
# @param zoY outcome column as numeric
# @param zC if classification outcome column as character
# @param zTarge if classification target class
# @param weights per-row weights
makeCustomCoder <- function(customCode, coder, codeSeq,
                            v,vcolin,zoY,zC,zTarget,weights,catScaling)  {
  levRestriction <- NULL
  vcol <- .preProcCat(vcolin,levRestriction)
  if(is.null(weights)) {
    weights <- rep(1.0, length(vcol))
  }
  extraModelDegrees <- max(0,length(unique(vcolin))-1)
  scores <- NULL
  tryCatch(
    if(is.null(zC)) {
      scores <- coder(v,vcol,zoY,weights)
    } else {
      scores <- coder(v,vcol,zC==zTarget,weights)
    },
    error = function(e) { warning(e) }
  )
  if(is.null(scores) || (!is.numeric(scores)) || (length(scores)!=length(vcol))) {
    scores <- rep(0.0, length(vcol))
  } else {
    if('center' %in% codeSeq) {
      # shift scores to be mean zero with respect to weights
      scores <- scores -  sum(scores*weights)/sum(weights)
    }
  }
  missingValueCode <- sum(scores * weights)/sum(weights)
  d <- data.frame(x = vcol,
                  pred = scores)
  # TODO: weighted version
  agg <- aggregate(pred~x, data=d, mean)
  conditionalScore <- as.list(as.numeric(agg$pred))
  names(conditionalScore) <- as.character(agg$x)
  conditionalScore <- conditionalScore[names(conditionalScore)!='zap']  # don't let zap group code
  newVarName <- make.names(paste(v, customCode, sep='_'))
  treatment <- list(origvar=v,
                    newvars=newVarName,
                    f=.customCode,
                    args=list(conditionalScore=conditionalScore,
                              levRestriction=levRestriction,
                              missingValueCode=missingValueCode),
                    treatmentName=paste('Custom Code:', customCode),
                    treatmentCode=customCode,
                    needsSplit=TRUE,
                    extraModelDegrees=extraModelDegrees)
  pred <- treatment$f(vcolin, treatment$args, FALSE)
  if(!.has.range.cn(pred)) {
    return(NULL)
  }
  class(treatment) <- 'vtreatment'
  if(!catScaling) {
    treatment$scales <- linScore(newVarName,pred,as.numeric(zC==zTarget),weights)
  } else {
    treatment$scales <- catScore(newVarName,pred,zC,zTarget,weights)
  }
  treatment
}





# apply linear interpolation on known numeric levels
.customCodeNum <- function(col, args, doCollar) {
  treated <- as.numeric(col)
  naposns <- .is.bad(treated)
  treated[naposns] <- args$missingValueCode
  if(sum(!naposns)>0) {
    xg <- pmax(min(args$predXs), pmin(max(args$predXs), col[!naposns]))
    if(doCollar) {
      xg <- pmax(min(args$cuts), pmin(max(args$cuts), xg))
    }
    treated[!naposns]  <- stats::approx(x=args$predXs, y=args$predYs, 
                                        xout= xg)$y
  }
  fails <- .is.bad(treated)
  if(any(fails)) {
    treated[fails] <- args$missingValueCode
  }
  treated
}

# Make a numeric input custom coder.
#
# @para customCode code name
# @param coder user supplied variable re-coder (see vignette for type signature)
# @param codeSeq argments to custom coder
# @param v variable name
# @param vcolin data column, numeric
# @param zoY outcome column as numeric
# @param zC if classification outcome column as character
# @param zTarge if classification target class
# @param weights per-row weights
makeCustomCoderNum <- function(customCode, coder, codeSeq,
                            v,vcolin,zoY,zC,zTarget,weights,catScaling)  {
  xcol <- as.numeric(vcolin)
  napositions <- .is.bad(xcol)
  nna <- sum(napositions)
  if(nna>=length(xcol)) {
    return(c())
  }
  if(is.null(weights)) {
    weights <- rep(1.0, length(vcolin))
  }
  xNotNA <- xcol[!napositions]
  yNotNa <- zoY[!napositions]
  wNotNa <- weights[!napositions]
  if(max(xcol)<=min(xcol)) {
    return(c())
  }
  cuts <- c(min(xNotNA), max(xNotNA))
  if(sum(napositions)>0) {
    missingValueCode <- .wmean(zoY[napositions], weights[napositions])
  } else {
    missingValueCode <- .wmean(yNotNa, wNotNa)
  }
  extraModelDegrees <- max(0,length(unique(xNotNA)))
  
  scores <- NULL
  tryCatch(
    if(is.null(zC)) {
      scores <- coder(v, xNotNA, zoY[!napositions], wNotNa)
    } else {
      scores <- coder(v, xNotNA,
                      (zC[!napositions])==zTarget, wNotNa)
    },
    error = function(e) { warning(e) }
  )
  if(is.null(scores) || (!is.numeric(scores)) || (length(scores)!=length(xcol))) {
    scores <- rep(0.0, length(xcol))
  } else {
    if('center' %in% codeSeq) {
      # shift scores to be mean zero with respect to weights
      scores <- scores -  sum(scores*wNotNa)/sum(wNotNa)
    }
  }
  d <- data.frame(x = xcol,
                  pred = scores)
  # TODO: weighted version
  agg <- aggregate(pred~x, data=d, mean)
  predXs <- agg$x
  if(length(predXs)<=1) {
    return(NULL)
  }
  predYs <- as.numeric(agg$pred)
  ord <- order(agg$x)
  predXs <- predXs[ord]
  predYs <- predYs[ord]
  newVarName <- make.names(paste(v, customCode, sep='_'))
  treatment <- list(origvar=v,
                    newvars=newVarName,
                    f=.customCodeNum,
                    args=list(predXs=predXs,
                              predYs=predYs,
                              cuts=cuts,
                              missingValueCode=missingValueCode),
                    treatmentName=paste('Custom Code:', customCode),
                    treatmentCode=customCode,
                    needsSplit=TRUE,
                    extraModelDegrees=extraModelDegrees)
  pred <- treatment$f(vcolin, treatment$args, FALSE)
  if(!.has.range.cn(pred)) {
    return(NULL)
  }
  class(treatment) <- 'vtreatment'
  if(!catScaling) {
    treatment$scales <- linScore(newVarName,pred,as.numeric(zC==zTarget),weights)
  } else {
    treatment$scales <- catScore(newVarName,pred,zC,zTarget,weights)
  }
  treatment
}

