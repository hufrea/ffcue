#!/usr/bin/sh

CUE_FILE=""
FAW_FILE=""
PICTURE=""
EX="flac"
NAME='$TRACK - $TITLE'
INPUT="cat /dev/null"
FORMAT="flac"
CUSTOM=""

set -eu

help="Usage: ffcue.sh [SCRIPT OPTIONS] [FFMPEG OPTIONS]\n"
help="$help  -e <file>  cue file path\n"
help="$help  -i <file>  input file, if not set use path from cue file\n"
help="$help  -f <str>   ffmpeg output format, default 'flac'\n"
help="$help             flac, mp3, opus, ipod, vorbis...\n"
help="$help  -o <str>   output file name, default '\$TRACK - \$TITLE'\n"
help="$help             vars: TRACK, TITLE, ARTIST, ALBUM, GENRE, DATE, COMPOSER, ALBUM_ARTIST\n"
help="$help  -p <file>  picture file\n"

while [ $# != 0 ]; do
  case "$1" in
     '--help')
         printf "$help"
         exit ;;
     '-i'|'--input')
         FAW_FILE="$2"
         shift ;;
     '-f'|'--format')
         FORMAT="$2"
         shift ;;
     '-e'|'--cue')
         CUE_FILE="$2"
         shift ;;
     '-p'|'--pic')
         PICTURE="$2"
         shift ;;
     '-o'|'--output')
         NAME="$2"
         shift ;;
     *)
         CUSTOM="$CUSTOM $1"
         ;;
  esac; shift
done

if [ ! "$CUE_FILE" ]; then
    printf "$help"
    exit 1
fi

EX="$FORMAT"
case "$FORMAT" in
    "opus" | "vorbis")
        EX="ogg"
        
        if [ "$PICTURE" ]; then
            INPUT="gen_oggpic"
            CUSTOM="-i - -map_metadata 1 -map_metadata 0 $CUSTOM"
        fi ;;
    *)
        [ "$FORMAT" = "ipod" ] && EX="m4a"
        [ "$FORMAT" = "adts" ] && EX="aac"
        
        if [ "$PICTURE" ]; then
            INPUT='cat "$PICTURE"'
            CUSTOM="-i - -c:v copy -map 0 -map 1:v -disposition:v attached_pic $CUSTOM"
        fi ;;
esac

echo "ffmpeg params: $CUSTOM" 1>&2

read DATE ALBUM ALBUM_ARTIST GENRE COMPOSER CATALOG \
    TRACK TITLE ARTIST ISRC INDEX \
    CR_TRACK CR_TITLE CR_ARTIST CR_ISRC CR_INDEX </dev/null || true

get_str() { 
    echo "$1" | cut -d'"' -f2; 
}

no_octa() {
    printf "%.0f\n" "$1"
}

cue2ff_time() {
    min=$(echo "$1" | cut -d':' -f1)
    ffhour=$(($(no_octa "$min")/60))
    ffmin=$(($(no_octa "$min") % 60))
    ffsec=$(echo "$1" | cut -d':' -f2)
    frames=$(echo "$1" | cut -d':' -f3 | tr -d -c 0-9)
    ffms=$(((1333 * $(no_octa "$frames")) / 100))
    printf '%.2d:%.2d:%s.%.3d\n' "$ffhour" "$ffmin" "$ffsec" "$ffms"
}

read_i() {
    r="0"
    for i in $(seq 0 $(($1 - 1))); do
        c="$(head -c 1)"
        [ ! "$c" ] && continue
        d=$(printf '%d' "'$c'")
        r=$(((d << (8*($1-1-i))) + r))
    done
    printf '%d' "$r"
}

parse_flac_pic() {
    head -c 4 >/dev/null
    while true; do
        t=$(read_i 1)
        size=$(read_i 3)
        if [ "$t" = "6" ] || [ "$t" = "134" ]; then
            head -c "$size"
            break
        else head -c "$size" >/dev/null
        fi
    done
}

gen_oggpic() {
	printf ';FFMETADATA1\nMETADATA_BLOCK_PICTURE='
	cat /dev/null | ffmpeg -i "$FAW_FILE" -i "$PICTURE" -map_metadata -1 -t 1 -v warning \
	    -map 0 -map 1 -disposition:v attached_pic -c:v copy -f flac - | \
	        parse_flac_pic | base64 -w 0
}
        
cut_file() {
    START=$(cue2ff_time "$INDEX")
    
    if [ ! "$CR_INDEX" ]; then 
        TO=""
    else 
        END=$(cue2ff_time "$CR_INDEX")
        TO="-to $END"
    fi
    if [ ! "$ARTIST" ]; then
        ARTIST="$ALBUM_ARTIST"
    fi
    
    eval "$INPUT" | ffmpeg -ss "$START" $TO \
        -i "$FAW_FILE" $CUSTOM -f "$FORMAT" \
        -metadata album="$ALBUM" -metadata date="$DATE" -metadata genre="$GENRE" \
        -metadata album_artist="$ALBUM_ARTIST" -metadata composer="$COMPOSER" \
        -metadata title="$TITLE" -metadata artist="$ARTIST" -metadata track="$TRACK" \
        -metadata CATALOG="$CATALOG" -metadata ISRC="$ISRC" \
        "$(eval echo "$NAME").$EX"
}

TRACK_PART=""
PSEUDO='\nFILE "" WAVE\n'

(cat "$CUE_FILE" && printf "$PSEUDO") | while read line; do
    if [ ! "$TRACK_PART" ]; then
        case $line in
            'PERFORMER'*)
                ALBUM_ARTIST=$(get_str "$line")
                ;;
            'REM GENRE'*)
                GENRE="${line#*GENRE }"
                ;;
            'REM DATE'*)
                DATE="${line#*DATE }"
                ;;
            'TITLE'*)
                ALBUM=$(get_str "$line")
                ;;
            'REM COMPOSER'*)
                COMPOSER=$(get_str "$line")
                ;;
            'CATALOG'*)
                CATALOG="${line#*CATALOG }"
                ;;
            'FILE'*)
                if [ ! "$FAW_FILE" ]; then
                    FAW_FILE=$(get_str "$line")
                fi
                TRACK_PART=1
                ;;
            *)
                echo "ignore: $line" >&2
                ;;
        esac
        continue;
    fi
    
    case "$line" in
        *'TRACK'*|'FILE'*)
            TRACK="$CR_TRACK"
            ARTIST="$CR_ARTIST"
            TITLE="$CR_TITLE"
            ISRC="$CR_ISRC"
            INDEX="$CR_INDEX"
            
            if [ "${line#FILE}" != "$line" ]; then
                CR_INDEX=""
                cut_file
                FAW_FILE=$(get_str "$line")
                continue
            fi
            CR_TITLE=""
            CR_ARTIST=""
            CR_ISRC=""
            
            CR_TRACK=$(echo "${line#*TRACK }" | cut -d' ' -f1)
            ;;
        *'TITLE'*)
            CR_TITLE=$(get_str "$line")
            ;;
        *'PERFORMER'*)
            CR_ARTIST=$(get_str "$line")
            ;;
        *'ISRC'*)
            CR_ISRC="${line#*ISRC }"
            ;;
        *'INDEX 01'*)
            CR_INDEX="${line#*INDEX 01 }"
            if [ "$INDEX" ]; then
                cut_file
            fi
            ;;
        *)
            echo "ignore: $line" >&2
            ;;
    esac
done;
