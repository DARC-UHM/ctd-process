# options(error=traceback)
# install.packages("tidyverse")
suppressPackageStartupMessages(library(tidyverse))
library(readr)
library(dplyr)
library(purrr)
library(cli)

### Added: Thu Feb 19, 2026 for "Little Hercules" to skip the Oxygen sensor
#  Rscript NA.R "$cruise_number" "$dive_number" "$dive_start_date" "$onbottom_time" "$tmp_output_destination" "$output_destination_path" "$skip_oxygen_calculation"

#  Access the arguments
args <- commandArgs(trailingOnly = TRUE)
cruise_number <- args[1]
dive_number <- args[2]
dive_start_date <- args[3]
tmp_input_files <- args[4]
output_destination_path <- args[5]
skip_oxygen_calculation <- tolower(args[6]) == "true" #true or false


calculate_oxygen_microMolar <- function(o2, sal, temp, depth) {
  # Pressure Compensation Coefficients
  b0 <- -0.00624097
  b1 <- -0.00693498
  b2 <- -0.00690358
  b3 <- -0.00429155
  c0 <- -0.00000031168

  t_s <- log((298.15 - temp) / (273.15 + temp))

  sal_comp_fact <- exp(sal * (b0 + b1 * t_s + b2 * t_s^2 + b3 * t_s^3) + c0 * sal^2)

  o2c <- (o2 * sal_comp_fact)
  mMo2 <- o2c * (1 + (0.032 * depth) / 1000)
  return (mMo2)
}
calculate_oxygen_mlperliter <- function(mMo2){
  return (mMo2/44.659)
}
calculate_oxygen_mgperliter <- function(mMo2){
  return ((mMo2 * 32) / 1000)
}

format_time <- function(timestamp) {
  return (format(as.POSIXct(timestamp, format = "%Y-%m-%dT%H:%M:%S"), format = "%Y%m%dT%H%M%SZ"))
}

read_ctd_nav_data <- function() {
  ctd_folder_path <- paste0(tmp_input_files, "/ctd_nav")
  ctd_file <- paste0(ctd_folder_path,"/",dive_number,".CTD.NAV.tsv")
  column_names <- c("Timestamp", "Latitude", "Longitude", "Depth", "Temperature", "01", "02", "Salinity", "03")

  # # Read and combine the files into a tibble
  ctd_data <- read_tsv(ctd_file,
                       col_names = column_names,
                       col_select = c("Timestamp", "Latitude", "Longitude", "Depth", "Temperature", "Salinity"),
                       col_types = cols(
                         Timestamp = col_datetime(format = "%Y-%m-%dT%H:%M:%S"),
                         Latitude = col_double(),
                         Longitude = col_double(),
                         Depth = col_double(),
                         Temperature = col_double(),
                         Salinity = col_double()
                       ),
                       show_col_types = FALSE)

  # Apply the function to the column using mutate()
  selected_ctd_data <- ctd_data %>% mutate(Timestamp = format_time(Timestamp)) %>% arrange(Timestamp)
  return(selected_ctd_data)
}

read_o2s_nav_data <- function() {
  o2s_folder_path <- paste0(tmp_input_files,"/o2s_nav")
  o2s_file <- paste0(o2s_folder_path,"/",dive_number,".O2S.NAV.tsv")
  column_names <- c("Timestamp", "04", "05", "06", "Oxygen", "07", "08")

  o2s_data <- read_tsv(o2s_file,
                       col_names = column_names,
                       col_select=c("Timestamp", "Oxygen"),
                       col_types=cols(Oxygen = col_double(),
                                      Timestamp = col_datetime(format = "%Y-%m-%dT%H:%M:%S")),
                       show_col_types = FALSE)

  # Apply the function to the column using mutate()
  selected_ctd_data <- o2s_data %>% mutate(Timestamp = format_time(Timestamp)) %>% arrange(Timestamp)
  return(selected_ctd_data)
}

read_dat_data <- function() {
  dat_folder_path <- paste0(tmp_input_files,"/dat")
  dat_files <- list.files(dat_folder_path, pattern=paste0(dive_number,".DAT"), full.names=TRUE)

  # Read and combine the files into a tibble
  # 2019/08/30 06:45:17.914 0.000
  column_names <- c("Date", "Time", "Alt")
  dat_data <- read_delim(dat_files,
                         col_names=column_names,
                         delim = " ",
                         col_types = cols(
                           Date = col_date(format = "%Y/%m/%d"),
                           Time = col_time(format = "%H:%M:%OS"),
                           Alt = col_double()
                         ),
                         show_col_types = FALSE)

  # Apply the function to the column using mutate()
  selected_dat_data <- dat_data %>%
    mutate(Timestamp = as.POSIXct(paste(Date, Time), format = "%Y-%m-%d %H:%M:%OS")) %>%
    mutate(Timestamp = format(Timestamp, format = "%Y%m%dT%H%M%SZ")) %>%
    arrange(Timestamp)

  return(selected_dat_data)
}

invisible(ctd_data <- read_ctd_nav_data())
invisible(dat_data <- read_dat_data())

if(skip_oxygen_calculation){
  merged_data <- left_join(ctd_data, dat_data, by = "Timestamp")
  # Omit Oxygen Calculation columns
  selected_columns <- c("Latitude", "Longitude", "Depth", "Temperature","Salinity", "Timestamp", "Alt")  
  new_header_names <- c('Latitude','Longitude','Depth','Temperature', 'Salinity','Date','Alt')  
} else {
  # Read O2S NAV data 
  invisible(o2s_data <- read_o2s_nav_data())
  # Merge filtered tibbles
  merged_data <- left_join(ctd_data, o2s_data, by = "Timestamp") %>% left_join(dat_data, by = "Timestamp")

  # Replace alt NAs with empty strings
  merged_data <- merged_data %>% mutate(across(.cols = c("Alt"), .fns = ~ifelse(is.na(.), "", .)))

  # print("START Oxygen Correction")
  calculate_oxygen <- function(calculate_oxygen_mgperliter, calculate_oxygen_microMolar, calculate_oxygen_mlperliter, merged_data) {
    merged_data <- merged_data %>%
      mutate(Oxygen_microMolar = calculate_oxygen_microMolar(Oxygen, Salinity, Temperature, Depth)) %>%
      mutate(Oxygen_mgperliter = calculate_oxygen_mgperliter(Oxygen_microMolar)) %>%
      mutate(Oxygen_mlperliter = calculate_oxygen_mlperliter(Oxygen_microMolar))
    return(merged_data)
  }
    # calculate Oxygen and merge
    merged_data <- calculate_oxygen(calculate_oxygen_mgperliter, calculate_oxygen_microMolar, calculate_oxygen_mlperliter, merged_data)
    selected_columns <- c("Latitude", "Longitude", "Depth", "Temperature", "Oxygen_mgperliter", "Oxygen_mlperliter", "Salinity", "Timestamp", "Alt")  # Specify the columns you want to select
  new_header_names <- c('Latitude','Longitude','Depth','Temperature','oxygen_mg_per_l', 'oxygen_ml_per_l', 'Salinity','Date','Alt')  # Specify the new header names
}


file_name <- paste0(cruise_number, "_", dive_number, "_", dive_start_date, "_ROVDATA.csv")
output_file_path <- paste0(output_destination_path, "/", file_name)

# Subset the tibble to select the desired columns
selected_data <- merged_data[, selected_columns]

# Rename the selected columns
colnames(selected_data) <- new_header_names

# print(selected_data)
# # # Write the selected and renamed data to a CSV file
time_write_csv <- write.csv(selected_data, file=output_file_path, row.names = FALSE)

cli_alert_success("Merged files")
