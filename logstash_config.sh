#!/bin/bash

LOGSTASH_CONF="/etc/logstash/pipeline/logstash.conf"

# Function to display the current Kafka bootstrap servers
list_servers() {
    echo "Current Kafka bootstrap servers:"
    grep -oP '(?<=bootstrap_servers => ").*?(?=")' $LOGSTASH_CONF
}

# Function to add a new Kafka bootstrap server
add_server() {
    read -p "Enter the new Kafka IP address: " new_ip
    read -p "Enter the new Kafka port (default is 9093): " new_port
    new_port=${new_port:-9093}

    if grep -q "$new_ip:$new_port" $LOGSTASH_CONF; then
        echo "Server $new_ip:$new_port already exists."
    else
        current_servers=$(grep -oP '(?<=bootstrap_servers => ").*?(?=")' $LOGSTASH_CONF)
        if [ -z "$current_servers" ]; then
            sed -i "s/bootstrap_servers => \".*\"/bootstrap_servers => \"$new_ip:$new_port\"/" $LOGSTASH_CONF
        else
            sed -i "s|bootstrap_servers => \"$current_servers\"|bootstrap_servers => \"$current_servers,$new_ip:$new_port\"|" $LOGSTASH_CONF
        fi
        echo "Server $new_ip:$new_port added."
    fi
}

# Function to remove a Kafka bootstrap server
remove_server() {
    read -p "Enter the Kafka IP address to remove: " remove_ip
    read -p "Enter the Kafka port to remove (default is 9093): " remove_port
    remove_port=${remove_port:-9093}

    if grep -q "$remove_ip:$remove_port" $LOGSTASH_CONF; then
        sed -i "s|$remove_ip:$remove_port,||" $LOGSTASH_CONF
        sed -i "s|,$remove_ip:$remove_port||" $LOGSTASH_CONF
        sed -i "s|$remove_ip:$remove_port||" $LOGSTASH_CONF
        echo "Server $remove_ip:$remove_port removed."
    else
        echo "Server $remove_ip:$remove_port not found."
    fi
}

# Function to get the IP address of the Elasticsearch container
get_elasticsearch_ip() {
    # Replace 'elasticsearch_container_name' with the actual name of your Elasticsearch container
    local container_name="siemtinel-elasticsearch"
    local ip=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $container_name)
    echo $ip
}

# Function to update the Elasticsearch IP address in logstash.conf
update_elasticsearch_ip() {
    local es_ip=$(get_elasticsearch_ip)
    if [ -z "$es_ip" ]; then
        echo "Elasticsearch container not found. Please ensure it is running."
        exit 1
    fi

    echo "[+] Updating Elasticsearch IP address to $es_ip..."
    sed -i "s|hosts => \"http://[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}:[0-9]\{1,5\}\"|hosts => \"http://$es_ip:9200\"|g" $LOGSTASH_CONF
    echo "[+] Elasticsearch IP address updated to $es_ip."
}

# Main menu
while true; do
    echo "1. List Kafka bootstrap servers"
    echo "2. Add a new Kafka bootstrap server"
    echo "3. Remove a Kafka bootstrap server"
    echo "4. Update Elasticsearch IP address"
    echo "5. Exit"
    read -p "Choose an option: " choice

    case $choice in
        1)
            list_servers
            ;;
        2)
            add_server
            ;;
        3)
            remove_server
            ;;
        4)
            update_elasticsearch_ip
            ;;
        5)
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
