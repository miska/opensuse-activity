#!/bin/sh
MONTHS_BACK="6"
BASE_URL="http://lists.opensuse.org/"
NOW="`date +%Y-%m-%d`"
FIRST_DATE="`date -d "$MONTHS_BACK months ago" +%s`"
SEND=""

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
    for mail in $@; do
        grep -Ril "^From: .*$mail.*" mail | while read mail_file; do
            MAIL_DATE="`sed -n 's|^Date:\ ||p' | head -n 1`"
	    MAIL_DATE="`date -d "$MAIL_DATE" +%s`"
            if [ "$MAIL_DATE" -gt "$FIRST_DATE" ]; then
                echo "active"
                return 0
            fi
        done
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
    touch 1st-warnings 2nd-warnings 3rd-warnings
    if are_active $MAILS > /dev/null; then
        echo $USER is active
	[ -z "`grep "|$CMAIL\$" 1st-warnings 2nd-warnings 3rd-warnings`" ] || echo $USER was inactive before
        sed -i "/|$CMAIL\$/ d" 1st-warnings
        sed -i "/|$CMAIL\$/ d" 2nd-warnings
        sed -i "/|$CMAIL\$/ d" 3rd-warnings
    else
        echo $USER is inactive
        if [ -z "`grep "|$USER|" 1st-warnings`" ]; then
            [ -z "$SEND" ] || cat 1st-warning | sed "s|@nick@|$USER|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
            echo "`date +%s`|1|$USER|$CMAIL" >> 1st-warnings
            continue
        fi
        if [ -z "`grep "|$USER|" 2nd-warnings`" ]; then
            [ -z "$SEND" ] || cat 2nd-warning | sed "s|@nick@|$USER|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
            echo "`date +%s`|1|$USER|$CMAIL" >> 2nd-warnings
            continue
        fi
        if [ -z "`grep "|$USER|" 3rd-warnings`" ]; then
            [ -z "$SEND" ] || cat 3rd-warning | sed "s|@nick@|$USER|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
            echo "`date +%s`|1|$USER|$CMAIL" >> 3rd-warnings
            continue
        fi
    fi
done < maildump
