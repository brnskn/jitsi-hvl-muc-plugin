# jitsi-hvl-muc-plugin

# Doc

# Get Active Rooms
**URL** : `/rooms`
**Method** : `GET`
**cURL** : `curl "http://localhost:5280/rooms"`
## Success Responses
**Code** : `200 OK`
**Content** :
```json
[
    {
        "name": "jvbbrewery",
        "jid": "jvbbrewery@internal.auth.jitsi.baran.lab"
    },
    {
        "name": "deneme",
        "jid": "deneme@conference.jitsi.baran.lab"
    }
]
```
# Get Specific Room Detail
**URL** : `http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}`
**Method** : `GET`
**cURL** : `curl "http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}"`
## Success Responses
**Code** : `200 OK`
**Content** :
```json
{
    "room": {
        "jid": "deneme@conference.jitsi.baran.lab",
        "password": "",
        "name": "deneme",
        "conference_duration": 1585752911000
    },
    "occupants": [
        {
            "email": "baransekin@gmail.com",
            "jid": "deneme@conference.jitsi.baran.lab/3c7a5c85",
            "display_name": "baransekin"
        }
    ]
}
```

# Create Room
**URL** : `http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}`
**Method** : `PUT`
**cURL** : `curl -X PUT "http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}"`
## Success Responses
**Code** : `200 OK`

# Destroy Room
**URL** : `http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}`
**Method** : `DELETE`
**cURL** : `curl -X PUT "http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}"`
## Success Responses
**Code** : `200 OK`

# Change Room Password
**URL** : `http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}&password={PASSWORD}`
**Method** : `PATCH`
**cURL** : `curl -X PUT "http://localhost:5280/room?room={ROOM_NAME}&domain={DOMAIN}&password={PASSWORD}"`
## Success Responses
**Code** : `200 OK`