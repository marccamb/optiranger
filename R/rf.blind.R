#' Non-random cross validation for random forest
#'
#' Grows multiple random forests with non-random cross validation: the algorithm is trained on
#' a specific part of the dataset, and predictions are done on another part of the dataset.
#'
#' @param tab An abundance or presence absence table containing samples in columns and OTUs/ASV in rows.
#' @param treat A boolean vector containing the class identity of each sample, i.e. the treatment to predict.
#' This means that you should pick a class as a reference for the calculation of precision and sensitivity.
#' @param train.id A charecter sting to be searched in samples names that will be used for training.
#' Can be a regular expression. Can alernatively be a boolean vector saying wether or not each sample
#' is part of the training dataset(TRUE for training samples, FALSE for testing samples), or a character
#' vector containing the training sample names.
#' @param mtry The mtry parameter to be passed to the \code{ranger} function.
#' See \code{ranger} documentation for details.
#' @param n.tree The number of tree to grow. The default is \code{500}.
#' @param n.forest The number of forests to grow. The default is \code{10}.
#' @param seed A number to set the seed before growing the forest. Only meaningful
#' if n.forest == 1. The default is \code{NULL}.
#'
#'@return A list object containing:
#' \itemize{
#'   \item a summary table with the number of true positives (TP), true negatives (TN), false positives (FP) and false negatives (FN)
#' the error rate, the sensistivity \eqn{TP/(TP + FN)}, and the precision \eqn{TP/(TP + FP)}
#'   \item The confusion matrix
#'   \item \code{n.forest} tables containing Gini index for each variable in each of the \code{n.forest} grown forests.
#'   This index gives the variable importance for classification.
#' }
#'
#' @import ranger
#' @export rf.blind

# 2020-02-27
# Marine C. Cambon

rf.blind <- function(tab, treat,
                     train.id,
                     mtry = NULL,
                     n.tree = 500,
                     n.forest = 10,
                     seed=NULL) {
  if(class(treat) != "logical") stop("treat is not a boolean vector")
  treat <- ifelse(treat, "positive", "negative")
  treat <- as.factor(treat)

  if(length(train.id)==1) {
    train.idx <- grep(train.id, colnames(tab))
  } else {
    if(class(train.id) == "logical") {
      train.idx <- which(train.id)
    } else {
      train.idx <- which(colnames(tab) %in% train.id)
    }
  }
  if(length(train.idx)==1) warning("The training dataset only contains 1 sample")
  if(length(train.idx)==0) stop("train.id does not match sample names")

  tab <- data.frame("treat" = treat, t(tab))
  train <- tab[train.idx, ]
  test <- tab[-train.idx, ]
  res <- data.frame()
  importance <- list()
  message("Growing ", n.forest, " forests...")
  for (i in 1:n.forest) {
    if(n.forest == 1) set.seed(seed)
    rg <- ranger::ranger(treat ~ ., data = train,
                      num.trees = n.tree,
                      mtry = mtry,
                      importance = "impurity")

    pred <- stats::predict(rg, data = test)
    tmp <- data.frame(table(pred$predictions, test$treat))
    TN <- tmp[tmp$Var1=="negative" & tmp$Var2=="negative","Freq"]
    TP <- tmp[tmp$Var1=="positive" & tmp$Var2=="positive","Freq"]
    FN <- tmp[tmp$Var1=="positive" & tmp$Var2=="negative","Freq"]
    FP <- tmp[tmp$Var1=="negative" & tmp$Var2=="positive","Freq"]
    error <- sum(test$treat != pred$predictions)/nrow(test)
    sensitivity <- TP/(TP+FN)
    precision <- TP/(TP+FP)
    res <- rbind(res, c(TP, TN, FP, FN, error, sensitivity, precision))
    importance[[i]] <- rg$variable.importance
  }
  colnames(res) <- c("TN","TP","FN","FP","error","sensitivity","precision")
  message("Done!")
  summary <- rbind(apply(res,2,mean),apply(res,2,sd))
  rownames(summary) <- c("mean", "sd")

  res_tot <- list(summary, res, importance)
  names(res_tot) <- c("summary", "confusion", "importance")
  return(res_tot)
}
