#!/bin/bash

add_kafka_servers() {
    # Get the Kafka servers from the user
    kafka_servers=$(whiptail --inputbox "Enter the Kafka servers (comma-separated)" 8 78 3>&1 1>&2 2>&3)
    
    # Check if the whiptail command was successful
    if [ $? -eq 0 ]; then
        # Add the Kafka servers to the logstash.conf file in the bootstrap_servers field
        sed -i "s/bootstrap_servers => \"localhost:9092\"/bootstrap_servers => \"$kafka_servers\"/g" /etc/logstash/pipeline.conf
        echo "Kafka servers updated successfully in /etc/logstash/pipeline.conf"
    else
        echo "Operation cancelled by user."
    fi
}

# Run the function
add_kafka_servers
