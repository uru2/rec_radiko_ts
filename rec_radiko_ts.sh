#!/bin/sh
#
# Radiko timefree program recorder
# Copyright (C) 2017-2026 uru (https://twitter.com/uru_2)
# License is MIT (see LICENSE file)
set -eu

# Define authorize key value (from https://radiko.jp/apps/js/playerCommon.js)
readonly AUTHKEY_VALUE='bcd151073c03b352e1ef2fd66c32209da9ca0afa'

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
  -s STATION      Station ID
  -f DATETIME     Record start datetime (%Y%m%d%H%M or %Y%m%d%H%M%S or %H%M or %H%M%S format, JST)
  -t DATETIME     Record end datetime (%Y%m%d%H%M or %Y%m%d%H%M%S or %H%M or %H%M%S format, JST)
  -d MINUTE       Record minute
  -u URL          Set -s, -f, -t option values from timefree program URL
  -m ADDRESS      Radiko premium mail address
  -p PASSWORD     Radiko premium password
  -o FILEPATH     Output file path
  -l              Show station ID, name and delay seconds
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
radiko_login() {
  mail=$1
  password=$2

  # Login
  login_json=$(curl \
      --silent \
      --request POST \
      --data-urlencode "mail=${mail}" \
      --data-urlencode "pass=${password}" \
      --output - \
      'https://radiko.jp/v4/api/member/login' \
    | tr -d '\r\n') || return 1

  # Extract login result
  radiko_session=$(echo "${login_json}" | extract_login_value 'radiko_session')

  # Join areafree?
  is_areafree='0'
  if [ "$(echo "${login_json}" | extract_login_value 'areafree')" = '1' ]; then
    is_areafree='1'
  fi

  # Check login
  if [ -z "${radiko_session}" ]; then
    return 1
  fi

  echo "${radiko_session},${is_areafree}"
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

  # for jq
  #value=$(cat - | jq -r ".${name}")

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
        regex = "^\"[0-9a-zA-Z]+\"";
        if (match(str, regex)) {
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
#   Login session
# Returns:
#   None
#######################################
radiko_logout() {
  radiko_session=$1
  if [ -z "${radiko_session}" ]; then
    return 0
  fi

  # Logout
  curl \
    --silent \
    --request POST \
    --data-urlencode "radiko_session=${radiko_session}" \
    --output /dev/null \
    'https://radiko.jp/v4/api/member/logout' || true  # Ignore error
}

#######################################
# Convert UNIX time
# Arguments:
#   datetime string (%Y%m%d%H%M[%S] format)
# Returns:
#   0: Success
#   1: Failed
#######################################
to_unixtime() {
  # for gawk
  #utime=$(echo "$1" | gawk '{ print mktime(sprintf("%d %d %d %d %d %d", substr($0, 0, 4), substr($0, 5, 2), substr($0, 7, 2), substr($0, 9, 2), substr($0, 11, 2), ((length($0) == 14) ? substr($0, 13, 2) : 0)), 1) - 32400 }')

  utime=$(echo "$1" \
    | awk '{
      date_str = $1;

      if (match(date_str, /[^0-9]/)) {
        # Invalid character
        print -1;
        exit;
      }

      if (length(date_str) != 12 && length(date_str) != 14) {
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
      second = (length(date_str) == 14) ? substr(date_str, 13, 2) - 0 : 0;

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

  if [ "${utime}" = '-1' ]; then
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
#   1: Failed
#######################################
to_datetime() {
  # for gawk
  #datetime=$(echo "$1" | gawk '{ print strftime("%Y%m%d%H%M%S", int($0) + 32400, 1) }')

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

      printf("%04d%02d%02d%02d%02d%02d", year, month, day, hour, minute, second);
    }')

  echo "${datetime}"
  return 0
}

#######################################
# Show all station ID, name and delay seconds
# Arguments:
#   None
# Returns:
#   None
#######################################
show_all_stations() {
  # Format to "{id}:{name}"
  curl --silent 'https://radiko.jp/v3/station/region/full.xml' \
    | xmllint --xpath '/region/stations/station[timefree="1"]/id/text() | /region/stations/station[timefree="1"]/name/text() | /region/stations/station[timefree="1"]/tf_max_delay/text()' - \
    | paste -d ':' - - -
}

#######################################
# Extract parameters from URL
# Arguments:
#   URL
# Returns:
#   0: Success
#   1: Failed
#######################################
extract_url_params() {
  url=$1

  # Extract station ID and record start datetime
  station_id=
  fromtime=
  if echo "${url}" | grep -q -e '^https\{0,1\}://radiko\.jp/#!/ts/' ; then
    # "https://radiko.jp/#!/ts/{station_id}/{fromtime}"
    station_id=$(echo "${url}" | sed -n 's;https\{0,1\}://radiko\.jp/#!/ts/\(.\{1,\}\)/[0-9]\{14,14\}$;\1;p')
    fromtime=$(echo "${url}" | sed -n 's;^https\{0,1\}://radiko\.jp/#!/ts/.\{1,\}/\([0-9]\{14,14\}\)$;\1;p')
  elif echo "${url}" | grep -q -e '^https\{0,1\}://radiko\.jp/share/' ; then
    # "https://radiko.jp/share/?t={fromtime}&sid={station_id}"
    station_id=$(echo "${url}" | sed -n 's;https\{0,1\}://radiko\.jp/share/.*[?&]sid=\([^&]\{1,\}\).*;\1;p')
    fromtime=$(echo "${url}" | sed -n 's;https\{0,1\}://radiko\.jp/share/.*[?&]t=\([0-9]\{1,14\}\).*;\1;p')

    # 24:00-28:59 -> next day 0:00-4:59
    if echo "${fromtime}" | grep -q -e '^[0-9]\{8,8\}2[4-8]' ; then
      utime_date=$(($(to_unixtime "$(echo "${fromtime}" | cut -c 1-8)000000") + 86400))
      utime_hour=$((($(echo "${fromtime}" | awk '{print substr($0,9,2)}') - 24) * 3600))
      utime_minute=$(($(echo "${fromtime}" | awk '{print substr($0,11,2)}') * 60))
      utime_second=$(($(echo "${fromtime}" | awk '{print substr($0,13,2)}') - 0))

      utime=$((utime_date + utime_hour + utime_minute + utime_second))
      fromtime=$(to_datetime "${utime}")
    fi
  fi

  if [ -z "${station_id}" ] || [ -z "${fromtime}" ]; then
    return 1
  fi

  # Extract station area_id
  area_id=$(curl --silent 'https://radiko.jp/v3/station/region/full.xml' \
    | xmllint --xpath "/region/stations/station[id='${station_id}']/area_id/text()" -)
  if [ -z "${area_id}" ]; then
    return 1
  fi

  # Target program date (0:00-4:59 -> previous day)
  program_date=$(to_datetime "$(($(to_unixtime "${fromtime}") - 18000))" | cut -c 1-8)

  # Extract record end datetime
  totime=$(curl --silent "https://api.radiko.jp/program/v3/date/${program_date}/area/${area_id}.xml" \
    | xmllint --xpath "string((/radiko/stations/station[@id='${station_id}']/progs/prog[@ft<='${fromtime}'])[last()]/@to)" -)
  if [ -z "${totime}" ]; then
    return 1
  fi

  # Concat parameters
  echo "${station_id},${fromtime},${totime}"
  return 0
}

#######################################
# Radiko authorize
# Arguments:
#   Login session
# Returns:
#   0: Success
#   1: Failed
#######################################
radiko_auth() {
  radiko_session=$1

  # Authorize 1
  auth1_res=$(curl \
      --silent \
      --header 'X-Radiko-App: pc_html5' \
      --header 'X-Radiko-App-Version: 0.0.1' \
      --header 'X-Radiko-Device: pc' \
      --header 'X-Radiko-User: dummy_user' \
      --dump-header - \
      --output /dev/null \
      'https://radiko.jp/v2/api/auth1' \
    | tr -d '\r') || return 1

  # Get partial key
  authtoken=$(echo "${auth1_res}" | sed -n 's/^[xX]-[rR][aA][dD][iI][kK][oO]-[aU][uU][tT][hH][tT][oO][kK][eE][nN]:[ \t]*\(.\{1,\}\)$/\1/p')
  keyoffset=$(echo "${auth1_res}" | sed -n 's/^[xX]-[rR][aA][dD][iI][kK][oO]-[kK][eE][yY][oO][fF][fF][sS][eE][tT]:[ \t]*\(.\{1,\}\)$/\1/p')
  keylength=$(echo "${auth1_res}" | sed -n 's/^[xX]-[rR][aA][dD][iI][kK][oO]-[kK][eE][yY][lL][eE][nN][gG][tT][hH]:[ \t]*\(.\{1,\}\)$/\1/p')
  if [ -z "${authtoken}" ] || [ -z "${keyoffset}" ] || [ -z "${keylength}" ]; then
    return 1
  fi

  partialkey=$(echo "${AUTHKEY_VALUE}" | dd bs=1 "skip=${keyoffset}" "count=${keylength}" 2> /dev/null | b64_enc | tr -d '\n')
  if [ -z "${partialkey}" ]; then
    return 1
  fi

  # Authorize 2
  auth2_url_param=
  if [ -n "${radiko_session}" ]; then
    auth2_url_param="?radiko_session=${radiko_session}"
  fi
  auth2_res=$(curl \
      --silent \
      --header 'X-Radiko-Device: pc' \
      --header 'X-Radiko-User: dummy_user' \
      --header "X-Radiko-AuthToken: ${authtoken}" \
      --header "X-Radiko-PartialKey: ${partialkey}" \
      "https://radiko.jp/v2/api/auth2${auth2_url_param}" \
    | tr -d '\r') || return 1
  if [ -z "${auth2_res}" ] || [ "${auth2_res}" = 'OUT' ]; then
    # Not detected access area(prefecture) or detected not in Japan
    return 1
  fi

  # Detected area ID (prefecture)
  area_id=$(echo "${auth2_res}" | head -n 1 | cut -d ',' -f1)

  echo "${authtoken},${area_id}"
  return 0
}

#######################################
# BASE64 encode wrapper
# Arguments:
#   (pipe)Target binary
# Returns:
#   0: Success
#   1: Failed
#######################################
b64_enc() {
  if command -v base64 > /dev/null ; then
    base64
  elif command -v basenc > /dev/null ; then
    basenc --base64 -
  elif command -v openssl > /dev/null ; then
    openssl enc -base64
  elif command -v uuencode > /dev/null ; then
    uuencode -m - | sed -e '1d' -e '$d'
  elif command -v b64encode > /dev/null ; then
    b64encode - | sed -e '1d' -e '$d'
  else
    echo 'base64, basenc, openssl, uuencode, b64encode commands not found.' >&2
    return 1
  fi
  return 0
}

#######################################
# Get HLS playlist URL list
# Arguments:
#   Station ID
#   Join area free flag
# Returns:
#   0: Success
#   1: Failed
#######################################
get_hls_urls() {
  station_id=$1
  is_areafree=$2

  areafree='0'
  if [ "${is_areafree}" = '1' ]; then
    areafree='1'
  fi

  # TimeFree 30 playlist (Possibly bandwidth limited)
  #  1st line: Main playlist, requires the "-http_seekable 0" option in ffmpeg >= 4.3 (Suppresses HTTP "Range" request headers)
  #  2nd line: Sub playlist
  curl --silent "https://radiko.jp/v3/station/stream/pc_html5/${station_id}.xml" \
    | xmllint --xpath "/urls/url[@timefree='1' and @areafree='${areafree}']/playlist_create_url/text()" - \
    | tr -d '\r'
}

#######################################
# Create a temporary directory
# Arguments:
#   None
# Returns:
#   0: Success
#   1: Failed
#######################################
mk_temp_dir() {
  # Alternative to "mktemp -d"
  tmp_dir="$(realpath "${TMPDIR:-/tmp}")/recradikots_$(head -n 2 /dev/random | b64_enc | tr -dc '0-9a-zA-Z' | cut -c 1-8)"
  if [ -d "${tmp_dir}" ]; then
    echo "Already exists ${tmp_dir}" >&2
    return 1
  fi

  mkdir -p "${tmp_dir}"
  echo "${tmp_dir}"
  return 0
}

# Define argument values
station_id=
fromtime=
totime=
duration=
url=
mail="${RADIKO_MAIL:-}"
password="${RADIKO_PASSWORD:-}"
output=

# Argument none?
if [ $# -lt 1 ]; then
  show_usage
  exit 1
fi

# Parse argument
while getopts s:f:t:d:m:u:p:o:l option; do
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
    l)
      show_all_stations
      exit 0
      ;;
    \?)
      show_usage
      exit 1
      ;;
  esac
done

# DateTime string completion
if echo "${fromtime}" | grep -q -E -e '^([0-1][0-9]|2[0-3])[0-5][0-9]([0-5][0-9]){0,1}$' ; then
  fromtime="$(date '+%Y%m%d')${fromtime}"
fi
if echo "${totime}" | grep -q -E -e '^([0-1][0-9]|2[0-3])[0-5][0-9]([0-5][0-9]){0,1}$' ; then
  totime="$(date '+%Y%m%d')${totime}"
fi

# Get program infomation from URL (-u option)
if [ -n "${url}" ]; then
  if ! url_params=$(extract_url_params "${url}") ; then
    echo 'Parse URL failed' >&2
    exit 1
  fi

  station_id=$(echo "${url_params}" | cut -d ',' -f1)
  fromtime=$(echo "${url_params}" | cut -d ',' -f2)
  totime=$(echo "${url_params}" | cut -d ',' -f3)
fi

# Convert to UNIX time
if ! utime_from=$(to_unixtime "${fromtime}") ; then
  echo 'Invalid "Record start datetime"' >&2
  exit 1
fi
utime_to=0
if [ -n "${totime}" ]; then
  if ! utime_to=$(to_unixtime "${totime}") ; then
    echo 'Invalid "Record end datetime"' >&2
    exit 1
  fi

  if [ "${utime_from}" -gt "${utime_to}" ]; then
    echo 'Start and end datetime range is invalid.' >&2
    exit 1
  fi
fi

# Check argument parameter
if [ -z "${station_id}" ]; then
  # -s value is empty
  echo 'Require "Station ID"' >&2
  exit 1
fi
if [ -z "${fromtime}" ]; then
  # -f value is empty
  echo 'Require "Record start datetime"' >&2
  exit 1
fi
if [ "${utime_from}" -lt 0 ]; then
  # -f value is empty
  echo 'Invalid "Record start datetime" format' >&2
  exit 1
fi
if [ -z "${totime}" ] && [ -z "${duration}" ]; then
  # -t value and -d value are empty
  echo 'Require "Record end datetime" or "Record minutes"' >&2
  exit 1
fi
if [ "${utime_to}" -lt 0 ]; then
  # -t value is invalid
  echo 'Invalid "Record end datetime" format' >&2
  exit 1
fi
if [ -n "${duration}" ] && echo "${duration}" | grep -q -e '[^0-9]' ; then
  # -d value is invalid
  echo 'Invalid "Record minute"' >&2
  exit 1
fi

# Calculate totime (-d option)
if [ -n "${duration}" ]; then
  # Compare -t value and -d value
  utime_to2=$((utime_from + (duration * 60)))

  if [ "${utime_to}" -lt ${utime_to2} ]; then
    # Set -d value
    utime_to=${utime_to2}
  fi

  totime=$(to_datetime "${utime_to}")
fi

# Second string completion
if echo "${fromtime}" | grep -q -e '^[0-9]\{12,12\}$' ; then
  fromtime="${fromtime}00"
fi
if echo "${totime}" | grep -q -e '^[0-9]\{12,12\}$' ; then
  totime="${totime}00"
fi

# Login premium
radiko_session=
is_areafree=
if [ -n "${mail}" ]; then
  i=1
  while : ; do
    # Max 3 times
    if res=$(radiko_login "${mail}" "${password}") ; then
      # Success
      radiko_session=$(echo "${res}" | cut -d ',' -f1)
      is_areafree=$(echo "${res}" | cut -d ',' -f2)
      break
    fi

    i=$((i + 1))
    if [ ${i} -gt 3 ]; then
      echo 'Cannot login Radiko premium' >&2
      exit 1
    fi

    sleep 5
  done
fi

# Authorize
authtoken=
area_id=
i=1
while : ; do
  # Max 3 times
  if res=$(radiko_auth "${radiko_session}") ; then
    # Success
    authtoken=$(echo "${res}" | cut -d ',' -f1)
    area_id=$(echo "${res}" | cut -d ',' -f2)
    break
  fi

  i=$((i + 1))
  if [ ${i} -gt 3 ]; then
    echo 'auth failed' >&2
    radiko_logout "${radiko_session}"
    exit 1
  fi

  sleep 5
done

# Generate default file path
if [ -z "${output}" ]; then
  output="${station_id}_${fromtime}_${totime}.m4a"
else
  # Fix file path extension
  if ! echo "${output}" | grep -q -e '\.m4a$' ; then
    # Add .m4a
    output="${output}.m4a"
  fi
fi

# Generate pseudo random MD5 hash values (tracking key?)
lsid=$(head -n 5 /dev/random | b64_enc | tr -dc '0-9a-f' | cut -c 1-32)

# Record
record_success='0'
ffmpeg_header=$(printf 'X-Radiko-Authtoken: %s\r\nX-Radiko-AreaId: %s' "${authtoken}" "${area_id}")

# Chunk download mode
chunk_no=0
seek_timestamp=$(to_unixtime "${fromtime}")
left_sec=$(($(to_unixtime "${totime}") - seek_timestamp))

# Generate temporary directory
tmp_dir="$(mk_temp_dir)"

# ffmpeg chunk file list
touch "${tmp_dir}/filelist.txt"

# New mode playlist only
for hls_url in $(get_hls_urls "${station_id}" "${is_areafree}"); do
  record_success='1'

  # Split to chunks
  while [ ${left_sec} -gt 0 ]; do
    chunk_file="${tmp_dir}/chunk${chunk_no}.m4a"

    # Chunk max 300 seconds
    l=300
    if [ "${left_sec}" -lt 300 ]; then
      # 5 second interval
      if [ "$(($((left_sec % 5))))" -eq 0 ]; then
        l="${left_sec}"
      else
        # Round up to the nearest 5 seconds
        l="$(($(($((left_sec / 5)) + 1)) * 5))"
      fi
    fi

    seek=$(to_datetime "${seek_timestamp}")
    end_at=$(to_datetime "$((seek_timestamp + l))")

    # chunk download
    if ! ffmpeg \
        -nostdin \
        -loglevel error \
        -fflags +discardcorrupt \
        -headers "${ffmpeg_header}" \
        -http_seekable 0 \
        -seekable 0 \
        -i "${hls_url}?station_id=${station_id}&start_at=${fromtime}&ft=${fromtime}&seek=${seek}&end_at=${end_at}&to=${end_at}&l=${l}&lsid=${lsid}&type=c" \
        -acodec copy \
        -vn \
        -bsf:a aac_adtstoasc \
        -y \
        "${chunk_file}" ; then
      record_success='0'
      break
    fi

    # Append to chunk file list
    echo "file '${chunk_file}'" >> "${tmp_dir}/filelist.txt"

    # chunk duration
    chunk_sec=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "${chunk_file}" \
      | awk '{printf("%d\n",$1+0.5)}')

    # Next chunk
    left_sec=$((left_sec - chunk_sec))
    seek_timestamp=$((seek_timestamp + chunk_sec))
    chunk_no=$((chunk_no + 1))
  done

  if [ "${record_success}" = '1' ]; then
    break
  fi
done

if [ "${record_success}" = '1' ]; then
  # Concat chunk files (no encoding)
  if ! ffmpeg -loglevel error -f concat -safe 0 -i "${tmp_dir}/filelist.txt" -c copy -y "${output}" ; then
    record_success='0'
  fi
fi

# Cleanup temporary directory
rm -rf "${tmp_dir}"

if [ "${record_success}" != '1' ]; then
  echo 'Record failed' >&2
  radiko_logout "${radiko_session}"
  exit 1
fi

# Finish
radiko_logout "${radiko_session}"
exit 0
