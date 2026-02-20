#!/bin/bash
#set -x # for debugging

# brew install ag (ag is the_silver_searcher, faster than grep)

# usage:
# ./na_ctd_processor.sh <cruise_number> <cruise_source_path> <dive_reports_source> <output_destination_path>

# inputs
cruise_number=$1
cruise_source_path=$2
dive_reports_source=$3
output_destination_path=$4
skip_oxygen_calculation=$5

# load pretty colors
txt_bold=$(tput bold)
txt_underline=$(tput sgr 0 1)
txt_success=${txt_bold}$(tput setaf 2)
txt_warn=${txt_bold}$(tput setaf 3)
txt_error=${txt_bold}$(tput setaf 1)
txt_reset=$(tput sgr0)

# OUTPUT - WRITE
today=$(date +%Y%m%d)
tmp_output_destination="$output_destination_path/$cruise_number/$today/tmp"
mkdir -p "$tmp_output_destination"
cd "NA" || exit 1

## Given a Cruise Number, identify the number of dives in the cruise
dive_count=`(ls "$dive_reports_source" | grep -e "^L" | wc -l | tr -d " ")`
if((dive_count == 0)); then
  printf "\n${txt_error}No dives found in $dive_reports_source$txt_reset\n\n"
  exit 1
fi

printf "\n${txt_bold}Found $dive_count dives$txt_reset\n"

dives=($(ls "$dive_reports_source"| grep -e "^L"))

## iterate through each of the dives
for((i = 0; i < dive_count; ++i)); do
  num=$((i+1))
  printf "\n=============================================\n"
  printf "                    ${txt_bold}${dives[i]}${txt_reset}\n"
  printf "                  Dive $num/$dive_count\n"
  dive_number=${dives[i]}

  # GRAB a COPY of TSV FILES LOCALLY
  ctd_nav_tsv_file="${dive_number}.CTD.NAV.tsv"
  ctd_nav_tsv="${dive_reports_source}/${dive_number}/merged/${ctd_nav_tsv_file}"
  if [[ ! -f "$tmp_output_destination/$ctd_nav_tsv_file" ]]; then
    mkdir -p "$tmp_output_destination/ctd_nav" && cp "$ctd_nav_tsv" "$tmp_output_destination/ctd_nav"
  else
    echo "skip copying file over: $ctd_nav_tsv_file"
  fi

  o2s_nav_tsv_file="${dive_number}.O2S.NAV.tsv"
  o2s_nav_tsv="${dive_reports_source}/${dive_number}/merged/${o2s_nav_tsv_file}"
  if [[ ! -f "$tmp_output_destination/$o2s_nav_tsv_file" ]]; then
    mkdir -p "$tmp_output_destination/o2s_nav" && cp "$o2s_nav_tsv" "$tmp_output_destination/o2s_nav"
  else
    echo "skip copying file over: $o2s_nav_tsv_file"
  fi

  # GRAB a START DATE of a DIVE
  dive_start_date=$(head -1 "$tmp_output_destination/ctd_nav/$ctd_nav_tsv_file" | cut -f1 -s | xargs date -j -f "%Y-%m-%dT%H:%M:%S" "+%Y%m%d")

  printf "\nExtracting DAT files..."

  # GRAB a COPY of DAT FILES LOCALLY
	if ! sh ./extract_DAT.sh "${dive_number}" "${cruise_source_path}" "${tmp_output_destination}" "${output_destination_path}"; then
	  # if extract_DAT.sh fails, skip this dive
	  printf "${txt_warn}SKIPPING DIVE${txt_reset}\n"
  else
    # run R script
    printf "Merging data...\r"
    Rscript NA.R "$cruise_number" "$dive_number" "$dive_start_date" "$tmp_output_destination" "$output_destination_path" "$skip_oxygen_calculation" #--vanilla --profile
  fi

done

# CLEANUP
printf "\n---------------------------------------------\n"
printf "\nRemoving temp files...\n"
rm -rf "${output_destination_path:?}/${cruise_number:?}"

printf "$txt_success\nCruise complete!\n$txt_reset"
printf "\nMerged csv files saved to ${txt_underline}${output_destination_path}${txt_reset}\n\n"

open "$output_destination_path"

exit 0
