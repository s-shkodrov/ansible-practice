#!/bin/bash
set -exuo pipefail
service nginx status > /dev/null || echo "nginx must be running"

CONFDIR="/etc/nginx/conf.d"
UPSTREAM_CONFIG="${CONFDIR}/200-upstream.conf"
exitcode=0
service=''
action="enable"

while getopts ":s:w:e?d?h?" opt; do
    case "$opt" in
    d|\?)
        action="disable"
        ;;
    e|\?)
        action="enable"
        ;;
    s)  service=$OPTARG
        ;;
    w)  worker_host=$OPTARG
        ;;
    h|--help) printf "usage: skynet_servicectl.sh -s SERVICE -w WORKER [-pedh] \n"
              printf "OPTIONS:\n"
              printf " -s SERVICE\n"
              printf "   SERVICE - service name in service_tag format OR 'all'\n\n"
              printf " -w WORKER\n"
              printf "   WORKER - worker host_name\n\n"
              printf " -e enable service worker (default)\n\n"
              printf " -d disable service worker\n\n"
              printf " -h, --help print help\n"
              exit 0
        ;;
    esac
done

if [[ -z $service ]]; then
  printf "[CRITICAL] Missing required argument -s. Exiting."
  exit 2
fi

BACKUP=$(mktemp)
cat ${UPSTREAM_CONFIG} > ${BACKUP}

worker=$(dig +short $worker_host | tail -1 | awk '{print $NF}')


if [[ $service == "all" ]]; then
  echo "all services worker=$worker => $action"

  if [[ "$action" == "disable" ]];then
    sed -i "/down;/n;s/$worker:\([0-9]*\)\(.*\);$/$worker:\1\2 down;/" ${UPSTREAM_CONFIG}
  else
    sed -i "s/$worker:\([0-9]*\)\(.*\)\( down\);$/$worker:\1\2;/" ${UPSTREAM_CONFIG}
  fi
else
  echo "service=$service worker=$worker => $action"

  if ! grep -q "$service" "${CONFDIR}/300-services.conf"; then
    echo "no such service $service"
    exit 2
  fi

  #Get port from chef generated fixed-format service conf
  port=$(sed -nr "s/^.*$service:([0-9]+)$/\1/p" "${CONFDIR}/300-services.conf" | head -n1)

  if ! grep -q "$worker:$port" ${UPSTREAM_CONFIG}; then
    echo "no such worker or/and port $worker:$port"
    exit 2
  fi

  if [[ "$action" == "disable" ]];then
    sed -i "/down;/n;s/$worker:$port\(.*\);$/$worker:$port\1 down;/" ${UPSTREAM_CONFIG}
  else
    sed -i "s/$worker:$port\(.*\)\( down\);$/$worker:$port\1;/" ${UPSTREAM_CONFIG}
  fi
fi

if nginx -t 2> /dev/null && service nginx reload ; then
  echo "OK"
  exitcode=0
else
  cp ${BACKUP} ${UPSTREAM_CONFIG}
  echo "ERROR"
  exitcode=1
fi
rm ${BACKUP}

exit $exitcode