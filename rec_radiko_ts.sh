#!/bin/sh
#
# Radiko timefree program recorder
# Copyright (C) 2017-2019 uru (https://twitter.com/uru_2)
# License is MIT (see LICENSE file)
set -u

radiko_session=""

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

  # Login
  login_json=$(curl \
      --silent \
      --request POST \
      --data-urlencode "mail=${mail}" \
      --data-urlencode "pass=${password}" \
      --output - \
      "https://radiko.jp/v4/api/member/login" \
    | tr -d "\r" \
    | tr -d "\n")

  # Extract login result
  radiko_session=$(echo "${login_json}" | extract_login_value "radiko_session")
  areafree=$(echo "${login_json}" | extract_login_value "areafree")

  # Check login
  if [ -z "${radiko_session}" ] || [ "${areafree}" != "1" ]; then
    return 1
  fi

  return 0
}

#######################################
# Extract login JSON value
# Arguments:
#   (pipe)Login result JSON
#   Key
# Returns:
#   None
#######################################
extract_login_value() {
  name=$1

  # for gawk
  #value=$(cat - | gawk -v "name=${name}" 'BEGIN { FS = "\n"; } { regex = "\""name"\"[ ]*:[ ]*(\"[0-9a-zA-Z]+\"|[0-9]*)"; if (!match($0, regex, v)) { exit 0; } val=v[1]; if (match(val, /\"([0-9a-zA-Z]*)\"/, v)) { val=v[1]; } print val; }')

  value=$(cat - \
    | awk -v "name=${name}" '
      BEGIN {
        FS = "\n";
      }
      {
        # Extract key and value
        regex = "\""name"\"[ ]*:[ ]*(\"[0-9a-zA-Z]+\"|[0-9]*)";
        if (!match($1, regex)) {
          exit 0;
        }
        str = substr($0, RSTART, RLENGTH);

        # Extract value
        regex = "\""name"\"[ ]*:[ ]*";
        match(str, regex);
        str = substr(str, RSTART + RLENGTH);

        # String value
        if (match(str, /^\"[0-9a-zA-Z]+\"/)) {
          print substr(str, RSTART + 1, RLENGTH - 2);
          exit 0;
        }

        # Numeric value
        if (match(str, /^[0-9]*/)) {
          print substr(str, RSTART, RLENGTH);
          exit 0;
        }
      }')

  echo "${value}"
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
  # Logout
  curl \
    --silent \
    --request POST \
    --data-urlencode "radiko_session=${radiko_session}" \
    --output /dev/null \
    "https://radiko.jp/v4/api/member/logout"
  radiko_session=""
  return 0
}

#######################################
# Finalize program
# Arguments:
#   None
# Returns:
#   None
#######################################
finalize() {
  if [ -n "${radiko_session}" ]; then
    logout
  fi
  return 0
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

  echo "${utime}"
  if [ "${utime}" = "-1" ]; then
    return 1
  fi
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
      station_id="${OPTARG}"
      ;;
    f)
      fromtime="${OPTARG}"
      ;;
    t)
      totime="${OPTARG}"
      ;;
    d)
      duration="${OPTARG}"
      ;;
    m)
      mail="${OPTARG}"
      ;;
    u)
      url="${OPTARG}"
      ;;
    p)
      password="${OPTARG}"
      ;;
    o)
      output="${OPTARG}"
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
if [ "${utime_from}" -lt 0 ]; then
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
if [ "${utime_to}" -lt 0 ]; then
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

  if [ "${utime_to1}" -lt ${utime_to2} ]; then
    # Set -d value
    utime_to=${utime_to2}
  fi

  totime=$(to_datetime "${utime_to}")
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
auth1_res=$(curl \
    --silent \
    --header "X-Radiko-App: pc_html5" \
    --header "X-Radiko-App-Version: 0.0.1" \
    --header "X-Radiko-Device: pc" \
    --header "X-Radiko-User: dummy_user" \
    --dump-header - \
    --output /dev/null \
    "https://radiko.jp/v2/api/auth1")

# Get partial key
authtoken=$(echo "${auth1_res}" | awk 'tolower($0) ~/^x-radiko-authtoken: / {print substr($0,21,length($0)-21)}')
keyoffset=$(echo "${auth1_res}" | awk 'tolower($0) ~/^x-radiko-keyoffset: / {print substr($0,21,length($0)-21)}')
keylength=$(echo "${auth1_res}" | awk 'tolower($0) ~/^x-radiko-keylength: / {print substr($0,21,length($0)-21)}')

if [ -z "${authtoken}" ] || [ -z "${keyoffset}" ] || [ -z "${keylength}" ]; then
  echo "auth1 failed" >&2
  finalize
  exit 1
fi

partialkey=$(echo "${AUTHKEY_VALUE}" | dd bs=1 "skip=${keyoffset}" "count=${keylength}" 2> /dev/null | base64)

# Authorize 2
auth2_url_param=""
if [ -n "${radiko_session}" ]; then
  auth2_url_param="?radiko_session=${radiko_session}"
fi
curl \
    --silent \
    --header "X-Radiko-Device: pc" \
    --header "X-Radiko-User: dummy_user" \
    --header "X-Radiko-AuthToken: ${authtoken}" \
    --header "X-Radiko-PartialKey: ${partialkey}" \
    --output /dev/null \
    "https://radiko.jp/v2/api/auth2${auth2_url_param}"
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
