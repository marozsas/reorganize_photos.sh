#!/bin/bash

# move lpeg photo files from source to destination, organazing it by
# date of photo (from metadata)

set  -o nounset -o noclobber -o pipefail
trap go_exit  SIGHUP SIGQUIT SIGTERM

export LC_ALL=C

# returns a string like year/month/day from file metadata.
function get_date_from_meta {
  # echo "DEBUG: $1"

  date_str="unknown_date::"
  dummy=$(exiftool -CreateDate -GPSDateStamp -GPSDateTime -ModifyDate -FileModifyDate -d "%Y:%m:%d" "$1" )

  # test if exiftool returned an error.
  if [ "$?" == "1" ]; then
    # impossible to get exif data.
    # try to use stat instead. mark the date uncertain by adding a
    # underline next to the year.
    dummy=$(stat "$1")

    # try to use Birth as date
    while read -r line; do
      if [[ "$line" =~ "Birth" ]]; then

        if echo "$line" | grep -q "[0-9]"; then
          date_str=$(echo "$line" | awk  '{print $2}' | sed -e 's#-#_-#; s#-#/#g')
          break
        fi
      fi

      # try to use Modify as date
      if [[ "$line" =~ "Modify" ]]; then
        if echo "$line" | grep -q "[0-9]"; then
          date_str=$(echo "$line" | awk  '{print $2}' | sed -e 's#-#_-#; s#-#/#g')
          break
        fi
      fi

      # try to use Change as date
      if [[ "$line" =~ "Change" ]]; then
        if echo "$line" | grep -q "[0-9]"; then
          date_str=$(echo "$line" | awk  '{print $2}' | sed -e 's#-#_-#; s#-#/#g')
          break
        fi
      fi
    done < <(echo "$dummy")
  else
    # exif data is ok, use one of them
    while read -r line; do
      if [[ "$line" =~ "Create" ]]; then
        date_str=$(echo "$line" | awk -F" : " '{print $2}' | sed -e 's#:#/#g')
        break
      fi

      if [[ "$line" =~ "GPS" ]]; then
        date_str=$(echo "$line" | awk -F" : " '{print $2}' | sed -e 's#:#/#g')
        break
      fi

      # for ModifyDate or FileModifyDate add a underline next to year
      # to indicate the date is uncertain.
      if [[ "$line" =~ "Modif" ]]; then
        date_str=$(echo "$line" | awk -F" : " '{print $2}' | sed -e 's#:#_:#; s#:#/#g')
        break
      fi
    done < <(echo "$dummy")
  fi

  # return the date
  echo "$date_str"
}

function go_exit {
  local signal_number="${SIGNAL:-}"
  local caller_info
  caller_info=$(caller)
  local line_number=${caller_info%%:*}
  local function_name=${caller_info#*:}
  echo "go_exit: signal number: ${signal_number}"
  #echo "go_exit: caller_info: $caller_info"
  echo "go_exit: line_number: ${line_number}"
  echo "go_exit: function_name: $function_name"

  cd ... || exit
}

function usage {
    cat << EOF
Description: This script moves image photo files from source to destination,
according with the date of photo (from metadata)

usage: $0 [-v] -s source_dir -d destination_dir...
move jpeg/tiff photo files from source to destination
regex patther is a grep case insensitive extended pattern like.
for instance, "\.jpg$|\.jpeg$|\.tiff$|\.tif$" selects all jpeg and tiff files.
and the pattern "\.nef$|\.raf$|\.dng$" selects all Nikon RAW, Fuji RAW and Adobe DNG files.

OPTIONS:
   -h      Show this message
   -n      dry run
   -s      source directory
   -d      destination directory
   -r      regex pattern used to select files on source
   -v      Verbose
EOF
  exit
}

# Argument processing
# h: help/usage
# s: read input files from stdin
# n: volume name
# v: verbose
f_verbose=0
f_dry=0
f_dst=0
f_src=0
f_regex=0
src=""
dst=""

while getopts "s:d:r:hnv" OPTION; do
  #echo "OPTION: ${OPTION}  ${OPTARG:-null}"
  case $OPTION in
    s)
      f_src=1
      src="${OPTARG}" ;;
    d)
      f_dst=1
      dst="${OPTARG}" ;;
    r)
      f_regex=1
      regex="${OPTARG}" ;;
    h)
      usage ;;
    v)
      f_verbose=1 ;;
    n)
      f_dry=1 ;;
    :)
      echo "Option -${OPTARG:-} requires an argument." > /dev/stderr
      usage
      ;;
    \?)
      echo "Invalid option" > /dev/stderr
      usage ;;
  esac
done

# shift $OPTIND # Shift non-options to positional parameters
shift "$((OPTIND - 1))"
# Access remaining arguments
#echo "DEBUG: number of arguments: ${#}" > /dev/stderr
#echo "DEBUG: First non-option: $1, number of arguments: ${#}" > /dev/stderr
if [ "$#" != "0" ]; then
  echo "Unknown argument $1"
  usage
fi

# sanity checks

if [ "$f_src" == "0" ]; then
    echo "Usage: the source folder must be specified." > /dev/stderr
    usage
fi

if [ "$f_dst" == "0" ]; then
    echo "Usage: the destination folder must be specified." > /dev/stderr
    usage
fi

if [ "$f_regex" == "0" ]; then
    echo "Usage: the regex pattern must be specified." > /dev/stderr
    usage
fi

if [ ! -d "$src" ]; then
	echo "Usage: the source directory $src must exist." > /dev/stderr
	exit
fi

if [ ! -d "$dst" ]; then
	echo "Usage: the destination directory $dst must exist." > /dev/stderr
	exit
fi

if [ ! -r "$src" ]; then
	echo "Usage: the source directory $src must be readable" > /dev/stderr
	exit
fi

if [ ! -w "$dst" ]; then
	echo "Usage: the destination directory $dst must be writable" > /dev/stderr
	exit
fi

# if [ $f_verbose == 1 ]; then
#     echo "DEBUG: verbose mode ON" > /dev/stderr
# else
#     echo "DEBUG: verbose mode OFF" > /dev/stderr
# fi

if [ $f_dry == 1 ]; then
    echo "DEBUG: dry run mode ON" > /dev/stderr
# else
#     echo "DEBUG: dry run mode OFF" > /dev/stderr
fi

if [ $f_verbose == 1 ]; then
    echo "The source folder is $src" > /dev/stderr
    echo "The destination folder is $dst" > /dev/stderr
fi

# test for existence of files on source folder
files=$(shopt -s nullglob dotglob; echo "${src}"/*)
if [ "${#files}" -lt "1" ]; then
    echo "There are no files on source folder." > /dev/stderr
    exit
fi

#echo "about to run"
#exit


#read files on source folder
count=0
while read -r f; do
    base_src=$(basename "$f")
    #echo "DEBUG: $f";

    # get a date from the file metadata
    createDate=$(get_date_from_meta "$f")

    # create the folder on destination
    mkdir -p "${dst}/${createDate}"
    file_on_dst="${dst}/${createDate}/${base_src}"
    # test if the photo already exist on destination
    if [ -f "$file_on_dst" ]; then
      # it already exist. test if they are identical.
      if cmp -bs "$f" "$file_on_dst"; then
        # they are different. Copy it as another version, inserting a
        # random string on filename
        randstr=$(echo $RANDOM | md5sum | head -c 20)
        file_on_dst=$(echo "$file_on_dst" | rev | sed -e "s/\./.${randstr}_/" | rev)
        if [ "$f_dry" == "1" ]; then
          if [ "$f_verbose" == "1" ]; then
            echo cp -v "$f" "$file_on_dst"
          fi
          # do nothing
        else
          # Actual copy
          if [ "$f_verbose" == "1" ]; then
            echo "Colision name avoided on ${base_src}, copied as ${file_on_dst}"
            cp -v "$f" "$file_on_dst"
          else
            cp "$f" "$file_on_dst"
          fi
        fi
        ((count+=1))
      else
        # they are equal. Skip.
        :
      fi
    else
      # it does not exist on dst. copy it.
      if [ "$f_dry" == "1" ]; then
        if [ "$f_verbose" == "1" ]; then
          echo cp -v "$f" "$file_on_dst"
        fi
        # do nothing
      else
        # Actual copy
        if [ "$f_verbose" == "1" ]; then
          cp -v "$f" "$file_on_dst"
        else
          cp "$f" "$file_on_dst"
        fi
      fi
      ((count+=1))
    fi
done< <(find "$src" -type f | grep -Ei "${regex}")

echo "$count files was copied to $dst."

