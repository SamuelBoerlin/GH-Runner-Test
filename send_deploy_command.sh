host=$1
port=$2
shift 2
status=1
retries=60
finished=0
connected=0
for i in $(seq 1 $retries); do
    if [ "$finished" -ne 0 ]; then break; fi
    if exec 3<>/dev/tcp/${host}/${port} && echo "$@" 1>&3; then
        while IFS= read -r x <&3; do
            if [ ! -z "$x" ]; then
                case "$x" in
                    "EOF") finished=1; break ;;
                    "STATUS: "*) status=${x#????????} ;;
                    *) if [ "$i" -ne 1 ] && [ "$connected" -ne 1 ]; then echo ""; connected=1; fi; echo "$x" ;;
                esac
            else
                break
            fi
        done
        if [ "$i" -ne "$retries" ] && [ "$finished" -eq 0 ]; then
            echo -n "."
            sleep 1
        fi
    else
        echo -n "."
        sleep 1
    fi
done
exec 3<>-
exit $status
