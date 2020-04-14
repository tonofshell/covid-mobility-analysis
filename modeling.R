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

merged_data = readRDS(here("Data", "covid_demo_data.rds")) %>% mutate_at(vars("family_density", "hu_density", "land_area", "pop_density"), as.numeric) %>% mutate_if(is.character, factor) %>% mutate(days_passed = as.numeric(days_passed)) %>% mutate(dem_rep_2000 = democrat_2000 - republican_2000, dem_rep_2004 = democrat_2004 - republican_2004, dem_rep_2008 = democrat_2008 - republican_2008, dem_rep_2012 = democrat_2012 - republican_2012, dem_rep_2016 = democrat_2016 - republican_2016) %>% select(-starts_with("democrat"), -starts_with("republican"), -pop_native_born)

num_var_names = merged_data %>% summarise_all(is.numeric) %>% pivot_longer(everything()) %>% filter(value) %>% .$name

#### Model Prep ####
calc_accuracy = function(test_data_set, predict_vals, y_var, mse = FALSE) {
  if (mse) {
    print("Calculating RMSE")
    return(predict_vals %>% na.omit() %>% as.numeric() %>% (function(x) x - test_data_set[[y_var]]) %>% (function(x) x^2) %>% mean() %>% sqrt())
  }
  print("Calculating Accuracy")
  return(as.logical((predict_vals == test_data_set[[y_var]])) %>% na.omit() %>% as.numeric() %>% sum() %>% (function(x) x / length(test_data_set[[y_var]])))
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


#### Home Model ####

home_sampled = merged_data %>% select(-date) %>% filter(category == "residential") %>% na.omit()
home_indices = createDataPartition(home_sampled$value, 0.75)[[1]]
home_training = home_sampled  %>% select(-c(id, category, page, change, changecalc, geometry)) %>% .[home_indices, ]
home_testing = home_sampled %>% select(-c(id, category, page, change, changecalc, geometry)) %>% .[-home_indices, ]

#### Principal Component Analysis ####
home_pca = home_training %>% na.omit() %>% mutate_all(as.numeric) %>% PCA(graph = FALSE)

home_pca_biplot = fviz_pca_var(home_pca, repel = TRUE) + theme_day(base_family = "Pragati Narrow", base_size = 18)
saveRDS(home_pca_biplot, here("Results", "home_pca_biplot.rds"))

#### Random Forest ####
rf_home = home_training %>% ranger(value ~ ., .)
rf_home_imp = home_training %>% ranger(value ~ ., ., importance = "impurity_corrected")

#### Stats ####
home_predictions = predict(rf_home, home_training)$predictions
home_testing %>% calc_accuracy(home_predictions, "value", mse = TRUE)

rf_home_imp_values = importance_pvalues(rf_home_imp, method = "altmann", formula = value ~ ., data = home_training, num.permutations = 50) %>% as_tibble(rownames = "variable") %>% arrange(-importance)

saveRDS(rf_home_imp_values, here("Results", "rf_home_imp_values.rds"))

# rf_all_imp_values %>% kable() %>% kable_styling(c("condensed", "striped", "responsive"))

#### Visualizations ####
rf_home_ice_objs = rf_home_imp_values %>% filter(importance > 0, variable %in% num_var_names) %>% top_n(12, importance) %>% .$variable %>% lapply(ice_plot, rf_home, home_training, "value", frac_to_build = 0.05)

saveRDS(rf_home_ice_objs, here("Results", "rf_home_ice_objs.rds"))

par(mfrow = c(2,3))
for (ice_obj in rf_home_ice_objs) {
  plot(ice_obj)
}

# rf_all_pdp_plots = rf_all_imp_values %>% top_n(12, importance) %>% .$variable %>% lapply(pdp_plot, rf_all_prob, na.omit(all_training))
# saveRDS(rf_all_pdp_plots, here("Results", "rf_all_pdp_plots.rds"))
# do.call(grid.arrange,  rf_all_pdp_plots)