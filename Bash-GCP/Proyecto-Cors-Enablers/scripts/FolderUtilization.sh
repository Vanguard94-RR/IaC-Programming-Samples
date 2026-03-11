#!/bin/bash

# This script is for monitoring the partition usage at 90%
# And inform the 3 more biggers files inside.

# Vars for SO Monitoring
partition="/tmp"
threshold=30
current=$(df "$partition" | grep "$partition" | awk '{ print $5}' | sed 's/%//g')
filesQuantities=5
filesBiggers=$(find "$partition" -type f -exec du -Sh {} + | sort -rh | head -n "$filesQuantities")

# Vars for Sendgrid
SUBJECT=""
SENDGRID_API_KEY=""
EMAIL_TO=""
FROM_EMAIL=""
FROM_NAME=""
MESSAGE="$(
    echo "Disk Space Alert"
    echo "Your root partition remaining free space is critically low. Used: $current%"
    echo "The files more biggers on the partition ""$partition"" are:"
    echo """$filesBiggers"""
)"

if [[ "$current" -gt "$threshold" ]]; then

    # Embedded python script for sending emails using SendGrid
    REQUEST_DATA='{"personalizations": [{ 
                    "to": [{ "email": "'"$EMAIL_TO"'" }],
                    "subject": "'"$SUBJECT"'" 
                    }],
                    "from": {
                        "email": "'"$FROM_EMAIL"'",
                        "name": "'"$FROM_NAME"'" 
                    },
                    "content": [{
                        "type": "text/plain",
                        "value": "'"$MESSAGE"'"
                    }]
    }'

    curl -X "POST" "https://api.sendgrid.com/v3/mail/send" \
        -H "Authorization: Bearer $SENDGRID_API_KEY" \
        -H "Content-Type: application/json" \
        -d "$REQUEST_DATA"

fi
