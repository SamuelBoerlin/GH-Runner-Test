host=$1
port=$2
shift 2

retries=60

status=1
finished=0
connected=0
errors_file="$(mktemp)"

for i in $(seq 1 $retries); do
    if [ "$finished" -ne 0 ] || [ "$connected" -ne 0 ]; then break; fi

    # Try opening connection and send command
    if exec 2>"$errors_file" 3<>/dev/tcp/${host}/${port} && echo "$@" 1>&3 ; then
        # Read response
        while [ "$finished" -eq 0 ] && IFS= read -r x <&3 2>"$errors_file"; do
            if [ ! -z "$x" ]; then
                case "$x" in
                    "EOF") finished=1 ;;
                    "STATUS: "*) status=${x#????????} ;;
                    *) if [ "$i" -ne 1 ] && [ "$connected" -ne 1 ]; then echo ""; fi; echo "$x" ;;
                esac

                connected=1
            else
                break
            fi
        done

        # Response not yet ready
        if [ "$finished" -eq 0 ]; then
            echo -n "."
            [ "$i" -ne "$retries" ] && sleep 1
        fi
    else
        echo -n "."
        [ "$i" -ne "$retries" ] && sleep 1
    fi
done

# Print out errors
if [ "$connected" -ne 1 ]; then echo ""; fi
if [ "$finished" -eq 0 ]; then cat "$errors_file"; fi

# Close connection
exec 3<&- ; exec 3>&-

# Exit with status code in response
exit $status
