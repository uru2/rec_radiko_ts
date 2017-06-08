#!/bin/sh
#
# Radiko timefree program recorder
# Copyright (C) 2017 uru (https://twitter.com/uru_2)
# License is MIT (see LICENSE file)

pid=$$
is_login=0

## Get script basepath
#current_path=`pwd`
#cd `dirname $0`
#base_path=`pwd`
#cd "${current_path}"
#work_path="${base_path}/tmp_rec_radiko_ts"

work_path=/tmp/tmp_rec_radiko_ts

cookie="${work_path}/${pid}_cookie"
auth1_fms="${work_path}/${pid}_auth1_fms"

#######################################
# Show usage
# Arguments:
#   None
# Returns:
#   None
#######################################
show_usage() {
  cat << _EOT_
Usage: `basename $0` -s STATION -f DATETIME (-t DATETIME or -d MINUTE) [options]
Options:
  -s STATION      Station ID (see http://radiko.jp/v3/station/region/full.xml)
  -f DATETIME     Record start datetime (%Y%m%d%H%M format, JST)
  -t DATETIME     Record end datetime (%Y%m%d%H%M format, JST)
  -d MINUTE       Record minute
  -m ADDRESS      Radiko premium mail address
  -p PASSWORD     Radiko premium password
  -o FILEPATH     Output file path
_EOT_
}


#######################################
# Finalize program
# Arguments:
#   None
# Returns:
#   None
#######################################
finalize() {
  # Logout premium
  if [ "${is_login}" -eq 1 ]; then
    curl \
        --silent \
        --insecure \
        --cookie "${cookie}" \
        --output /dev/null \
        "https://radiko.jp/ap/member/webapi/member/logout"

    is_login=0
  fi

  # Remove temporary files
  rm -f "${cookie}"
  rm -f "${auth1_fms}"
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
    echo -1
    return 1
  fi

  # for gawk
  #utime=`echo "$1" | gawk '{ print mktime(sprintf("%d %d %d %d %d 0", substr($0, 0, 4), substr($0, 5, 2), substr($0, 7, 2), substr($0, 9, 2), substr($0, 11, 2))) }'`

  utime=`echo "$1" \
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
    }'`

  echo "${utime}"
  if [ ${utime} -eq -1 ]; then
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
    return -1
  fi

  # for gawk
  #datetime=`echo "$1" | gawk '{ print strftime("%Y%m%d%H%M", $0) }'`

  datetime=`echo "$1" \
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
    }'`

  echo "${datetime}"
  return 0
}

# Define argument values
station_id=
fromtime=
totime=
duration=
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
while getopts s:f:t:d:m:p:o: option; do
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

# Convert to UNIX time
utime_from=`to_unixtime "${fromtime}"`
utime_to=0
if [ ! -z "${totime}" ]; then
  utime_to=`to_unixtime "${totime}"`
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
if [ ! -z "${duration}" ] && [ -z "`echo \"${duration}\" | awk '/^[0-9]+$/ {print $0}'`" ]; then
  # -d value is invalid
  echo "Invalid \"Record minute\"" >&2
  finalize
  exit 1
fi

# Calculate totime (-d option)
if [ ! -z "${duration}" ]; then
  utime_to1=${utime_to}
  utime_to2=`expr ${utime_from} + \( ${duration} \* 60 \)`

  if [ ${utime_to1} -lt ${utime_to2} ]; then
    utime_to=${utime_to2}
  fi

  totime=`to_datetime ${utime_to}`
fi

# Create work path
if [ ! -d "${work_path}" ]; then
  mkdir "${work_path}"
fi

# Get authorize key file
authkey="${work_path}/authkey.jpg"
if [ ! -f "${authkey}" ]; then
  curl \
      --silent \
      --output "${work_path}/myplayer-release.swf" \
      "http://radiko.jp/apps/js/flash/myplayer-release.swf"

  swfextract --binary 12 "${work_path}/myplayer-release.swf" --output "${authkey}"
fi

# Login premium
if [ -n "${mail}" ]; then
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

  # Check login
  check=`curl \
      --silent \
      --insecure \
      --cookie "${cookie}" \
      "https://radiko.jp/ap/member/webapi/member/login/check" \
    | awk /\"areafree\":/`

  if [ -z "${check}" ]; then
    echo "Cannot login Radiko premium" >&2
    finalize
    exit 1
  fi

  # Set login flag
  is_login=1
fi

# Authorize 1
curl \
    --silent \
    --insecure \
    --request POST \
    --data "" \
    --header "pragma: no-cache" \
    --header "X-Radiko-App: pc_ts" \
    --header "X-Radiko-App-Version: 4.0.0" \
    --header "X-Radiko-User: test-stream" \
    --header "X-Radiko-Device: pc" \
    --cookie "${cookie}" \
    --output "${auth1_fms}" \
    "https://radiko.jp/v2/api/auth1_fms"

if [ $? -ne 0 ]; then
  echo "auth1_fms failed" >&2
  finalize
  exit 1
fi

# Get partial key
authtoken=`cat "${auth1_fms}" | awk 'tolower($0) ~/^x-radiko-authtoken=/ {print substr($0,20,length($0)-20)}'`
keyoffset=`cat "${auth1_fms}" | awk 'tolower($0) ~/^x-radiko-keyoffset=/ {print substr($0,20,length($0)-20)}'`
keylength=`cat "${auth1_fms}" | awk 'tolower($0) ~/^x-radiko-keylength=/ {print substr($0,20,length($0)-20)}'`
partialkey=`dd if=${authkey} bs=1 skip=${keyoffset} count=${keylength} 2> /dev/null | base64`

# Authorize 2
curl \
    --silent \
    --insecure \
    --request POST \
    --header "pragma: no-cache" \
    --header "X-Radiko-App: pc_ts" \
    --header "X-Radiko-App-Version: 4.0.0" \
    --header "X-Radiko-User: test-stream" \
    --header "X-Radiko-Device: pc" \
    --header "X-Radiko-AuthToken: ${authtoken}" \
    --header "X-Radiko-PartialKey: ${partialkey}" \
    --cookie "${cookie}" \
    --output /dev/null \
    "https://radiko.jp/v2/api/auth2_fms"

if [ $? -ne 0 ]; then
  echo "auth2_fms failed" >&2
  finalize
  exit 1
fi

# Get playlist
playlist=`curl \
    --silent \
    --insecure \
    --request POST \
    --header "pragma: no-cache" \
    --header "X-Radiko-AuthToken: ${authtoken}" \
    "https://radiko.jp/v2/api/ts/playlist.m3u8?station_id=${station_id}&ft=${fromtime}00&to=${totime}00" \
  | awk '/^https?:\/\// {print $0}'`

if [ $? -ne 0 ] || [ -z "${playlist}" ]; then
  echo "Cannot get playlist" >&2
  finalize
  exit 1
fi

# Generate default file path
if [ -z "${output}" ]; then
  output="${station_id}_${fromtime}_${totime}.m4a"
fi
if [ -f "${output}" ]; then
  rm -f "${output}"
fi

# Fix file path
echo "${output}" | grep -q "\.m4a$"
if [ $? -ne 0 ]; then
  # Add .m4a
  output="${output}.m4a"
fi

# Record
ffmpeg \
    -loglevel error \
    -fflags +discardcorrupt \
    -headers "X-Radiko-Authtoken: ${authtoken}" \
    -i "${playlist}" \
    -acodec copy \
    -vn \
    -bsf:a aac_adtstoasc \
    "${output}"

if [ $? -ne 0 ]; then
  echo "Record failed" >&2
  finalize
  exit 1
fi

finalize
exit 0
