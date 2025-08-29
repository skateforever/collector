kill_collector(){
    for pid in $(ps aux | grep "${1::1}${1:1}" | awk '{print $2}'); do
        kill -9 "${pid}" > /dev/null 2>&1
    done
    exit 0
}
