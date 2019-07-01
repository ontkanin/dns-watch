#!/bin/bash
#
# Copyright 2019 Juraj Ontkanin
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

VERSION=0.1.3
SCRIPT_NAME="DNS Record Change Monitor v${VERSION}"

##############################################################################
## Usage
##

usage() {
cat << EOF

$SCRIPT_NAME

The script monitors changes in the DNS zone specified by the config file,
and logs and sends alerts every time there is a change detected. It uses 
AXFR zone transfers for the monitoring and local sendmail for sending alerts.

usage: $(basename $0) [OPTION]

OPTION:

    -c CONFIG_FILE  configuration INI file for $(basename $0)
    -h              show this help

CONFIG FILE:

    EMAIL_FROM      email address of a sender
    EMAIL_TO        email address of a TO recipient
    EMAIL_CC        email address of a CC recipient
    EMAIL_BCC       email address of a BCC recipient
    EMAIL_SUBJECT   subject of the email
    LOG_DIR         directory where to store log file for the DNS zone
    NS_AXFR         NS server to use for the zone transfer
    RECORD_TYPES    comma separated list of the query types
                    for example: A, AAAA, CNAME, MX, NS, SRV
    IGNORE_TTL      yes = do not report TTL changes;
                    no  = report TTL changes;
    REPORT_DELETED  yes = report deleted/modified DNS records;
                    no  = do not report deleted/modified DNS records
    REPORT_NEW      yes = report new DNS records;
                    no  = do not report new records
    ZONE_TSIG_KEY   TSIG key for the zone transfer
    ZONE_NAME       name of the DNS zone to monitor
    ZONE_VIEW       name of the DNS view the zone belongs to

EOF
}

##############################################################################
## Fatal Error
##

fatal_error() {

  echo "--- ERROR: $@" >&2
  echo
  exit 2
}

##############################################################################
## Parse INI file
##

parse_ini() {

  [[ -z $1 ]] && fatal_error "[${FUNCNAME[0]}] missing INI file parameter"
  [[ -z $2 ]] && fatal_error "[${FUNCNAME[0]}] missing INI key parameter"

  egrep -i "^\s*${2}\s*=\s*" "$1" | cut -d= -f2- | xargs
}

##############################################################################
## Email processing
##

send_report_email() {

  (
    # Email headers
    #
    [[ -n $EMAIL_FROM ]] && echo "FROM: ${EMAIL_FROM}"
    [[ -n $EMAIL_TO ]]   && echo "TO: ${EMAIL_TO}"
    [[ -n $EMAIL_CC ]]   && echo "CC: ${EMAIL_CC}"
    [[ -n $EMAIL_BCC ]]  && echo "BCC: ${EMAIL_BCC}"

    echo "Subject: ${EMAIL_SUBJECT}"
    echo 'MIME-Version: 1.0'
    echo 'Content-Type: text/html; charset="UTF-8"'

    echo '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">'
    echo '<html dir="ltr" xml:lang="en" xmlns="http://www.w3.org/1999/xhtml">'
    echo '<head>'
    echo '  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />'
    echo '  <meta name="description" xml:lang="en" content="Notice of Claimed Infringement" />'
    echo '  <meta name="MSSmartTagsPreventParsing" content="TRUE" />'
    echo "  <title>${EMAIL_SUBJECT}</title>"
    echo '  <style type="text/css">'
    echo '  <!--'
    echo '    @media all {'
    echo '      * { padding: 0; margin: 0; }'
    echo '      body { font: normal 90%/1.5em Arial, Helvetica, sans-serif; color: #000; background-color: #fff; padding: 2em; text-align: left; }'
    echo '      h1 { font-size: 1.7em; padding: 0.3em 0 .5em; text-align: center; }'
    echo '      h2 { font-size: 1.3em; padding: 0 0 .5em; }'
    echo '      p { padding: .5em 0; }'
    echo '      li { margin-left: 1.5em; padding-left: .5em; }'
    echo '      a { background-color: #fff; color: #2960a7; }'
    echo '      #wrapper { line-height: 1.8em; }'
    echo '    }'
    echo '  -->'
    echo '  </style>'
    echo '</head>'
    echo '<body xml:lang="en">'

    echo '<div id="wrapper">'
    echo "  <strong>Zone:</strong> $( tr '[:lower:]' '[:upper:]' <<< ${ZONE_NAME} )<br/>"
    echo "  <strong>View:</strong> $( tr '[:lower:]' '[:upper:]' <<< ${ZONE_VIEW} )<br/>"
    echo "  <strong>Date:</strong> ${TIMESTAMP}"
    echo '</div>'

    echo '<p></p>'

    if [[ $SEND_DELETED == 'yes' ]]; then

      echo "<p><strong>The following DNS records have been removed or modified since the last DNS report.</strong></p>"
      echo "<p>If you believe that some of these records should not have been removed or modified, please contact DNS administrators.</p>"
      echo '<p></p>'
      echo '<pre>'

      awk -F# '{ printf "%-35s %-6s %s %s\n", $1,$2,$3,$4 }' <<< "$ZONELOG_DEL"

      echo '</pre>'
      echo '<p></p>'
      echo '</body>'
      echo '</html>'
    fi

    if [[ $SEND_NEW == 'yes' ]]; then

      echo "<p><strong>The following DNS records have been created or modified since the last DNS report.</strong></p>"
      echo "<p>If you believe that some of these records should not have been created or modified, please contact DNS administrators.</p>"
      echo '<p></p>'
      echo '<pre>'

      awk -F# '{ printf "%-35s %-6s %s %s\n", $1,$2,$3,$4 }' <<< "$ZONELOG_NEW"

      echo '</pre>'
      echo '<p></p>'
      echo '</body>'
      echo '</html>'
    fi

  ) | /usr/sbin/sendmail -t -i

}

##############################################################################
## MAIN
##############################################################################


## Make a note about the date and time the script is being run
##

TIMESTAMP="$( date +'%F %T' )"

## Check if 'dig' is installed
##

dig -v 1>/dev/null 2>/dev/null
[[ $? -ne 0 ]] && fatal_error "[main] 'dig' is not installed!"

## Collect OPTIONS and PARAMETERS
##

CONFIGFILE_DEFAULT=""

OPTIND=1

while getopts ":c:h" OPTION; do
  case "$OPTION" in
    c)
      CONFIGFILE="$OPTARG"
      ;;
    h)
      usage
      exit 1
      ;;
    *)
      usage
      fatal_error "[main] unrecognized option or missing argument: -$OPTARG"
      ;;
  esac
done

shift $(($OPTIND - 1))

ARGC=0; ARGS=()
while [[ -n "$1" ]]; do
  ARGS[(( ARGC++ ))]=$1;
  shift
done

case "$ARGC" in
  0)
    ## nothing to do here
    ;;
  *)
    usage
    fatal_error "[main] too many arguments"
    ;;
esac

: ${CONFIGFILE=$CONFIGFILE_DEFAULT}

## Load, normalize and parse INI config file
##

[[ -z "$CONFIGFILE" ]] || [[ ! -f "$CONFIGFILE" ]] && usage && exit 1

EMAIL_FROM="$(      parse_ini "$CONFIGFILE" 'EMAIL_FROM'      )"
EMAIL_TO="$(        parse_ini "$CONFIGFILE" 'EMAIL_TO'        )"
EMAIL_CC="$(        parse_ini "$CONFIGFILE" 'EMAIL_CC'        )"
EMAIL_BCC="$(       parse_ini "$CONFIGFILE" 'EMAIL_BCC'       )"
EMAIL_SUBJECT="$(   parse_ini "$CONFIGFILE" 'EMAIL_SUBJECT'   )"
LOG_DIR="$(         parse_ini "$CONFIGFILE" 'LOG_DIR'         | sed -e 's;/$;;g' )"
NS_AXFR="$(         parse_ini "$CONFIGFILE" 'NS_AXFR'         )"
RECORD_TYPES="$(    parse_ini "$CONFIGFILE" 'RECORD_TYPES'    | tr '[:lower:]' '[:upper:]' | sed -e 's/[[:space:]]*,[[:space:]]*/|/g' )"
IGNORE_TTL="$(      parse_ini "$CONFIGFILE" 'IGNORE_TTL'      | tr '[:upper:]' '[:lower:]' )"
REPORT_DELETED="$(  parse_ini "$CONFIGFILE" 'REPORT_DELETED'  | tr '[:upper:]' '[:lower:]' )"
REPORT_NEW="$(      parse_ini "$CONFIGFILE" 'REPORT_NEW'      | tr '[:upper:]' '[:lower:]' )"
ZONE_TSIG_KEY="$(   parse_ini "$CONFIGFILE" 'ZONE_TSIG_KEY'   )"
ZONE_NAME="$(       parse_ini "$CONFIGFILE" 'ZONE_NAME'       | tr '[:upper:]' '[:lower:]' )"
ZONE_VIEW="$(       parse_ini "$CONFIGFILE" 'ZONE_VIEW'       | tr '[:upper:]' '[:lower:]' )"

## Check config file settings
##

[[ -z "$ZONE_NAME"   ]] && fatal_error "[main] ZONE_NAME not specified!"
[[ -z "$NS_AXFR"     ]] && fatal_error "[main] NS_AXFR not specified!"

if [[ -n "$LOG_DIR" ]]; then
  [[ -e "$LOG_DIR" ]] && [[ ! -d "$LOG_DIR" ]] && fatal_error "[main] LOG_DIR not a directory!"
else
  LOG_DIR='.'
fi

[[ -z "$ZONE_VIEW" ]] && ZONE_VIEW='default'

if [[ -e "${LOG_DIR}/${ZONE_VIEW}" ]]; then
  [[ ! -d "${LOG_DIR}/${ZONE_VIEW}" ]] && fatal_error "[main] ZONE_VIEW not a directory!"
else
  mkdir -p "${LOG_DIR}/${ZONE_VIEW}"
fi

## Get ZONE (AXFR)
##

ZONEFILE_NEW="${LOG_DIR}/${ZONE_VIEW}/${ZONE_NAME}.axfr.new"
ZONEFILE_OLD="${LOG_DIR}/${ZONE_VIEW}/${ZONE_NAME}.axfr"

[[ -z "$ZONE_TSIG_KEY" ]] && AXFR="AXFR" || AXFR="-y $ZONE_TSIG_KEY AXFR"
dig $AXFR $ZONE_NAME @"$NS_AXFR" > "$ZONEFILE_NEW"
RET1=$?

egrep -q '^; Transfer failed' "$ZONEFILE_NEW"
RET2=$?

if [ $RET1 -ne 0 -o $RET2 -eq 0 ]; then
  rm -f "$ZONEFILE_NEW"
  fatal_error "[main] zone transfer for '${ZONE_VIEW}/${ZONE_NAME}' failed!"
fi

## There's no ZONEFILE_OLD in the first run, so there'll be nothing to report
##

if [[ -f "$ZONEFILE_OLD" ]]; then

  ## Normalize old and new zone file, and compare them
  ## 

  if [[ $IGNORE_TTL == 'yes' ]]; then
    ZONE_BUFFER_NEW="$( egrep -v -e "^;" -e "^$" "$ZONEFILE_NEW" | egrep "\sIN\s+(${RECORD_TYPES})\s" | awk '{ out=""; for(i=5;i<=NF;i++) { out=out" "$i }; print $1"##"$4"#"out"#" }' | sed -e 's/\.#/#/g' | sort -u )"
    ZONE_BUFFER_OLD="$( egrep -v -e "^;" -e "^$" "$ZONEFILE_OLD" | egrep "\sIN\s+(${RECORD_TYPES})\s" | awk '{ out=""; for(i=5;i<=NF;i++) { out=out" "$i }; print $1"##"$4"#"out"#" }' | sed -e 's/\.#/#/g' | sort -u )"
  else
    ZONE_BUFFER_NEW="$( egrep -v -e "^;" -e "^$" "$ZONEFILE_NEW" | egrep "\sIN\s+(${RECORD_TYPES})\s" | awk '{ out=""; for(i=5;i<=NF;i++) { out=out" "$i }; print $1"#"$2"#"$4"#"out"#" }' | sed -e 's/\.#/#/g' | sort -u )"
    ZONE_BUFFER_OLD="$( egrep -v -e "^;" -e "^$" "$ZONEFILE_OLD" | egrep "\sIN\s+(${RECORD_TYPES})\s" | awk '{ out=""; for(i=5;i<=NF;i++) { out=out" "$i }; print $1"#"$2"#"$4"#"out"#" }' | sed -e 's/\.#/#/g' | sort -u )"
  fi

  ZONELOG_NEW="$( diff --changed-group-format='%<' --unchanged-group-format='' <( echo "$ZONE_BUFFER_NEW" ) <( echo "$ZONE_BUFFER_OLD" ) | sort )"
  ZONELOG_DEL="$( diff --changed-group-format='%<' --unchanged-group-format='' <( echo "$ZONE_BUFFER_OLD" ) <( echo "$ZONE_BUFFER_NEW" ) | sort )"

  ## Log DNS record changes into changelog, and send mail report if needed
  ##

  CHANGELOG="${LOG_DIR}/${ZONE_VIEW}/${ZONE_NAME}.log"

  SEND_REPORT='no'
  SEND_NEW='no'
  SEND_DELETED='no'
  
  if [[ $( wc -w <<< "$ZONELOG_DEL" ) -gt 0 ]]; then 
    while IFS=# read RECORD RECORD_TTL RECORD_TYPE RECORD_VALUE; do
      RECORD_VALUE="$( xargs <<< "$RECORD_VALUE" | sed -e 's/^"//g' -e 's/"$//g' )"
      echo "${TIMESTAMP}.000 action=\"removed\" zone=\"${ZONE_NAME}\" zone_view=\"${ZONE_VIEW}\" record=\"${RECORD}\" record_ttl=\"${RECORD_TTL}\" record_type=\"${RECORD_TYPE}\" record_value=\"${RECORD_VALUE}\"" >> "$CHANGELOG"
    done <<< "$ZONELOG_DEL"
    [[ $REPORT_DELETED == 'yes' ]] && SEND_REPORT='yes' && SEND_DELETED='yes'
  fi

  if [[ $( wc -w <<< "$ZONELOG_NEW" ) -gt 0 ]]; then
    while IFS=# read RECORD RECORD_TTL RECORD_TYPE RECORD_VALUE; do
      RECORD_VALUE="$( xargs <<< "$RECORD_VALUE" | sed -e 's/^"//g' -e 's/"$//g' )"
      echo "${TIMESTAMP}.001 action=\"added\" zone=\"${ZONE_NAME}\" zone_view=\"${ZONE_VIEW}\" record=\"${RECORD}\" record_ttl=\"${RECORD_TTL}\" record_type=\"${RECORD_TYPE}\" record_value=\"${RECORD_VALUE}\"" >> "$CHANGELOG"
    done <<< "$ZONELOG_NEW"
    [[ $REPORT_NEW == 'yes' ]] && SEND_REPORT='yes' && SEND_NEW='yes'
  fi

  if [[ $SEND_REPORT == 'yes' ]]; then
    [[ -z "$EMAIL_FROM"    ]] && EMAIL_FROM='root'
    [[ -z "$EMAIL_TO"      ]] && [[ -z "$EMAIL_CC" ]] && [[ -z "$EMAIL_BCC" ]] && EMAIL_TO='root'
    [[ -z "$EMAIL_SUBJECT" ]] && EMAIL_SUBJECT="DNS report for $( tr '[:lower:]' '[:upper:]' <<< ${ZONE_NAME} ) in $( tr '[:lower:]' '[:upper:]' <<< ${ZONE_VIEW} ) view"
    send_report_email
  fi
fi

## Cleanup
##

mv "$ZONEFILE_NEW" "$ZONEFILE_OLD"

