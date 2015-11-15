#!/bin/bash

if [[ -z "$KAFKA_ADVERTISED_PORT" ]]; then
    export KAFKA_ADVERTISED_PORT=$(docker port `hostname` 9092 | sed -r "s/.*:(.*)/\1/g")
fi
echo "KAFKA_ADVERTISED_PORT=${KAFKA_ADVERTISED_PORT}"

if [[ -z "$KAFKA_BROKER_ID" ]]; then
    export KAFKA_BROKER_ID=$(docker inspect `hostname` | jq --raw-output '.[0] | .Name' | awk -F_ '{print $3}')
fi
echo "KAFKA_BROKER_ID=${KAFKA_BROKER_ID}"

if [[ -z "$KAFKA_LOG_DIRS" ]]; then
    export KAFKA_LOG_DIRS="/kafka/kafka-logs-$KAFKA_BROKER_ID"
fi
echo "KAFKA_LOG_DIRS=${KAFKA_LOG_DIRS}"

if [[ -z "$KAFKA_ZOOKEEPER_CONNECT" ]]; then
    export KAFKA_ZOOKEEPER_CONNECT=$(env | grep ZK.*PORT_2181_TCP= | sed -e 's|.*tcp://||' | paste -sd ,)
fi
echo "KAFKA_ZOOKEEPER_CONNECT=${KAFKA_ZOOKEEPER_CONNECT}"

if [[ -n "$KAFKA_HEAP_OPTS" ]]; then
    sed -r -i "s/(export KAFKA_HEAP_OPTS)=\"(.*)\"/\1=\"$KAFKA_HEAP_OPTS\"/g" $KAFKA_HOME/bin/kafka-server-start.sh
    unset KAFKA_HEAP_OPTS
fi
echo "KAFKA_HEAP_OPTS=${KAFKA_HEAP_OPTS}"

if [[ -z "$KAFKA_ADVERTISED_HOST_NAME" ]]; then
    export KAFKA_ADVERTISED_HOST_NAME=$(hostname -i)
fi
echo "KAFKA_ADVERTISED_HOST_NAME=${KAFKA_ADVERTISED_HOST_NAME}"

for VAR in `env`
do
  if [[ $VAR =~ ^KAFKA_ && ! $VAR =~ ^KAFKA_HOME ]]; then
    kafka_name=`echo "$VAR" | sed -r "s/KAFKA_(.*)=.*/\1/g" | tr '[:upper:]' '[:lower:]' | tr _ .`
    env_var=`echo "$VAR" | sed -r "s/(.*)=.*/\1/g"`
    if egrep -q "(^|^#)$kafka_name=" $KAFKA_HOME/config/server.properties; then
        sed -r -i "s@(^|^#)($kafka_name)=(.*)@\2=${!env_var}@g" $KAFKA_HOME/config/server.properties #note that no config values may contain an '@' char
    else
        echo "$kafka_name=${!env_var}" >> $KAFKA_HOME/config/server.properties
    fi
  fi
done

# Capture kill requests to stop properly
trap "$KAFKA_HOME/bin/kafka-server-stop.sh; echo 'Kafka stopped.'; exit" SIGHUP SIGINT SIGTERM

$KAFKA_HOME/bin/kafka-server-start.sh $KAFKA_HOME/config/server.properties &
KAFKA_SERVER_PID=$!

wait_timeout=600
count=0
while netstat -lnt | awk '$4 ~ /:9092$/ {exit 1}'; do
    sleep 1;
    count=$(expr $count + 1)
    if [ $count -gt $wait_timeout ]; then
        break
    fi
done

if [[ -n $KAFKA_CREATE_TOPICS ]]; then
    IFS=','; for topicToCreate in $KAFKA_CREATE_TOPICS; do
        IFS=':' read -a topicConfig <<< "$topicToCreate"
        $KAFKA_HOME/bin/kafka-topics.sh --create --zookeeper $KAFKA_ZOOKEEPER_CONNECT --replication-factor ${topicConfig[2]} --partition ${topicConfig[1]} --topic "${topicConfig[0]}"
    done
fi
echo "KAFKA_CREATE_TOPICS=${KAFKA_CREATE_TOPICS}"

wait $KAFKA_SERVER_PID
