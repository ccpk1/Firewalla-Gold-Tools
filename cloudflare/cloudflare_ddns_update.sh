# A bash script to update a Cloudflare DNS A record with the external IP of the source machine
# For MultiWAN system, allows specifying/limiting which WAN interface to use for updating external IP
# Using "-f" after the command line will force the update, otherwise script checks if update is required.
# Used to provide DDNS service for my home
# Needs the DNS record pre-creating on Cloudflare

# ********* To make executable: chmod +x cloudflare_ddns_update.sh *********

# Cloudflare zone is the zone which holds the record
ZONE="example.com"
# DNS record is the A record which will be updated
DNS_RECORD="www.example.com"
# Is Cloudflare DNS record proxy enabled?
PROXIED=true
# Cloudflare authentication details, keep these private
CLOUDFLARE_API_TOKEN="<ENTER TOKEN>"
# Specify interface for curl if multi wan otherwise just leave leave empty quotes
INTERFACE="--interface eth0"
# Number of lines in the log file before trunking
LOG_LIMIT=2000

# ** Update Home Assistant - Uncomment the Home Assistant lines here and below if you want to notify HA of external IP updates
#URL="https://ha.example.com/api/webhook/set_wan_one_ip"
#INTERFACE_FOR_HA="--interface 192.168.202.1"

# Setup Logging
DIRECTORY=$(cd `dirname $0` && pwd)
LOG="$DIRECTORY/cloudflare_ddns_update.log"
touch $LOG
echo $LOG
		
TrunkLog () {
	echo "$(tail -n $LOG_LIMIT  $LOG)" > $LOG
}

CURRENT_IP_INFO=$(curl $INTERFACE -s https://ipinfo.io/)
PROVIDER=$(echo $CURRENT_IP_INFO | jq ".org")
CURRENT_IP=$(echo $CURRENT_IP_INFO | jq ".ip" | sed -e 's|"||g')

echo "****************  Begin Update ***************" | tee -a $LOG
echo $(date) "Org: $PROVIDER" | tee -a $LOG
echo $(date) "IP:  $CURRENT_IP" | tee -a $LOG

# get the zone id for the requested zone
ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$ZONE&status=active" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json" | jq -r '{"result"}[] | .[0] | .id') 

echo $(date) "ZoneName: $ZONE" | tee -a $LOG
echo $(date) "ZoneID: $ZONE_ID" | tee -a $LOG

# get the dns record info
DNS_RECORD_INFO=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$DNS_RECORD" \
  -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
  -H "Content-Type: application/json")

DNS_RECORD_ID=$(echo $DNS_RECORD_INFO | jq -r '{"result"}[] | .[0] | .id')
DNS_IP=$(echo $DNS_RECORD_INFO | jq -r '{"result"}[] | .[0] | .content')

echo $(date) "DNSRecordName: $DNS_RECORD" | tee -a $LOG
echo $(date) "DNSRecordID: $DNS_RECORD_ID" | tee -a $LOG
echo $(date) "DNSIP: $DNS_IP" | tee -a $LOG

if [ "$CURRENT_IP" != "$DNS_IP" ] || [ "$1" = "-f" ]; then
    # Perform update if IP's don't match or -f was specified in the command line
    echo $(date) "Status: Update Required" | tee -a $LOG
    RESULT_DATA=$(curl -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$DNS_RECORD_ID" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$CURRENT_IP\"}")

    RESULT=$(echo $RESULT_DATA | jq ".success")

    echo $(date) "UpdateResult: $RESULT" | tee -a $LOG
    
    #** Uncomment lines below to update your Home Assistant (Home Assistant Web Hook must be set up manually)
    #echo $(date) "HomeAssistant: Updating" | tee -a $LOG
    #DATA_STRING="{\"ip\":\"$CURRENT_IP\"}"
    #curl $INTERFACE_FOR_HA --request POST --header "Content-Type: application/json" --data $DATA_STRING $URL
    #echo $(date) "HomeAssistant: Complete" | tee -a $LOG

else
	echo $(date) "Status: No update required" | tee -a $LOG
fi

echo "****************  End Update ***************" | tee -a $LOG
TrunkLog
