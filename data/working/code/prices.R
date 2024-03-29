# Here stands the script to import and wrangle price data
# Import PCE-adjusted prices
# Calculate inflation-adjustment
# Write to database





### First, build a library
options(scipen=999)

library(dplyr)
library(tidyr)
library(lubridate)
library(stringr)

library(readxl)
library(readr)




# Import

raw_prices <- read_csv(file = "./raw/raw_prices.csv")




# AK Consumer Price Index
# https://fred.stlouisfed.org/series/CUUSA427SEHF01
# this data came with 2 CPIs per year (January, July)
# wanted 1 CPI per year, so I averaged the two

ak_cpi <- read.csv("./raw/CUUSA427SA0.csv") %>%
  mutate(date = ymd(DATE)) %>%
  mutate(`AK CPI` = CUUSA427SA0) %>%
  filter(month(date) == 1) %>%
  mutate(Year = year(date)) %>%
  select(Year, `AK CPI`)



## Build dataframe of nominal prices

prices <- raw_prices %>%
  
  # add AK Consumer Price Index data
  left_join(., ak_cpi, by = join_by(Year == Year)) %>%
  
  # calculate nominal prices
  mutate(`Residential Price kWh (nominal dollars)` = 
           (`Residential $/kWh`)*100, 
            .after = `Residential Sales MWh`) %>%
  mutate(`Commercial Price kWh (nominal dollars)` = 
          (`Commercial $/kWh`)*100, 
            .after = `Commercial Sales MWh`) %>%
  mutate(`Other Price kWh (nominal dollars)` = 
          (`Other $/kWh`)*100, 
            .after = `Other Sales MWh`) %>%
  select(c("Year",
           "AEA Sales Reporting ID",
           "Residential Price kWh (nominal dollars)",
           "Residential Customers",
           "Residential Sales MWh",
           "Commercial Price kWh (nominal dollars)",
           "Commercial Customers",
           "Commercial Sales MWh",
           "Other Price kWh (nominal dollars)",
           "Other Customers",
           "Other Sales MWh",
           "Total Customers",
           "AK CPI"))




# load PCE-adjusted Residential Prices
# load pce data
pce_sales <- read_csv("./raw/prices_pce.csv") %>%
  mutate("Residential Price kWh (nominal dollars)" = (`Residential Rate after PCE ($/kWh)`)*100) %>% 
  select(-c("PCE Community\n(Y/N)")) 
  

sales_minus_residential <- prices %>%
  mutate("Residential Price kWh (nominal dollars)" = NULL) %>%
  select(c("Year",
           "AEA Sales Reporting ID",
           # "Residential Price kWh (nominal dollars)",
           "Residential Customers",
           "Residential Sales MWh",
           "Commercial Price kWh (nominal dollars)",
           "Commercial Customers",
           "Commercial Sales MWh",
           "Other Price kWh (nominal dollars)",
           "Other Customers",
           "Other Sales MWh",
           "Total Customers",
           "AK CPI"))


# add `Commercial $/kWh` and `Other $/kWh` to PCE communities
pce_sales_plus_commercial_other <- left_join(pce_sales, 
                                             sales_minus_residential, 
                                             join_by(`Year`, `AEA Sales Reporting ID`)) %>%
                                  select(c("Year",
                                           "AEA Sales Reporting ID",
                                           "Residential Price kWh (nominal dollars)",
                                           "Residential Customers",
                                           "Residential Sales MWh",
                                           "Commercial Price kWh (nominal dollars)",
                                           "Commercial Customers",
                                           "Commercial Sales MWh",
                                           "Other Price kWh (nominal dollars)",
                                           "Other Customers",
                                           "Other Sales MWh",
                                           "Total Customers",
                                           "AK CPI"))


# burn PCE communities from raw_sales in order to set up for r_bind() next
non_pce_prices <- anti_join(prices, pce_sales, by = join_by(`AEA Sales Reporting ID`))


prices_pce <- rbind(non_pce_prices, pce_sales_plus_commercial_other)




  

# calculate inflation-adjustment 
# join community data
# add ACEP regions

prices_pce_inflation <- prices_pce %>%
  # calculate inflation adjusted prices
  mutate(`Residential Price kWh (2021 dollars)` = 
           (`Residential Price kWh (nominal dollars)`*232.679/`AK CPI`), 
            .after = `Residential Price kWh (nominal dollars)`) %>%
  mutate(`Commercial Price kWh (2021 dollars)` = 
           (`Commercial Price kWh (nominal dollars)`*232.679/`AK CPI`), 
            .after = `Commercial Price kWh (nominal dollars)`) %>%
  mutate(`Other Price kWh (2021 dollars)` = 
           (`Other Price kWh (nominal dollars)`*232.679/`AK CPI`), 
            .after = `Other Price kWh (nominal dollars)`) %>%
  
  # finally, select statement to narrow things down
  select(c("Year",
           "AEA Sales Reporting ID",
           "Residential Price kWh (2021 dollars)",
           "Residential Customers",
           "Residential Sales MWh",
           "Commercial Price kWh (2021 dollars)",
           "Commercial Customers",
           "Commercial Sales MWh",
           "Other Price kWh (2021 dollars)",
           "Other Customers",
           "Other Sales MWh",
           "Total Customers",
           "AK CPI"
           ))



# Now that cleaning is done, add community crosswalk data
crosswalk2020 <- read_csv("./raw/crosswalk2020.csv")

# need to figure out SR-195 (Metlakatla, Southeast), SR-199 (Seward, Railbelt), SR-9 (Paxson, Chugach)
crosswalk2020 <- rbind(crosswalk2020, c("SR-195", NA, NA, NA, "Metlakatla", NA, "Southeast"))
crosswalk2020 <- rbind(crosswalk2020, c("SR-199", NA, NA, NA, "Seward", NA, "Railbelt"))
crosswalk2020 <- rbind(crosswalk2020, c("SR-9", NA, NA, NA, "Paxson", NA, "Copper River/Chugach"))

# join inflation-adjusted plus PCE prices AND regional data
final <- left_join(prices_pce_inflation, crosswalk2020, join_by(`AEA Sales Reporting ID`))


# Add ACEP region to revenue data
# rural remote, coastal, railbelt
unique(final$`AEA Energy Region`)

final$`ACEP Energy Region` <- "error"

final$`ACEP Energy Region` <- if_else(final$`AEA Energy Region` == c("Railbelt"), 
                           "Railbelt", final$`ACEP Energy Region`)

final$`ACEP Energy Region` <- if_else(final$`AEA Energy Region` %in% c("Southeast", "Kodiak", "Copper River/Chugach"), 
                           "Coastal", final$`ACEP Energy Region`)

final$`ACEP Energy Region` <- if_else(final$`AEA Energy Region` %in% c("North Slope", 
                                                        "Bering Straits", 
                                                        "Yukon-Koyukuk/Upper Tanana",
                                                        "Lower Yukon-Kuskokwim", 
                                                        "Bristol Bay",
                                                        "Aleutians",
                                                        "Northwest Arctic"
                                                        ),
                           "Rural Remote", final$`ACEP Energy Region`)



# test, this should return 0 records
sub <- subset(final, `ACEP Energy Region` == "error")




# reorder column names

final_final <- final %>%
  select(c("Year",
           "AEA Sales Reporting ID",
           "PCE ID", 
           "RCA CPCN",
           "Utility Name",
           "Reporting Name",
           "Intertie Name",
           "AEA Energy Region",
           "ACEP Energy Region",
           "Residential Price kWh (2021 dollars)",
           "Residential Customers",
           "Residential Sales MWh",
           "Commercial Price kWh (2021 dollars)",
           "Commercial Customers",
           "Commercial Sales MWh",
           "Other Price kWh (2021 dollars)",
           "Other Customers",
           "Other Sales MWh",
           "Total Customers",
           "AK CPI"))




# convert column names to lower case, replace spaces with underscores
colnames(final_final) <- gsub(" ", "_", str_to_lower(colnames(final_final)))

# delete ( ) from column names
colnames(final_final) <- gsub("(", "", colnames(final_final), fixed=T)
colnames(final_final) <- gsub(")", "", colnames(final_final), fixed=T)






# check if table exists
dbExistsTable(con, "prices")

# delete contents
# dbExecute(con, "DELETE FROM prices")

# write tables
dbWriteTable(con, "prices", final_final, overwrite=T)

# clean up
rm(ak_cpi, 
   crosswalk2020, 
   final,
   final_final,
   non_pce_prices, 
   pce_sales, 
   pce_sales_plus_commercial_other, 
   prices,
   prices_pce,
   prices_pce_inflation,
   raw_prices,
   sales_minus_residential,
   sub
)

## test load from database
prices <- dbReadTable(con, "prices")











