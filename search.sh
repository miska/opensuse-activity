#!/bin/bash
MONTHS_BACK="6"
ND_WAR="28"
RD_WAR="7"
KICK="5"
BASE_URL="http://lists.opensuse.org/"
NOW="`date +%Y-%m-%d`"
NOW_S="`date +%s`"
FIRST_DATE="`date -d "$MONTHS_BACK months ago" +%s`"
SEND="y"
IGNORE_REPLIES=""

ND_WAR="`expr $ND_WAR \* 24 \* 3600`"
RD_WAR="`expr $RD_WAR \* 24 \* 3600`"
KICK="`expr   $KICK   \* 24 \* 3600`"

source `pwd`/config

get_lists() {
    wget -O - "$BASE_URL" | \
    sed -n 's|.*style="text-align:left; vertical-align:top;"><a href="\([^"]*\)".*|\1|p'
}
kick() {
    ssh $CONNECT_HOST "curl -H 'Host: connect.opensuse.org' -X POST 'http://127.0.0.1/services/api/rest/xml/?method=connect.user.groups.del' -d 'login=$1&group_guid=111&api_key=$CONNECT_KEY'" < /dev/null
    ssh $CONNECT_HOST "curl -H 'Host: connect.opensuse.org' -X POST 'http://127.0.0.1/services/api/rest/xml/?method=connect.user.groups.add' -d 'login=$1&group_guid=52448&api_key=$CONNECT_KEY'" < /dev/null
}

restore() {
    ssh $CONNECT_HOST "curl -H 'Host: connect.opensuse.org' -X POST 'http://127.0.0.1/services/api/rest/xml/?method=connect.user.groups.del' -d 'login=$1&group_guid=52448&api_key=$CONNECT_KEY'" < /dev/null
    ssh $CONNECT_HOST "curl -H 'Host: connect.opensuse.org' -X POST 'http://127.0.0.1/services/api/rest/xml/?method=connect.user.groups.add' -d 'login=$1&group_guid=111&api_key=$CONNECT_KEY'" < /dev/null
}

get_mboxes() {
    [ -z "$NO_DOWNLOAD" ] || return
    offlineimap
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

last_active() {
    mkdir -p cache
    LAST_CHECKED_MAIL=0
    if [ -f "cache/$1" ]; then
        ACTIVE_CACHE="`head -n 1 "cache/$1"`"
        LAST_CHECKED_MAIL="`tail -n 1 "cache/$1"`"
	[ "$ACTIVE_CACHE" \!= "$LAST_CHECKED_MAIL" ] || LAST_CHECKED_MAIL=0
	LAST_CACHE_ACTIVE="0`echo $ACTIVE_CACHE | cut -f 1 -d :`"
	LAST_CACHE_MAIL_ACTIVE="0`echo $ACTIVE_CACHE | cut -f 2 -d :`"
        if [ $LAST_CACHE_ACTIVE -gt $FIRST_DATE ]; then
            echo "$ACTIVE_CACHE"
            return
	else
            rm -f "cache/$1"
	fi
    fi
    LAST_ACTIVE="0"
    LAST_MAIL_ACTIVE="0"
    NEW_LAST_CHECKED_MAIL="$LAST_CHECKED_MAIL"
    for mail in $@; do
        if expr "x$mail" : x- > /dev/null; then
            continue
        fi
	if [ -z "$IGNORE_REPLIES" ]; then
            grep -Ril -e "^From:.*$mail.*" -e "^Sender:.*$mail.*" mail | \
            while read mail_file; do
                MAIL_DATE="`sed -n 's|^Date:\ ||p' "$mail_file" | head -n 1`"
                MAIL_DATE="`date -d "$MAIL_DATE" +%s`"
                if [ "$MAIL_DATE" -gt "$LAST_MAIL_ACTIVE" ]; then
                    LAST_MAIL_ACTIVE="$MAIL_DATE"
                fi
            done
        fi
        [ "$LAST_ACTIVE" -gt "$LAST_MAIL_ACTIVE" ] || LAST_ACTIVE="$LAST_MAIL_ACTIVE"
        for i in data/*/*.gz; do
    	    MAIL_DATE="`echo "$i" | sed -n 's|.*\([2-9][0-9][0-9][0-9]\)-\([0-1][0-9]\).mbox.gz|\1-\2-01|p'`"
    	    MAIL_DATE="`date -d "$MAIL_DATE" +%s`"
    	    # First day of month + 31 days
	    [ "$NEW_LAST_CHECKED_MAIL" -gt "$MAIL_DATE" ] || NEW_LAST_CHECKED_MAIL="$MAIL_DATE"
    	    MAIL_DATE="`expr "$MAIL_DATE" + 2678400`"
    	    if [ "$MAIL_DATE" -gt "$LAST_ACTIVE" ] && [ "$MAIL_DATE" -gt "$LAST_CHECKED_MAIL" ] && [ -n "`zgrep -i -m 1 "$mail" $i`" ]; then
    	        LAST_ACTIVE="$MAIL_DATE"
    	    fi
        done
    done
    echo $LAST_ACTIVE:$LAST_MAIL_ACTIVE > "cache/$1"
    echo $NEW_LAST_CHECKED_MAIL >> "cache/$1"
    echo $LAST_ACTIVE:$LAST_MAIL_ACTIVE
}

get_mail_dump() {
    ssh $CONNECT_HOST "wget -O - \"https://connect.opensuse.org/services/api/rest/xml/?method=connect.exmembersadmin.mails&api_key=$CONNECT_KEY\"" | grep -v '^<' >  maildump
    ssh $CONNECT_HOST "wget -O - \"https://connect.opensuse.org/services/api/rest/xml/?method=connect.membersadmin.mails&api_key=$CONNECT_KEY\""   | grep -v '^<' >> maildump
}

START="`date +%s`"

get_mail_dump
get_mboxes

while read ln; do
    USER="`echo "$ln" | sed 's|^\([^\|]*\)\ \|.*|\1|'`"
    CMAIL="`echo "$ln" | sed 's|^\([^\|]*\)\ \|\ \([^\|]*\)\ .*|\2|'`"
    MAILS="`echo "$ln" | sed 's|.*\|\ \([^\|]*\)$|\1|' | tr ' ' "\n" | sort -u`"
    [ x"$USER" \!= xopensuse-bot ] || continue
    LAST_ACTIVE="`last_active $CMAIL $MAILS`"
    LAST_MAIL_ACTIVE="`echo $LAST_ACTIVE | cut -f 2 -d :`"
    LAST_ACTIVE="`echo $LAST_ACTIVE | cut -f 1 -d :`"
    touch 1st-warnings 2nd-warnings kicked
    MAILS_TEXT="`for i in $CMAIL $MAILS; do echo " * $i"; done`"
    if [ $LAST_ACTIVE -gt $FIRST_DATE ]; then
        echo $USER is active
        [ -n "$SEND" ] || continue
        if [ -n "`grep "|$CMAIL\$" 1st-warnings 2nd-warnings kicked`" ]; then
		echo $USER was inactive before
		echo $CMAIL >> to_unkick.txt
	fi
        sed -i "/|$CMAIL\$/ d" 1st-warnings
        sed -i "/|$CMAIL\$/ d" 2nd-warnings
        if [ -n "`grep "|$CMAIL\$" kicked`" ] && [ $LAST_MAIL_ACTIVE -gt $FIRST_DATE ]; then
            if [ -z "$SEND" ]; then
                echo "User $USER would be restored"
            else
                echo "Restoring membership"
                sed -i "/|$CMAIL\$/ d" kicked
                restore "$USER"
                cat welcome | sed "s|@nick@|$USER|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
            fi
        fi
    else
        echo $USER is inactive
        if [ -z "`grep "|$USER|" 1st-warnings`" ]; then
            if [ -z "$SEND" ]; then
                echo $USER would get 1st warning
            else
                echo "Sending first warning"
                cat 1st-warning | sed -e "s|@nick@|$USER|g" -e "s|@mails@|$MAILS_TEXT|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
                echo "`date +%s`|1|$USER|$CMAIL" >> 1st-warnings
            fi
            continue
        fi
        LAST="`sed -n "s/|1|$USER|$CMAIL//p" 1st-warnings`"
        LAST="`expr $LAST + $ND_WAR`"
        if [ $NOW_S -gt $LAST ] && [ -z "`grep "|$USER|" 2nd-warnings`" ] && [ "`grep "|$USER|" 1st-warnings`" ]; then
            if [ -z "$SEND" ]; then
                echo $USER would get 2nd warning
            else
                echo "Sending second warning"
                cat 2nd-warning | sed -e "s|@nick@|$USER|g" -e "s|@mails@|$MAILS_TEXT|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
                echo "`date +%s`|1|$USER|$CMAIL" >> 2nd-warnings
            fi
            continue
        fi
        LAST="`sed -n "s/|1|$USER|$CMAIL//p" 2nd-warnings`"
        LAST="`expr $LAST + $KICK`"
        if [ $NOW_S -gt $LAST ] && [ -z "`grep "|$USER|" kicked`" ] && [ "`grep "|$USER|" 2nd-warnings`" ]; then
            if [ -z "$SEND" ]; then
                echo $USER would get kicked out
            else
                echo "Kicking out"
                cat kick | sed -e "s|@nick@|$USER|g" -e "s|@mails@|$MAILS_TEXT|g" | msmtp -a opensuse-bot -f opensuse-bot@opensuse.org $CMAIL
                echo "`date +%s`|1|$USER|$CMAIL" >> kicked
                kick "$USER"
            fi
            continue
        fi
    fi
done < maildump

STOP="`date +%s`"

echo Finished in `expr $STOP - $START`s
