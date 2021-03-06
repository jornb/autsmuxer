#!/bin/bash
#
# autsmuxer - automated tsMuxeR wrapper.
# Copyright (C) 2012  Joseph Wiseman
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU Library General Public License as published
# by the Free Software Foundation; either version 2, or (at your option)
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#


##default options - uncomment and set##
#RECURSIVE=0	##recurse when provided with directory input.
#SAVE_INPUT=1	##set to 1 to retain MKV input files.
#OUTPUT=''	##default output directory.
#TEMP=''	##default temp directory.
#FORMAT=''	##available: ts, m2ts, bluray, avchd, demux
#DTS=0		##set to 1 to never transcode DTS.
#VTRACK=''	##specify video track.
#ATRACK=''	##specify audio track.
#STRACK=''	##specify subs track.
SFONT='/usr/share/fonts/TTF/DejaVuSans.ttf'	##required only for subs.
#SPLIT=''	##maximum filesize per part. eg. 4000MB (safer with 3900) for FAT32 filesystem.
#SPDIF=''	##convert AC3 and DTS to LPCM - set to 1 for DTS only, 2 for AC3/DTS.


##


TITLE='autsmuxer'
VERSION=4.20121124

IFS=$'\n'

##


type_allpkgreq () {
  for pkg in $@; do
    ! $(type "${pkg}" &> '/dev/null') && { echo -e "\n ${pkg} is required."; ((pkgreqcounter++)); }
  done
  
  [ -n "${pkgreqcounter}" ] && die
}


##


tsmuxer_mkv2x () {
  echo -e " Processing: ${1}..\n"
  
  mkvinfo=$(mkvinfo --ui-language en_US "${1}")
  case $(echo "${mkvinfo}" | grep 'EBML version:' | cut -d' ' -f4) in
    1) audio_lang='und'
      subs_lang='und'
    ;;
    *) _extebml=0
    ;;
  esac
  
  
  for vc in V_MPEG4/ISO/AVC V_MS/VFW/WVC1 V_MPEG-2; do
    video_codec+=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${vc}" | cut -d' ' -f6))
  done
  for vt in ${video_codec[@]}; do
    video_track=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${vt}" -B11 | grep -i "+ Track number:" | cut -d' ' -f6))
  done
  #echo ${video_codec[@]}
  #echo ${video_track[@]}
  
  for ac in A_AC3 A_AAC A_DTS A_MP3 A_MPEG/L2 A_MPEG/L3 A_LPCM; do
    audio_codec+=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${ac}" | cut -d' ' -f6))
  done
  for at in ${audio_codec[@]}; do
    audio_track=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${at}" -B11 | grep -i "+ Track number:" | cut -d' ' -f6))
  done
  [ -z "${audio_lang}" ] && audio_lang=($(echo "${mkvinfo}" | grep -i "Track type: audio" -A18 | grep -i "Language:" | cut -d' ' -f5))
  #echo ${audio_codec[@]}
  #echo ${audio_track[@]}
  #echo ${audio_lang[@]}
  
  for sf in S_HDMV/PGS S_TEXT/UTF8; do
    subs_format=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${sf}" | cut -d' ' -f6))
  done
  for st in ${subs_format[@]}; do
    subs_track=($(echo "${mkvinfo}" | grep -i "+ Codec ID: ${st}" -B11 | grep -i "+ Track number:" | cut -d' ' -f6))
  done
  [ -z "${subs_lang}" ] && subs_lang=($(echo "${mkvinfo}" | grep -i "Track type: subtitles" -A18 | grep -i "Language:" | cut -d' ' -f5))
  #echo ${subs_format[@]}
  #echo ${subs_track[@]}
  #echo ${subs_lang[@]}

  [ -n "${VTRACK}" ] && vid=$((VTRACK-1)) || vid=0
  [ -n "${ATRACK}" ] && aud=$((ATRACK-1)) || aud=0
  [ -n "${STRACK}" ] && sub=$((STRACK-1)) || sub=0

  video_extract=${video_track[vid]}
  video_extract=$((video_extract-1))
  audio_extract=${audio_track[aud]}
  audio_extract=$((audio_extract-1))
  subs_extract=${subs_track[sub]}
  subs_extract=$((subs_extract-1))
  
  [ -f "${3}.meta" ] && rm "${3}.meta"
  
  if [ -n "${video_codec[vid]}" ]; then
    video_fps=$(echo "${mkvinfo}" | grep "+ Track number: ${video_track[vid]}" -A18 | grep -i "+ Default duration:" -m1 | cut -d' ' -f7 | tr -d '(')
    
    case "${FORMAT:=m2ts}" in
      ts|m2ts) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --vbr --vbv-len=500" >> "${3}.meta"
      ;;
      bluray) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --blu-ray --vbr --auto-chapters=5 --vbv-len=500" >> "${3}.meta"
      ;;
      avchd) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --avchd --vbr --auto-chapters=5 --vbv-len=500" >> "${3}.meta"
      ;;
      demux) echo -n "MUXOPT --no-pcr-on-video-pid --new-audio-pes --demux --vbr --vbv-len=500" >> "${3}.meta"
      ;;
    esac
    
    [ -n "${SPLIT}" ] && echo -n " --split-size=${SPLIT}" >> "${3}.meta"
    
    case ${_extebml} in
      0) echo -e "\n${video_codec[vid]}, \"${1}\", level=4.1, fps=${video_fps}, insertSEI, contSPS, track=${video_track[vid]}, lang=${audio_lang[aud]}" >> "${3}.meta"
      ;;
      *) mkvextract tracks "${1}" $video_extract:"${3}.264" && 
        echo -e "\n${video_codec[vid]}, ${3}.264, level=4.1, fps=${video_fps}, insertSEI, contSPS, lang=${audio_lang[aud]}" >> "${3}.meta" || die
      ;;
    esac
    
  else
    die "\n Incompatible video codec found."
  fi
  
  _spdifconvert () {
    ##audio_channels=$(echo "${mkvinfo}" | grep -i "+ Track number: ${audio_track[aud]}" -A18 | grep -i "+ Channels:" -m1 | cut -d' ' -f6)
    ##audio_frequency=$(echo "${mkvinfo}" | grep -i "+ Track number: ${audio_track[aud]}" -A18 | grep -i "+ Sampling frequency:" -m1 | cut -d' ' -f7)
    
    ##mencoder -noconfig all -msglevel all=-1 -really-quiet -of rawaudio -af format=s16le -lavdopts threads=2 
    ##-oac pcm -ovc frameno "${1}" -of rawaudio -channels "${audio_channels}" -srate "${audio_frequency}" -mc 0 -noskip -o - | spdifconvert --stdin --persevere --output="${2}.wav"
    
    mkvextract tracks "${1}" $audio_extract:"${2}.aud" && spdifconvert -v "${2}.aud" && 
    echo "A_LPCM, ${2}.aud.wav, lang=${audio_lang[aud]}" >> "${2}.meta" || die
  }
  
  case "${audio_codec[aud]}" in
    A_DTS)
      if [ "${DTS:=0}" = 0 -a "${SPDIF:=0}" = 0 ]; then
        mkvextract tracks "${1}" $audio_extract:"${3}.dts" && dcadec -o wavall "${3}.dts" | aften -v 0 -readtoeof 1 - "${3}.ac3" && 
        echo "A_AC3, ${3}.ac3, lang=${audio_lang[aud]}" >> "${3}.meta" || die
      else
        if [ "${SPDIF}" = 0 ]; then
          case ${_extebml} in
            0) echo "A_DTS, \"${1}\", track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${3}.meta"
            ;;
            *) mkvextract tracks "${1}" $audio_extract:"${3}.dts" && 
              echo "A_DTS, ${3}.dts, lang=${audio_lang[aud]}" >> "${3}.meta" || die
            ;;
          esac
        else
          _spdifconvert "${1}" "${3}"
        fi
      fi
    ;;
    A_AC3)
      _repairac3 () {
        audio_channels=$(echo "${mkvinfo}" | grep -i "+ Track number: ${audio_track[aud]}" -A18 | grep -i '+ Channels:' -m1 | cut -d' ' -f6)
        audio_frequency=$(echo "${mkvinfo}" | grep -i "+ Track number: ${audio_track[aud]}" -A18 | grep -i '+ Sampling frequency:' -m1 | cut -d' ' -f7)
        
        ##if input headers contain 'Name' tag, mencoder only reads first few MBs. few files will require this (bizarre) fix.
        $(echo "${mkvinfo}" | grep -i "+ Track number: ${audio_track[aud]}" -A18 | grep -q '+ Name:') && audio_channels=2
        
        case "${audio_channels}" in
          2) _aften () { aften -v 1 -raw_ch 2 -raw_sr "${audio_frequency}" -b 192 -wmax 30 - "${1}.ac3"; }
          ;;
          *) _aften () { aften -v 1 -raw_ch "${audio_channels}" -lfe 1 -raw_sr "${audio_frequency}" -b 384 -wmax 30 - "${1}.ac3"; }
          ;;
        esac
        
        mencoder -noconfig all -msglevel all=-1 -really-quiet -of rawaudio -af format=s16le -lavdopts threads=2 
        -oac pcm -ovc frameno "${1}" -of rawaudio -channels "${audio_channels}" -srate "${audio_frequency}" -mc 0 -noskip -o - | _aften "${2}"
        
        [ -f "${2}.ac3" ] || die
        
        echo "A_AC3, ${2}.ac3, lang=${audio_lang[aud]}" >> "${2}.meta"
      }
      
      if [ "${SPDIF:=0}" != 2 ]; then
        case ${_extebml} in
          0) _tsmuxerinfo=$(tsMuxeR "${1}")
            if ! echo "${_tsmuxerinfo}" | grep -s "Track ID:    ${audio_track[aud]}" -A1 | grep -q "Can't detect stream type"; then
              echo "A_AC3, \"${1}\", track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${3}.meta"
            else
              _repairac3 "${1}" "${3}"
            fi
          ;;
          *) mkvextract tracks "${1}" $audio_extract:"${3}.ac3" && _tsmuxerinfo=$(tsMuxeR "${3}.ac3") || die
            if ! echo "${_tsmuxerinfo}" | grep -q "Can't detect stream type"; then
              echo "A_AC3, ${3}.ac3, lang=${audio_lang[aud]}" >> "${3}.meta"
            else
              rm "${3}.ac3"
              _repairac3 "${1}" "${3}"
            fi
          ;;
        esac
      elif [ "${SPDIF}" = 2 ]; then
        _spdifconvert "${1}" "${3}"
      fi
    ;;
    A_MPEG/L[2-3])
      case ${_extebml} in
        0) echo "A_MP3, \"${1}\", track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${3}.meta"
        ;;
        *) mkvextract tracks "${1}" $audio_extract:"${3}.mp3" && 
          echo "A_MP3, ${3}.mp3, lang=${audio_lang[aud]}" >> "${3}.meta" || die
        ;;
      esac
    ;;
    A_*)
      case ${_extebml} in
        0) echo "${audio_codec[aud]}, \"${1}\", track=${audio_track[aud]}, lang=${audio_lang[aud]}" >> "${3}.meta"
        ;;
        *) mkvextract tracks "${1}" $audio_extract:"${3}.aud" && 
          echo "${audio_codec[aud]}, ${3}.aud, lang=${audio_lang[aud]}" >> "${3}.meta" || die
        ;;
      esac
    ;;
    *) die "\n Incompatible audio codec found."
    ;;
  esac
  
  
  if [ -f "${SFONT}" -a -n "${subs_format[sub]}" ]; then
    video_width=$(echo "${mkvinfo}" | grep '+ Pixel width:' -m1 | cut -d':' -f2 | tr -d ' ')
    video_height=$(echo "${mkvinfo}" | grep '+ Pixel height:' -m1 | cut -d':' -f2 | tr -d ' ')
    
    case ${_extebml} in
      0) subs_source="${1}"
      ;;
      *) mkvextract tracks "${1}" $subs_extract:"${3}.sub" && subs_source="${3}.sub" || die
      ;;
    esac
    
    echo "${subs_format[sub]}, ${subs_source}, font-name=${SFONT}, font-size=45, font-color=0x00ffffff, bottom-offset=24, 
	font-border=2, text-align=center, video-width=${video_width}, video-height=${video_height}, fps=${video_fps}, track=${subs_track[sub]}, 
    lang=${subs_lang[sub]}" >> "${3}.meta"
  fi
  
  output="${2}"
  case "${FORMAT}" in
    ts|m2ts) output+=".${FORMAT}"
    ;;
    bluray|avchd|demux) output+='.'$(echo "${FORMAT}" | tr [:lower:] [:upper:])
    ;; ##no ${^^} for OSX/BSD support.
  esac
  
  tsMuxeR "${3}.meta" "${output}" && echo -e "\n ${1##*/} successfully remuxed to: ${output}!" || { rm -f "${output}"; die "\n Error remuxing: ${1##*/}."; }
  
  rm -f "${3}."{meta,264,dts,ac3,wav,mp3,aud,sub} &> '/dev/null'
  [ "${SAVE_INPUT:=1}" = 0 ] && rm -rf "${1}"
  
  return 0
}


die() {
  echo -e "${1}"
  rm -rf "${TEMP}"
  
  exit 1
}


##


usage () {
  echo -e "\n ${TITLE} - ${VERSION}"
  echo -e "\n usage: ${0##*/} [-options] inputfile/dir."
  echo -e "\n options:"
  echo -e "\n\t -R \t- Recursively search for MKV files."
  echo -e "\n\t -d \t- Delete input file after successful mux."
  echo -e "\n\t -o \t- Specify output directory."
  echo -e "\n\t -t \t- Specify temporary directory."
  echo -e "\n\t -f \t- Set format - (<ts/m2ts/bluray/avchd/demux>)."
  echo -e "\n\n\t --recursive <0/1>"
  echo -e "\n\t --save-input <0/1>"
  echo -e "\n\t --output </output/dir/>"
  echo -e "\n\t --temp </temp/dir/>"
  echo -e "\n\t --format <ts/m2ts/bluray/avchd/demux>"
  echo -e "\n\t --dts <0/1>"
  echo -e "\n\t --vtrack <#>"
  echo -e "\n\t --atrack <#>"
  echo -e "\n\t --strack <#>"
  echo -e "\n\t --sfont </path/to/font.ttf>"
  echo -e "\n\t --split <#MB/GB>"
  echo -e "\n\t --spdif <0/1/2>"
  
  exit 0
}


##


[ "$#" == 0 ] && usage

while [ "$#" -ne 0 ]; do
  case ${1} in
    --recursive)
      shift; RECURSIVE="${1}"
      [ -z "${1}" -o "${1}" -ge 2 ] && die "\n RECURSIVE must be 1 or 0."
    ;;
    --save-input)
      shift; SAVE_INPUT="${1}"
      [ -z "${1}" -o "${1}" -ge 2 ] && die "\n SAVE_INPUT must be 1 or 0."
    ;;
    -o|--output)
      shift; [ -n "${1}" ] && OUTPUT="${1}" || die "\n No OUTPUT directory provided."
    ;;
    -t|--temp)
      shift; [ -n "${1}" ] && TEMP="${1}" || die "\n No TEMP directory provided."
    ;;
    -f|--format)
      shift; [[ $(echo "${1}" | egrep -o "ts|m2ts|bluray|avchd|demux") ]] && FORMAT="${1}" || die "\n Invalid FORMAT provided."
    ;;
    --dts)
      shift; DTS="${1}"
      [ -z "${1}" -o "${1}" -ge 2 ] && die "\n DTS must be 1 or 0."
    ;;
    --vtrack)
      shift; VTRACK=$(echo "${1}" | tr -d '[:alpha:]')
      [ -z "${1}" -o "${1}" = 0 ] && die "\n VTRACK track must be >1."
    ;;
    --atrack)
      shift; ATRACK=$(echo "${1}" | tr -d '[:alpha:]')
      [ -z "${1}" -o "${1}" = 0 ] && die "\n ATRACK track must be >1."
    ;;
    --strack)
      shift; STRACK=$(echo "${1}" | tr -d '[:alpha:]')
      [ -z "${1}" -o "${1}" = 0 ] && die "\n STRACK track must be >1."
    ;;
    --sfont)
      shift; SFONT="${1}"
      [ ! -f "${SFONT}" ] && die "\n Font file: ${SFONT} not found."
    ;;
    --split)
      shift; SPLIT="${1}"
      [ -z "${1}" -o "${1}" = 0 ] && die "\n SPLIT must be >1."
    ;;
    --spdif)
      shift; SPDIF="${1}"
      [ -z "${1}" -o "${1}" -ge 3 ] && die "\n SPDIF must be <2."
    ;;
    -*)
      while getopts ":hRd" opt ${1}; do
        case "${opt}" in
          h)
            usage
            exit 0
          ;;
          R)
            RECURSIVE=1
          ;;
          d)
            SAVE_INPUT=0
          ;;
        esac
      done
    ;;
    *) INPUT=("${1}")
    ;;
  esac
  shift
done

[ "${SPDIF:=0}" != 0 ] && spdifconvert="spdifconvert" || spdifconvert="type"
type_allpkgreq "mkvinfo" "mkvextract" "dcadec" "aften" "mencoder" "tsMuxeR" "${spdifconvert}"


if [ "${RECURSIVE:=0}" = 1 -a -d "${INPUT}" ]; then
  INPUT=($(find "${INPUT}" -type f | egrep -i "\.mkv$" | sort))
elif [ -d "${INPUT}" ]; then
  INPUT=($(find "${INPUT}" -maxdepth 1 -type f | egrep -i "\.mkv$" | sort))
elif [ ! -f "${INPUT}" ]; then
  die "\n Input file: ${INPUT} not found.";
fi

[ -n "${OUTPUT}" -a ! -d "${OUTPUT}" ] && { mkdir -p "${OUTPUT}" || die "Unable to create output directory: ${OUTPUT}."; }
TEMP="${TEMP:=$PWD}/autsmuxer-tmp-$$"; mkdir -p "${TEMP}" || die "Unable to create temporary directory: ${TEMP}."

for input in ${INPUT[@]}; do
  [ -n "${OUTPUT}" ] && output="${OUTPUT}/${input##*/}" || output="${input}"
  tsmuxer_mkv2x "${input}" "${output%.*}" "${TEMP}/$$"
done

rm -rf "${TEMP}"