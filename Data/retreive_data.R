# Load and Merge Data

library(tidyverse)
library(jsonlite)
library(lubridate)
library(here)
google_covid_json = read_json(here("Data", "data.json"))

nest_data = function(x) {
  list("data" = x %>% as_tibble() %>% mutate_all(as.character) )
}

google_covid_data = google_covid_json %>% lapply(nest_data) %>% as_tibble(.name_repair = "unique") %>% pivot_longer(everything()) %>% mutate(name = str_remove_all(name, "\\.")) %>% rename("id" = name) %>% unnest(value) %>% mutate_at(vars("id", "page", "change", "changecalc", "value"), as.numeric) %>% mutate(date = ymd(date))
