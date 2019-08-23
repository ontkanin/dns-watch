# dns-watch
**DNS Record Change Monitoring**

The script monitors changes in the DNS zone specified by the config file,
and logs and sends alerts every time there is a change detected. It uses 
AXFR zone transfers for the monitoring and local sendmail or postfix for sending alerts.

## Usage

```
dns-watch.sh [OPTION]
```

```
OPTION:
    -c CONFIG_FILE  configuration INI file for dns-watch.sh
    -h              show this help
```
```
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
    IGNORE_CASE     yes = case insensitive monitoring
                    no  = case sensitive monitoring
    IGNORE_TTL      yes = do not report TTL changes;
                    no  = report TTL changes;
    REPORT_DELETED  yes = report deleted/modified DNS records;
                    no  = do not report deleted/modified DNS records
    REPORT_NEW      yes = report new DNS records;
                    no  = do not report new records
    ZONE_TSIG_KEY   TSIG key for the zone transfer
    ZONE_NAME       name of the DNS zone to monitor
    ZONE_VIEW       name of the DNS view the zone belongs to
```

## Example

**Config file**

```
################################################
## DNS Record Change Monitor Configfile
################################################

ZONE_NAME       = example.com
ZONE_VIEW       = default
ZONE_TSIG_KEY   = default-transfer-linux:L7Ta5zAtXxGEY7qnwRmrqf==
LOG_DIR         = /var/log/dns-watch
NS_AXFR         = xfrout.example.com
RECORD_TYPES    = A,AAAA,CNAME,MX,NS,SRV
IGNORE_CASE     = no
IGNORE_TTL      = no
REPORT_NEW      = yes
REPORT_DELETED  = yes
EMAIL_FROM      = DNS Admin <dns_admin@example.com>
EMAIL_TO        = dns_admin@example.com
EMAIL_CC        = 
EMAIL_BCC       = 
EMAIL_SUBJECT   = 
```

The script must be run from a computer that is allowed to connect to and do a zone transfer (AXFR) with the DNS server, or the config file must contain a TSIG key whitelisted for the zone transfer.

**Crontab**

The script can be run, for example, via cron:

```
*/30 * * * *	/usr/local/bin/dns-watch.sh -c /etc/dns-watch/sample.cfg
```
where you can control the frequency of how often you want to monitor your DNS zone.

