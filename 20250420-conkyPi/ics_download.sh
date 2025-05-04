#!/bin/bash

export ICS_QUERY_TZ=localtime
export ICS_QUERY_COMPONENT=VEVENT

err() {
    echo "ERROR: $1" >&2
    exit 1
}

verb=false
if [ "A$1" == "A-v" ]; then verb=true; fi
verb_echo() {
    if [ "$verb" == "true" ]; then echo "$1"; fi
}

# requires: wget
test -x $(which wget) || err "wget is not installed"
# brew test (Linux)
it=/home/linuxbrew/.linuxbrew/bin/brew; if [ -x "$it" ]; then eval "$($it shellenv)"; fi
# test brew is available
brew --version > /dev/null || err "brew is not installed"
# requires: uv
uv --version > /dev/null || err "uv is not installed -- brew install uv"
# requires: ics-query
uv run ics-query --version > /dev/null || err "ics-query is not installed -- uv tool install ics-query"

# get the script directory
script_dir=$(cd $(dirname $0); pwd)

source $script_dir/ics_todo.source
# content of ics_todo.source: space separated lines of Name|URL|Color
#todo="Name1|https://calendar.google.com/calendar/ical/.../basic.ics|red"
#todo="$todo Name2|https://calendar.google.com/calendar/ical/.../basic.ics|blue"

list=""
for user in $todo; do
    IFS='|' read -r name url color <<< "$user"
    if [ "A$color" == "A" ]; then color="white"; fi
    list="$list /tmp/$name.ics:$color"
    if [ -f "/tmp/$name.ics" ]; then
        file_time=$(date -r "/tmp/$name.ics" +%s)
        current_time=$(date +%s)
        time_diff=$((current_time - file_time))
        if [ $time_diff -lt 21600 ]; then  # 6 hours in seconds
            verb_echo "/tmp/$name.ics is up to date, skipping"
            continue
        fi
    fi
    verb_echo "** Downloading ${name}"
    wget -qO /tmp/${name}.temp1.ics "$url" || err "Could not download $name calendar"
    uv run ics-query between `date +%Y%m%d` +7d /tmp/${name}.temp1.ics /tmp/${name}.temp2.ics || err "Could not query $name calendar"
    # Get the headers from temp.ics until the first BEGIN:VEVENT and write them to $name.temp3.ics
    event_line=$(grep -n "BEGIN:VEVENT" /tmp/${name}.temp1.ics | head -n 1 | cut -d: -f1)
    head -n $(($event_line - 1)) /tmp/${name}.temp1.ics > /tmp/$name.temp3.ics
    # Get the events from temp2.ics and append them to $name.temp3.ics
    cat /tmp/${name}.temp2.ics >> /tmp/$name.temp3.ics
    # copy the last line of temp.ics to $name.ics
    tail -n 1   /tmp/${name}.temp1.ics >> /tmp/$name.temp3.ics
    # Remove any content between BEGIN:VALARM and END:VALARM
    sed '/BEGIN:VALARM/,/END:VALARM/d' /tmp/$name.temp3.ics > /tmp/$name.ics
    if [ ! -s "/tmp/$name.ics" ]; then err "Downloaded $name calendar is empty"; fi
    rm -f /tmp/${name}.temp*.ics
done

if [ -z "$list" ]; then err "No calendar to merge"; fi

# requires uv (available: brew install uv) -- dependencies listed in the header of merge-cals.py
uv run $script_dir/ics_merge2txt.py $list --conky || err "Could not merge calendars"