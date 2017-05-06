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
Usage: `basename $0` -s STATION -f DATETIME [options]
Options:
  -s STATION      Station ID (see http://radiko.jp/v3/station/region/full.xml)
  -f DATETIME     Record start datetime (%Y%m%d%H%M format)
  -t DATETIME     Record end datetime (%Y%m%d%H%M format)
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

# Check argument parameter
if [ -z "${station_id}" ]; then
  echo "Require \"Station ID\"" >&2
  finalize
  exit 1
fi
if [ -z "${fromtime}" ]; then
  echo "Require \"Record start datetime\"" >&2
  finalize
  exit 1
fi
if [ -z "${totime}" ] && [ -z "${duration}" ]; then
  echo "Require \"Record end datetime\" or \"Record minutes\"" >&2
  finalize
  exit 1
fi

# Calculate totime (-d option)
# **TODO**

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
  # login
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
    "https://radiko.jp/v2/api/ts/playlist.m3u8?station_id=${station_id}&ft=${fromtime}&to=${totime}" \
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
