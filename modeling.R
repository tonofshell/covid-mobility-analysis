# Modeling Script #

#### Setup #### 
library(cowpoke) #devtools::install_github("tonofshell/cowpoke")
library(beachball) #devtools::install_github("tonofshell/beachball")
library(FactoMineR)
library(factoextra)
library(mgcv)
library(glmnet)
library(pdp)
library(ICEbox)
library(ranger)
library(randomForest)
library(caret)
library(lubridate)
library(tidyverse)
library(tictoc)
library(here)
library(doParallel)

set.seed(60615)

setup_cl = function(seed = round(Sys.time()), num_processes = parallel::detectCores() - 1) {
  require(parallel)
  if (exists("cl")) {
    print("Stopping existing cluster")
    try(parallel::stopCluster(cl))
  }
  assign("cl", parallel::makeCluster(num_processes, outfile = "out.txt"), envir = globalenv())
  RNGkind("L'Ecuyer-CMRG")
  print(paste("Using", as.numeric(seed), "as parallel RNG seed"))
  clusterSetRNGStream(cl, seed)
}
setup_cl(60615, 16)
registerDoParallel(cl)

merged_data = readRDS(here("Data", "covid_demo_data.rds")) %>% mutate_at(vars("family_density", "hu_density", "land_area", "pop_density"), as.numeric) %>% mutate_if(is.character, factor) %>% mutate(days_passed = as.numeric(days_passed)) %>% mutate(dem_rep_2000 = democrat_2000 - republican_2000, dem_rep_2004 = democrat_2004 - republican_2004, dem_rep_2008 = democrat_2008 - republican_2008, dem_rep_2012 = democrat_2012 - republican_2012, dem_rep_2016 = democrat_2016 - republican_2016) %>% select(-starts_with("democrat"), -starts_with("republican"), -pop_native_born) %>% left_join({.} %>% group_by(date, category) %>% summarise(value_mean = mean(value))) %>% mutate(value = value - value_mean, value_mean = NULL)

#%>% filter(date > ymd("2020-03-26")) %>% group_by(state, county, category) %>% summarise_all(mean) %>% select(-days_passed) %>% ungroup()

num_var_names = merged_data %>% summarise_all(is.numeric) %>% pivot_longer(everything()) %>% filter(value) %>% .$name

#### Model Prep ####
calc_accuracy = function(test_data_set, predict_vals, y_var, rmse = NULL) {
  if (is.null(rmse)) {
    if (is.numeric(test_data_set[[y_var]])) {
      rmse = TRUE
    } else {
      rmse = FALSE
    }
  }
  if (rmse) {
    print("Calculating RMSE")
    rmse = predict_vals %>% na.omit() %>% as.numeric() %>% (function(x) x - test_data_set[[y_var]]) %>% (function(x) x^2) %>% mean() %>% sqrt()
    names(rmse) = "RMSE"
    return(rmse)
  }
  print("Calculating Accuracy")
  acc = as.logical((predict_vals == test_data_set[[y_var]])) %>% na.omit() %>% as.numeric() %>% sum() %>% (function(x) x / length(test_data_set[[y_var]]))
  names(acc) = "Accuracy"
  return(acc)
}

ice_plot = function(variable_name, mod, training_data, y_var, ...) {
  library(ICEbox)
  library(tidyverse)
  library(ranger)
  ice_obj = ice(mod, as.data.frame(training_data) %>% select(-y_var), as.data.frame(training_data) %>% select(y_var) %>% unlist(), predictor = variable_name, predictfcn = function(object, newdata){return(predict(object, newdata)$predictions)}, ...)
  return(ice_obj)
}

pdp_plot = function(v_name, mod, train_dat) {
  return(pdp::partial(mod, train = train_dat, pred.var = v_name, type = "classification", plot = TRUE, rug = TRUE, plot.engine = "ggplot2"))
}

split_data = function(data_set, y_var, split_prop = 0.75) {
  indices = createDataPartition(data_set[[y_var]], p = split_prop)[[1]]
  output = list()
  output$y_var = y_var
  output$indices = indices
  output$training = data_set %>% .[indices,]
  output$testing = data_set %>% .[-indices,]
  output
}

rf_workflow = function(part_data_obj) {
  output = list()
  output$formula = as.formula(paste(part_data_obj$y_var, "~", "."))
  output$model = part_data_obj$training %>% {ranger(output$formula, .)}
  output$imp_model = part_data_obj$training %>% {ranger(output$formula, ., importance = "impurity_corrected")}
  output$test_preds = predict(output$model, part_data_obj$testing)$predictions
  output$performance = print(part_data_obj$testing %>% calc_accuracy(output$test_preds, part_data_obj$y_var, rmse = TRUE))
  output
}

imp_table = function(workflow_obj, data_obj) {
  workflow_obj$imp_vals = importance_pvalues(workflow_obj$imp_model, method = "altmann", formula = workflow_obj$formula, data = data_obj$training, num.permutations = 50) %>% as_tibble(rownames = "variable") %>% arrange(-importance)
  workflow_obj
}

ice_objs = function(workflow_obj, data_obj, n_vars = 12, ...) {
  workflow_obj$ice_objs = workflow_obj$imp_vals %>% filter(importance > 0, variable %in% num_var_names) %>% top_n(n_vars, importance) %>% .$variable %>% lapply(ice_plot, workflow_obj$model, data_obj$training, data_obj$y_var, ...)
  workflow_obj
}

save_results = function(workflow_obj) {
  out = list()
  if (!is.null(workflow_obj$performance)) {
    out$performance = workflow_obj$performance
  }
  if (!is.null(workflow_obj$imp_vals)) {
    out$imp_vals = workflow_obj$imp_vals
  }
  if (!is.null(workflow_obj$ice_objs)) {
    out$ice_objs = workflow_obj$ice_objs
  }
  name = deparse(substitute(workflow_obj)) %>% str_remove("_mod")
  saveRDS(out, here("Results", paste0(name, ".rds")))
}

ice_frac = 0.05

#### Home Models ####

home_sampled = merged_data %>% select(-c(id, page, change, changecalc, geometry, date)) %>% filter(category == "residential") %>% select(-category) %>% na.omit() %>% split_data("value")

#### Principal Component Analysis ####
home_pca = home_sampled$training %>% mutate_all(as.numeric) %>% PCA(graph = FALSE)

home_pca_biplot = fviz_pca_var(home_pca, repel = TRUE) + theme_day(base_family = "Pragati Narrow", base_size = 18)
saveRDS(home_pca_biplot, here("Results", "home_pca_biplot.rds"))

#### Random Forest ####

rf_home_mod = home_sampled %>% rf_workflow()
save_results(rf_home_mod)

#### Stats ####
rf_home_mod = imp_table(rf_home_mod, home_sampled)
save_results(rf_home_mod)

#### Visualizations ####
rf_home_mod = ice_objs(rf_home_mod, home_sampled, frac_to_build = ice_frac)
save_results(rf_home_mod)

# par(mfrow = c(3,4))
# for (ice_obj in rf_home_mod$ice_objs) {
#   plot(ice_obj)
# }

#### Work Models ####

work_sampled = merged_data %>% select(-c(id, page, change, changecalc, geometry, date)) %>% filter(category == "workplace") %>% select(-category) %>% na.omit() %>% split_data("value")

#### Principal Component Analysis ####
work_pca = work_sampled$training %>% mutate_all(as.numeric) %>% PCA(graph = FALSE)

work_pca_biplot = fviz_pca_var(work_pca, repel = TRUE) + theme_day(base_family = "Pragati Narrow", base_size = 18)
saveRDS(work_pca_biplot, here("Results", "work_pca_biplot.rds"))

#### Random Forest ####

rf_work_mod = work_sampled %>% rf_workflow()
save_results(rf_work_mod)

#### Stats ####
rf_work_mod = imp_table(rf_work_mod, work_sampled)
save_results(rf_work_mod)

#### Visualizations ####
rf_work_mod = ice_objs(rf_work_mod, work_sampled, frac_to_build = ice_frac)
save_results(rf_work_mod)

# par(mfrow = c(3,4))
# for (ice_obj in rf_work_mod$ice_objs) {
#   plot(ice_obj)
# }

#### Transit Models ####

transit_sampled = merged_data %>% select(-c(id, page, change, changecalc, geometry, date)) %>% filter(category == "transitstations") %>% select(-category) %>% na.omit() %>% split_data("value")

#### Principal Component Analysis ####
transit_pca = transit_sampled$training %>% mutate_all(as.numeric) %>% PCA(graph = FALSE)

transit_pca_biplot = fviz_pca_var(transit_pca, repel = TRUE) + theme_day(base_family = "Pragati Narrow", base_size = 18)
saveRDS(transit_pca_biplot, here("Results", "transit_pca_biplot.rds"))

#### Random Forest ####

rf_transit_mod = transit_sampled %>% rf_workflow()
save_results(rf_transit_mod)

#### Stats ####
rf_transit_mod = imp_table(rf_transit_mod, transit_sampled)
save_results(rf_transit_mod)

#### Visualizations ####
rf_transit_mod = ice_objs(rf_transit_mod, transit_sampled, frac_to_build = ice_frac)
save_results(rf_transit_mod)

# par(mfrow = c(3,4))
# for (ice_obj in rf_transit_mod$ice_objs) {
#   plot(ice_obj)
# }

#### Retail Models ####

retail_sampled = merged_data %>% select(-c(id, page, change, changecalc, geometry, date)) %>% filter(str_detect(category, "retail")) %>% select(-category) %>% na.omit() %>% split_data("value")

#### Principal Component Analysis ####
retail_pca = retail_sampled$training %>% mutate_all(as.numeric) %>% PCA(graph = FALSE)

retail_pca_biplot = fviz_pca_var(retail_pca, repel = TRUE) + theme_day(base_family = "Pragati Narrow", base_size = 18)
saveRDS(retail_pca_biplot, here("Results", "retail_pca_biplot.rds"))

#### Random Forest ####

rf_retail_mod = retail_sampled %>% rf_workflow()
save_results(rf_retail_mod)

#### Stats ####
rf_retail_mod = imp_table(rf_retail_mod, retail_sampled)
save_results(rf_retail_mod)

#### Visualizations ####
rf_retail_mod = ice_objs(rf_retail_mod, retail_sampled, frac_to_build = ice_frac)
save_results(rf_retail_mod)

# par(mfrow = c(3,4))
# for (ice_obj in rf_retail_mod$ice_objs) {
#   plot(ice_obj)
# }
