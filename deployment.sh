print_usage() {
    echo "usage: $(basename """$0""") [host] [port] [command...]"
}

if [ "$#" -le 2 ]; then
    echo "Incorrect number of arguments"
    print_usage
    exit 1
fi

host=$1
port=$2
shift 2

case $port in
    ''|*[!0-9]*)
        echo "Invalid port '$port'"
        print_usage
        exit 1
        ;;
esac

retries=60

status=1
finished=0
connected=0
errors_file="$(mktemp)"

PSK_KEY_FILE="${PSK_KEY_FILE:-psk.key}"

check_psk_file() {
    [ ! -f "${PSK_KEY_FILE}" ] && echo "Could not find pre-shared key file '${PSK_KEY_FILE}'" >&2 && exit 1
}

read_identity() {
    check_psk_file
    cat "${PSK_KEY_FILE}" | sed 's/:.*//'
}

read_key() {
    check_psk_file
    cat "${PSK_KEY_FILE}" | sed 's/.*://g' | tr -d '\n' | xxd -p
}

[ -z "$(read_identity)" ] && echo "Failed reading pre-shared key identity" >&2 && exit 1
[ -z "$(read_key)" ] && echo "Failed reading pre-shared key" >&2 && exit 1

# Enable extended glob patterns for parsing
shopt -s extglob

connect() {
    # Connects to the deployment server via openssl. Uses a pre-shared key (PSK), consisting
    # of an identity and key, for authorization
    identity=$1
    psk=$2
    openssl s_client -tls1_2 -quiet -verify_quiet -psk_identity $identity -psk $psk -connect ${host}:${port} 2>"$errors_file"
}

for i in $(seq 1 $retries); do
    if [ "$finished" -ne 0 ] || [ "$connected" -ne 0 ]; then break; fi

    # Try opening connection, send command and read response
    while IFS= read -r x 2>"$errors_file"; do
        # Parse response
        case "$x" in
            "${COMMAND_RESPONSE_STATUS:-STATUS}: "@([-]+([0-9])|+([0-9])))
                # Response is exit code of command (by default STATUS: <exit_code>)
                status=${x#????????}
                # If there is no EOF word then consider the command finished
                [ -z "$COMMAND_RESPONSE_EOF" ] && finished=1
                ;;
            *)
                if [ ! -z "$COMMAND_RESPONSE_EOF"] && [ "$x" = "$COMMAND_RESPONSE_EOF" ]; then
                    # Response is EOF word, command has finished
                    finished=1
                else
                    # Output response to stdout
                    if [ "$i" -ne 1 ] && [ "$connected" -ne 1 ]; then
                        echo ""
                    fi
                    echo "$x"
                fi
                ;;
        esac

        connected=1

        if [ "$finished" -ne 0 ]; then break; fi
    done < <(echo "$@" | connect "$(read_identity)" $(read_key)) # Pipe command into openssl connection

    # Something went wrong, try again
    if [ "$finished" -eq 0 ]; then
        connected=0
        echo -n "."
        [ "$i" -ne "$retries" ] && sleep 1
    fi

done

# Print out errors
if [ "$connected" -ne 1 ]; then echo ""; fi
if [ "$finished" -eq 0 ]; then cat "$errors_file" >&2; fi

# Exit with status code in response
exit $status
