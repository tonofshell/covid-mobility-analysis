# Load and Merge Data

library(tidyverse)
library(jsonlite)
library(lubridate)
library(sf)
library(tidycensus)
library(here)
google_covid_json = read_json(here("Data", "data.json"))

nest_data = function(x) {
  list("data" = x %>% as_tibble() %>% mutate_all(as.character) )
}

google_covid_data = google_covid_json %>% lapply(nest_data) %>% as_tibble(.name_repair = "unique") %>% pivot_longer(everything()) %>% mutate(name = str_remove_all(name, "\\.")) %>% rename("id" = name) %>% unnest(value) %>% mutate_at(vars("id", "page", "change", "changecalc", "value"), as.numeric) %>% mutate(date = ymd(date)) %>% mutate(NAME = paste(county, state, sep = ", "))


source("api_keys.R")
census_api_key(census_key)

save_key = TRUE

if (save_key) {
  acs_vars_18 = load_variables(year = 2018, dataset = "acs5")
  #saveRDS(acs_vars_17, file = "Datasets/acs_vars_17.rds")
}
acs_18 = get_acs(geography = "county", year = 2018, geometry = TRUE, moe_level = 95,
                 variables = c(total_pop = "B01003_001", pop_white = "B02001_002", 
                               pop_black = "B02001_003", pop_asian = "B02001_005", 
                               pop_hispanic = "B03001_003", pop_native_amer = "B02001_004", 
                               pop_not_hisp_white = "B03002_003", pop_not_hisp_black = "B03002_004",
                               pop_not_hisp_na = "B03002_005", pop_not_hisp_asian = "B03002_006",
                               pop_not_hisp_nh_pi = "B03002_007", pop_not_hisp_other = "B03002_008",
                               pop_not_hisp_two_more = "B03002_009",
                               pop_hisp_white = "B03002_013", pop_hisp_black = "B03002_014",
                               pop_hisp_na = "B03002_015", pop_hisp_asian = "B03002_016",
                               pop_hisp_nh_pi = "B03002_017", pop_hisp_other = "B03002_018",
                               pop_hisp_two_more = "B03002_019",
                               med_age = "B01002_001", pop_female = "B01001_026", med_income = "B19326_001", 
                               pop_below_poverty ="B17001_002", pop_employed = "B27011_003", 
                               month_housing_costs = "B25105_001", pop_work_out_res_area = "B08008_003", 
                               pop_rented = "B25033_008", pop_owned = "B25008_002", 
                               pop_occupied = "B25008_001", total_hu = "B25001_001",
                               pop_under_18 = "B09002_001", total_families = "B19123_001",
                               pop_native_born = "B99051_002", pop_foreign_born = "B99051_005",
                               pop_educ_lt_hs = "B16010_002", pop_educ_hs = "B16010_015",
                               pop_educ_some_col = "B16010_028", pop_educ_mt_ba = "B16010_041", 
                               pop_geo_mobility = "B07001_001", pop_public_assist = "B09010_002", 
                               pop_bb_inet = "B28002_004", pop_any_inet = "B28002_002", 
                               pop_has_comp = "B28001_002", gini_index = "B19083_001", 
                               pop_commute_drove = "B08006_002", pop_commute_pub_trans = "B08006_008", 
                               pop_commute_bike = "B08006_014", pop_commute_walk = "B08006_015", 
                               pop_commute_none = "B08006_017", hu_with_mortgage = "B25027_002",
                               pop_nb_insured = "B27020_003", pop_nb_priv_insured = "B27020_004", 
                               pop_nb_pub_insured = "B27020_005", pop_nb_not_insured = "B27020_006", 
                               pop_fbn_insured = "B27020_009", pop_fbn_priv_insured = "B27020_010", 
                               pop_fbn_pub_insured = "B27020_011", pop_fbn_not_insured = "B27020_012", 
                               pop_fbnc_insured = "B27020_014", pop_fbnc_priv_insured = "B27020_015", 
                               pop_fbnc_pub_insured = "B27020_016", pop_fbnc_not_insured = "B27020_017")) %>%
  as_tibble() %>% 
  pivot_wider(id_cols = c(NAME, geometry, GEOID), names_from = "variable", values_from = "estimate") %>% 
  mutate(pop_insured = pop_nb_insured + pop_fbn_insured + pop_fbnc_insured, 
         pop_priv_insured = pop_nb_priv_insured + pop_fbn_priv_insured + pop_fbnc_priv_insured, 
         pop_pub_insured = pop_nb_pub_insured + pop_fbn_pub_insured + pop_fbnc_pub_insured, 
         pop_not_insured = pop_nb_not_insured + pop_fbn_not_insured + pop_fbnc_not_insured) %>% 
  select(-starts_with("pop_nb"), -starts_with("pop_fbn"), -starts_with("pop_fbnc"))


acs_18_vals = acs_18 %>% mutate(land_area = st_area(geometry) %>% units::set_units(mi^2)) %>% mutate_at(vars(-c("GEOID", "NAME", "total_pop", "med_age", "med_income", "total_hu", "total_families", "month_housing_costs", "geometry", "land_area", "gini_index", "pop_has_comp", "pop_any_inet", "pop_bb_inet")), (function(x) x / .$total_pop)) %>% mutate_at(vars(c("pop_has_comp", "pop_any_inet", "pop_bb_inet")), (function(x) x / .$total_hu)) %>% mutate(pop_density = total_pop / land_area, total_hu = total_hu / land_area, total_families = total_families / land_area) %>% rename(hu_density = total_hu, family_density = total_families)

president_data = read_csv(here("Data", "countypres_2000-2016.csv")) %>% mutate(NAME = paste0(county, " County, ", state), prop_votes = candidatevotes / totalvotes, party = party %>% ifelse(is.na(.) | . == "green", "other", .), party_year = paste0(party, "_", year)) %>% select(NAME, prop_votes, party_year) %>% group_by(NAME, party_year) %>% summarise(prop_votes = sum(prop_votes, na.rm = TRUE)) %>% pivot_wider(id_cols = "NAME", names_from = "party_year", values_from = "prop_votes")

merged_data = google_covid_data %>% left_join(acs_18_vals) %>% left_join(president_data) %>% select(-NAME, -GEOID)

saveRDS(merged_data, here("Data", "covid_demo_data.rds"))
write_csv(merged_data, here("Data", "covid_demo_data.csv"))
