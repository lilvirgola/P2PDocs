#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

## Clenup function
function ctrl_c() {
        echo "exiting..."
        echo "Stopping all instances..."
        for ((i=1; i<=NUM_INSTANCES; i++)); do
            INSTANCE="${INSTANCE_NAME}${i}"
            echo "Stopping instance: $INSTANCE"
            docker compose -f ../docker-compose-test.yml --project-name test$i down
        done
        echo "All instances stopped."
        echo "Cleaning up..."
        echo "Removing test scripts..."
        rm connect.sh
        rm disconnect.sh
        echo "Removing shared network..."
        docker network rm $SHARED_NET || echo "Network not found, skipping removal."
        echo "Unsetting environment variables..."
        unset FRONTEND_PORT
        unset NUMBER
        echo "All done."
        echo "Exiting script."
        exit 0
}


if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <number_of_instances>"
    exit 1
fi


NUM_INSTANCES=$1
INSTANCE_NAME="test"
SHARED_NET="p2p_docs_shared_net"

if [ "$NUM_INSTANCES" -lt 1 ]; then
    echo "Number of instances must be at least 1."
    exit 1
fi
echo "creating shared network..."
docker network create $SHARED_NET --subnet=172.16.1.0/24 || echo "Network already exists, skipping creation."
for ((i=1; i<=NUM_INSTANCES; i++)); do
    INSTANCE="${INSTANCE_NAME}${i}"
    echo "Starting instance: $INSTANCE"
    PORT=$((3000 + $i))
    echo "Using port: $PORT"
    export FRONTEND_PORT=$PORT
    export NUMBER=$(($i + 1))
    echo "Using number: $NUMBER"
    docker compose -f ../docker-compose-test.yml --project-name test$i up --build -d
done

echo "All instances started, creating the test scripts..."


echo "Creating disconnect script..."
cat <<EOL > disconnect.sh
#!/bin/bash
if [ "\$#" -ne 1 ]; then
    echo "Usage: $0 <instance_number>"
    exit 1
fi
if [ "\$1" -lt 1 ]||[ "\$1" -gt ${NUM_INSTANCES} ]; then
    echo "This instance does not exist, please provide a number between 1 and ${NUM_INSTANCES}."
    exit 1
fi
INSTANCE="${INSTANCE_NAME}\${1}_backend"
echo "disconnecting \$INSTANCE... form ${SHARED_NET}"
docker network disconnect ${SHARED_NET} \$INSTANCE || echo "Network not found, skipping disconnection."
echo "Done, exiting script."
EOL
chmod +x disconnect.sh

echo "Creating connect script..."

cat <<EOL > connect.sh
#!/bin/bash
if [ "\$#" -ne 1 ]; then
    echo "Usage: $0 <instance_number>"
    exit 1
fi
if [ "\$1" -lt 1 ]||[ "\$1" -gt ${NUM_INSTANCES} ]; then
    echo "This instance does not exist, please provide a number between 1 and ${NUM_INSTANCES}."
    exit 1
fi
INSTANCE="${INSTANCE_NAME}\${1}_backend"
echo "connecting \$INSTANCE... form ${SHARED_NET}"
docker network connect ${SHARED_NET} \$INSTANCE || echo "Network not found, skipping connection."
echo "Done, exiting script."
EOL
chmod +x connect.sh

echo "Test scripts created."


trap ctrl_c INT
echo "Press Ctrl+C to stop."
while true; do
    sleep 1
done