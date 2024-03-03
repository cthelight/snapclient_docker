#! /bin/sh

# Check if user requested dump of available audio devices.
# If so, dump them (via snapclient) and exit
if [ "$LIST_DEVICES_AND_EXIT" = "true" ]; then
    echo "Listing all available sound devices.."
    snapclient -l
    exit $?
fi

# We currently require a server host to be specified to snapclient
# If one is not specified, abort now. (NOT YET SET is a quick and dirty default value to check for overrides)
if [ "$SNAPSERVER" = "NOT YET SET" ]; then
    echo 1>&2 "Must specify the snapserver to connect to. Aborting..."
    exit 1
fi

# Given the volitility of identifiable information in docker containers, we allow specifying a specific identifier
# If one is not specified, let snapclient pick. (NOT YET SET is a quick and dirty default value to check for overrides)
if ! [ "$CLIENT_HOST_ID" = "NOT YET SET" ]; then
    HOST_ID="--hostID $CLIENT_HOST_ID"
else
    HOST_ID=""
fi

# Actually run the client with the info provided
snapclient  -s "$SND_DEVICE" -h "$SNAPSERVER" -p "$SNAPSERVER_PORT" $HOST_ID
