#!/bin/sh
MONTHS_BACK="6"
BASE_URL="http://lists.opensuse.org/"
NOW="`date +%Y-%m-%d`"

source `pwd`/config

get_lists() {
    wget -O - "$BASE_URL" | \
    sed -n 's|.*style="text-align:left; vertical-align:top;"><a href="\([^"]*\)".*|\1|p'
}

get_mboxes() {
    [ -z "$NO_DOWNLOAD" ] || return
    for l in `get_lists`; do
        mkdir -p "data/$l"
        pushd "data/$l" > /dev/null
        for i in `seq 0 $MONTHS_BACK`; do
            DATE="`date -d "$NOW $i month ago" +%Y-%m`"
            if [ \! -f "$l-$DATE.mbox.gz" ]; then
                echo -n "Downloading $l ($DATE) ... "
                if wget -c "$BASE_URL$l/$l-$DATE.mbox.gz" > /dev/null 2> /dev/null; then
                    echo "done"
                else
                    echo "failed"
                fi
            fi
        done
        popd > /dev/null
    done
}

are_active() {
    for mail in $@; do
        if [ -n "`zgrep -i -m 1 $mail data/*/*.gz`" ]; then
            echo "active"
            return 0
        fi
    done
    echo "inactive"
    return 1
}

get_mail_dump() {
    [ -f maildump ] || ssh $CONNECT_HOST "wget -O - \"http://connect.opensuse.org/services/api/rest/xml/?method=connect.membersadmin.mails&api_key=$CONNECT_KEY\"" | grep -v '^<' > maildump
}

get_mboxes

while read ln; do
    USER="`echo "$ln" | sed 's|^\([^\|]*\)\ \|.*|\1|'`"
    CMAIL="`echo "$ln" | sed 's|^\([^\|]*\)\ \|\ \([^\|]*\)\ .*|\2|'`"
    MAILS="`echo "$ln" | sed 's|.*\|\ \([^\|]*\)$|\1|' | tr ' ' "\n" | sort -u`"
    if are_active $MAILS > /dev/null; then
        echo $USER is active
        sed -i "/|$CMAIL\$/ d" warnings
    else
        echo $USER is inactive
        if [ -z "`grep "|$USER|" warnings`" ]; then
            cat 1st-warning | sed "s|@nick@|$USER|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
            echo "`date +%s`|1|$USER|$CMAIL" >> warnings
        fi
    fi
done < maildump
