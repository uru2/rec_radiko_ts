#!/bin/sh
#
# Radiko timefree program recorder
# Copyright (C) 2017 uru (https://twitter.com/uru_2)
# License is MIT (see LICENSE file)
set -u
pid=$$

is_login=0
work_path=/tmp/tmp_rec_radiko_ts
cookie="${work_path}/cookie.dat"
auth1_res="${work_path}/auth1_res.${pid}"
login_pid="${work_path}/login_pid.${pid}"

# Define authorize key value (from http://radiko.jp/apps/js/playerCommon.js)
readonly AUTHKEY_VALUE="bcd151073c03b352e1ef2fd66c32209da9ca0afa"

#######################################
# Show usage
# Arguments:
#   None
# Returns:
#   None
#######################################
show_usage() {
  cat << _EOT_
Usage: $(basename "$0") [options]
Options:
  -s STATION      Station ID (see http://radiko.jp/v3/station/region/full.xml)
  -f DATETIME     Record start datetime (%Y%m%d%H%M format, JST)
  -t DATETIME     Record end datetime (%Y%m%d%H%M format, JST)
  -d MINUTE       Record minute
  -u URL          Set -s, -f, -t option values from timefree program URL
  -m ADDRESS      Radiko premium mail address
  -p PASSWORD     Radiko premium password
  -o FILEPATH     Output file path
_EOT_
}

#######################################
# Radiko Premium Login
# Arguments:
#   Mail address
#   Password
# Returns:
#   0: Success
#   1: Failed
#######################################
login() {
  mail=$1
  password=$2

  # Running other logged in process?
  if [ ! -f "${cookie}" ]; then
    # Login
    curl \
        --silent \
        --insecure \
        --request POST \
        --data-urlencode "mail=${mail}" \
        --data-urlencode "pass=${password}" \
        --cookie-jar "${cookie}" \
        --output /dev/null \
        "https://radiko.jp/ap/member/login/login"
  fi

  # Check login
  check=$(curl \
      --silent \
      --insecure \
      --cookie "${cookie}" \
      "https://radiko.jp/ap/member/webapi/member/login/check" \
    | awk /\"areafree\":/)
  if [ -z "${check}" ]; then
    rm -f "${cookie}"
    return 1
  fi

  # Register pid, set login flag
  printf "%s" "${pid}" > "${login_pid}"
  is_login=1

  return 0
}

#######################################
# Radiko Premium Logout
# Arguments:
#   None
# Returns:
#   None
#######################################
logout() {
  # Find executing other logged in process
  exists_other=0
  find_result=$(mktemp)
  find "${work_path}" -type f -name "login_pid.*" > "${find_result}"
  while read -r file; do
    file_pid=$(cat "${file}")

    # Current process?
    if [ "${file_pid}" = "${pid}" ]; then
      # Current process
      continue
    fi

    # Alive process?
    if [ -n "$(ps -o "pid" -p "${file_pid}" | awk 'NR>1{gsub(" ","");print $0;}')" ]; then
      # Exists other process
      exists_other=1
    else
      # Target process forced termination?
      rm -f "${file}"
    fi
  done < "${find_result}"
  rm -f "${find_result}"

  # Other logged in process is not exists, then logout
  if [ ${exists_other} -eq 0 ]; then
    curl \
        --silent \
        --insecure \
        --cookie "${cookie}" \
        --output /dev/null \
        "https://radiko.jp/ap/member/webapi/member/logout"

    rm -f "${cookie}"
  fi

  # Remove pid, unset login flag
  is_login=0
  rm -f "${login_pid}"
}

#######################################
# Finalize program
# Arguments:
#   None
# Returns:
#   None
#######################################
finalize() {
  # Logout
  if [ ${is_login} -eq 1 ]; then
    logout
  fi

  # Remove temporary files
  rm -f "${auth1_res}"
}

#######################################
# Convert UNIX time
# Arguments:
#   datetime string (%Y%m%d%H%M format)
# Returns:
#   0: Success
#   1: Failure
#######################################
to_unixtime() {
  if [ $# -ne 1 ]; then
    printf "%s" "-1"
    return 1
  fi

  # for gawk
  #utime=$(echo "$1" | gawk '{ print mktime(sprintf("%d %d %d %d %d 0", substr($0, 0, 4), substr($0, 5, 2), substr($0, 7, 2), substr($0, 9, 2), substr($0, 11, 2))) }')

  utime=$(echo "$1" \
    | awk '{
      date_str = $1;

      if (match(date_str, /[^0-9]/)) {
        # Invalid character
        print -1;
        exit;
      }

      if (length(date_str) != 12) {
        # Invalid length
        print -1;
        exit;
      }

      # Split datetime parts
      year = substr(date_str, 1, 4) - 0;
      month = substr(date_str, 5, 2) - 0;
      day = substr(date_str, 7, 2) - 0;
      hour = substr(date_str, 9, 2) - 0;
      minute = substr(date_str, 11, 2) - 0;
      second = 0;

      # Validation parts
      if ((year < 1970) || (month < 1) || (month > 12) || (hour < 0) || (hour > 23) \
        || (minute < 0) || (minute > 59) || (second < 0) || (second > 59)) {
        print -1;
        exit;
      }
      split("31 0 31 30 31 30 31 31 30 31 30 31", days_of_month);
      days_of_month[2] = (year % 4 != 0) ? 28 : (year % 100 != 0) ? 29 : (year % 400 != 0) ? 28 : 29;
      if (day > days_of_month[month]) {
        print -1;
        exit;
      }

      # To UNIX time
      if (month < 3) {
        month+= 12;
        year--;
      }
      tz_offset = 32400;  # JST(UTC+9)
      utime = (365 * year + int(year / 4) - int(year / 100) + int(year / 400) + int(306 * (month + 1) / 10) - 428 + day - 719163) \
                * 86400 + (hour * 3600) + (minute * 60) + second - tz_offset;
      print utime;
      exit;
    }')

  if [ "${utime}" = "-1" ]; then
    return 1
  fi

  echo "${utime}"
  return 0
}

#######################################
# UNIX time to datetime string
# Arguments:
#   UNIX time
# Returns:
#   0: Success
#   1: Failure
#######################################
to_datetime() {
  if [ $# -ne 1 ]; then
    echo ""
    return 1
  fi

  # for gawk
  #datetime=$(echo "$1" | gawk '{ print strftime("%Y%m%d%H%M", $0) }')

  datetime=$(echo "$1" \
    | awk '{
      ut = $0 + 32400;  # JST(UTC+9)

      # hour, minute, second
      tm = ut;
      second = tm % 60;
      tm = int(tm / 60);
      minute = tm % 60;
      tm = int(tm / 60);
      hour = int(tm % 24);

      # year, month, day
      year = 1970;
      left_days = int(ut / 86400) + 1;
      while (left_days > 0) {
        is_leap = (((year) % 4) == 0 && (((year) % 100) != 0 || ((year) % 400) == 0));
        year_days = (is_leap == 0) ? 365 : 366;
        if (left_days > year_days) {
          year++;
          left_days -= year_days;
          continue;
        }

        split("31 28 31 30 31 30 31 31 30 31 30 31", days_of_month);
        days_of_month[2] = (is_leap == 0) ? 28 : 29;
        month = 1;
        day = 0;
        for (i = 1; i <= 12; i++) {
          if (days_of_month[i] >= left_days) {
            day = left_days;
            left_days = 0;
            break;
          }
          left_days -= days_of_month[i];
          month++;
        }
      }

      printf("%04d%02d%02d%02d%02d", year, month, day, hour, minute);
    }')

  echo "${datetime}"
  return 0
}

# Define argument values
station_id=
fromtime=
totime=
duration=
url=
mail=
password=
output=

# Argument none?
if [ $# -lt 1 ]; then
  show_usage
  finalize
  exit 1
fi

# Parse argument
while getopts s:f:t:d:m:u:p:o: option; do
  case "${option}" in
    s)
      station_id=${OPTARG}
      ;;
    f)
      fromtime=${OPTARG}
      ;;
    t)
      totime=${OPTARG}
      ;;
    d)
      duration=${OPTARG}
      ;;
    m)
      mail=${OPTARG}
      ;;
    u)
      url=${OPTARG}
      ;;
    p)
      password=${OPTARG}
      ;;
    o)
      output=${OPTARG}
      ;;
    \?)
      show_usage
      finalize
      exit 1
      ;;
  esac
done

# Get program infomation from URL (-u option)
if [ -n "${url}" ]; then
  # Extract station ID and record start datetime
  station_id=$(echo "${url}" | sed -n 's/^https\{0,1\}:\/\/radiko\.jp\/#!\/ts\/\(.\{1,\}\)\/[0-9]\{14,14\}$/\1/p')
  ft=$(echo "${url}" | sed -n 's/^https\{0,1\}:\/\/radiko\.jp\/#!\/ts\/.\{1,\}\/\([0-9]\{14,14\}\)$/\1/p')
  fromtime=$(echo "${ft}" | cut -c 1-12)
  if [ -z "${station_id}" ] || [ -z "${fromtime}" ]; then
    echo "Parse URL failed" >&2
    finalize
    exit 1
  fi

  # Extract record end datetime
  totime=$(curl --silent "http://radiko.jp/v3/program/station/weekly/${station_id}.xml" \
    | xmllint --xpath "/radiko/stations/station[@id='${station_id}']/progs/prog[@ft='${ft}']/@to" - \
    | sed -n 's/^[ ]\{0,\}to=["'']\{0,\}\([0-9]\{14,14\}\)["'']\{0,\}$/\1/p' \
    | cut -c 1-12)
  if [ -z "${totime}" ]; then
    echo "Parse URL failed" >&2
    finalize
    exit 1
  fi
fi

# Convert to UNIX time
utime_from=$(to_unixtime "${fromtime}")
utime_to=0
if [ -n "${totime}" ]; then
  utime_to=$(to_unixtime "${totime}")
fi

# Check argument parameter
if [ -z "${station_id}" ]; then
  # -s value is empty
  echo "Require \"Station ID\"" >&2
  finalize
  exit 1
fi
if [ -z "${fromtime}" ]; then
  # -f value is empty
  echo "Require \"Record start datetime\"" >&2
  finalize
  exit 1
fi
if [ ${utime_from} -lt 0 ]; then
  # -f value is empty
  echo "Invalid \"Record start datetime\" format" >&2
  finalize
  exit 1
fi
if [ -z "${totime}" ] && [ -z "${duration}" ]; then
  # -t value and -d value are empty
  echo "Require \"Record end datetime\" or \"Record minutes\"" >&2
  finalize
  exit 1
fi
if [ ${utime_to} -lt 0 ]; then
  # -t value is invalid
  echo "Invalid \"Record end datetime\" format" >&2
  finalize
  exit 1
fi
if [ -n "${duration}" ] && [ -z "$(echo "${duration}" | awk '/^[0-9]+$/ {print $0}')" ]; then
  # -d value is invalid
  echo "Invalid \"Record minute\"" >&2
  finalize
  exit 1
fi

# Calculate totime (-d option)
if [ -n "${duration}" ]; then
  # Compare -t value and -d value
  utime_to1=${utime_to}
  utime_to2=$((utime_from + (duration * 60)))

  if [ ${utime_to1} -lt ${utime_to2} ]; then
    # Set -d value
    utime_to=${utime_to2}
  fi

  totime=$(to_datetime "${utime_to}")
fi

# Create work path
if [ ! -d "${work_path}" ]; then
  mkdir "${work_path}"
fi

# Create authorize key file
authkey="${work_path}/authkey.txt"
if [ ! -f "${authkey}" ]; then
  printf "%s" "${AUTHKEY_VALUE}" > ${authkey}
fi

# Login premium
if [ -n "${mail}" ]; then
  login "${mail}" "${password}"
  ret=$?

  if [ ${ret} -ne 0 ]; then
    echo "Cannot login Radiko premium" >&2
    finalize
    exit 1
  fi
fi

# Authorize 1
curl \
    --silent \
    --insecure \
    --header "X-Radiko-App: pc_html5" \
    --header "X-Radiko-App-Version: 0.0.1" \
    --header "X-Radiko-Device: pc" \
    --header "X-Radiko-User: dummy_user" \
    --cookie "${cookie}" \
    --dump-header "${auth1_res}" \
    --output /dev/null \
    "https://radiko.jp/v2/api/auth1"
ret=$?

if [ ${ret} -ne 0 ]; then
  echo "auth1 failed" >&2
  finalize
  exit 1
fi

# Get partial key
authtoken=$(awk 'tolower($0) ~/^x-radiko-authtoken: / {print substr($0,21,length($0)-21)}' < "${auth1_res}")
keyoffset=$(awk 'tolower($0) ~/^x-radiko-keyoffset: / {print substr($0,21,length($0)-21)}' < "${auth1_res}")
keylength=$(awk 'tolower($0) ~/^x-radiko-keylength: / {print substr($0,21,length($0)-21)}' < "${auth1_res}")
partialkey=$(dd "if=${authkey}" bs=1 "skip=${keyoffset}" "count=${keylength}" 2> /dev/null | base64)

# Authorize 2
curl \
    --silent \
    --insecure \
    --header "X-Radiko-Device: pc" \
    --header "X-Radiko-User: dummy_user" \
    --header "X-Radiko-AuthToken: ${authtoken}" \
    --header "X-Radiko-PartialKey: ${partialkey}" \
    --cookie "${cookie}" \
    --output /dev/null \
    "https://radiko.jp/v2/api/auth2"
ret=$?

if [ ${ret} -ne 0 ]; then
  echo "auth2 failed" >&2
  finalize
  exit 1
fi

# Generate default file path
if [ -z "${output}" ]; then
  output="${station_id}_${fromtime}_${totime}.m4a"
else
  # Fix file path extension
  echo "${output}" | grep -q "\\.m4a$"
  ret=$?

  if [ ${ret} -ne 0 ]; then
    # Add .m4a
    output="${output}.m4a"
  fi
fi

# Record
ffmpeg \
    -loglevel error \
    -fflags +discardcorrupt \
    -headers "X-Radiko-Authtoken: ${authtoken}" \
    -i "https://radiko.jp/v2/api/ts/playlist.m3u8?station_id=${station_id}&l=15&ft=${fromtime}00&to=${totime}00" \
    -acodec copy \
    -vn \
    -bsf:a aac_adtstoasc \
    -y \
    "${output}"
ret=$?

if [ ${ret} -ne 0 ]; then
  echo "Record failed" >&2
  finalize
  exit 1
fi

# Finish
finalize
exit 0
