#!/bin/bash

# Function to detect the Linux distribution
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    elif type lsb_release >/dev/null 2>&1; then
        DISTRO=$(lsb_release -si)
    elif [ -f /etc/lsb-release ]; then
        . /etc/lsb-release
        DISTRO=$DISTRIB_ID
    elif [ -f /etc/debian_version ]; then
        DISTRO='Debian'
    else
        DISTRO='Unknown'
    fi
    echo $DISTRO
}
# Function to install suricata and copy the suricata.yml file
install_suricata() {
    DISTRO=$(detect_distro)
    sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y
    sudo add-apt-repository ppa:oisf/suricata-stable -y
    sudo apt-get update
    sudo apt-get install suricata -y
    sudo systemctl enable suricata
    sudo systemctl stop suricata
    # community-id: true in /etc/suricata/suricata.yaml
    sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml
    # find the line pcap: and under it, set the value of the variable interface to the device name for your system
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
    #replace the eth0 with the interface variable chosen by the user in the sensor_setup_info() function
    sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml
    # #use-mmap: yes
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml
    # enable capture-settings
    sudo suricata-update
    sudo suricata-update list-sources
    #TODO add the wazuuh rules
    sudo suricata-update enable-source tgreen/hunting
    sudo suricata -T -c /etc/suricata/suricata.yaml -v
    sudo systemctl start suricata
}


suricata_network_setup(){
    # interface configuration
    sudo ip link set $interface multicast off
    sudo ip link set $interface promisc on
    sudo ip link set $interface up
}
is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

sensor_setup_info(){
    # using whiptail to list all intefaces and make the user choose one to use as sniffer 
    interfaces=$(ip link show | awk -F': ' '/state UP/ {print $2}')
    # choose an interface to use as sniffer
    echo "Available network interfaces:"
    select interface in $interfaces; do
        if is_valid_interface "$interface"; then
            echo "Interface chosen: $interface"
            break
        else
            echo "Invalid interface. Please try again."
        fi
    done

    # If a valid interface is chosen, proceed with the script
    if [ -n "$interface" ]; then
        # Your script logic here
        echo "Continuing with interface: $interface"
    else
        echo "No valid interface selected. Exiting."
        exit 1
    fi
}


# Function to install Docker
install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            sudo apt-get update
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            sudo apt-get update
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose
            ;;
        "centos" | "rhel")
            sudo yum install -y yum-utils
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            sudo yum install -y docker-ce docker-ce-cli containerd.io
            ;;
        "fedora")
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_latest_filebeat() {
    # get the version of filebeat from .env file 
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb
            sudo dpkg -i filebeat-$VERSION-amd64.deb
            ;;
        "centos" | "rhel")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm
            ;;
        "fedora")
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

interactive_setup_filebeat() {
    sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml
    # add /var/log/suricata/eve.json to the paths in filebeat/filebeat.yml
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    # enable and start the filebeat service
    sudo systemctl enable filebeat
    # enable the suricata module
    #sudo filebeat modules enable suricata
    # setup the suricata module
    #sudo filebeat setup
    # start the filebeat service
    sudo systemctl start filebeat

}

start_project() {
    sudo docker compose up setup
    sudo docker compose up -d
}


install_kafka() {
    # build the kafka image
    sudo docker build -t siemtinel-bitnami-kafka-server kafka/
    # make the directory for the kafka data
    sudo mkdir -p /opt/siemtinel
    # run the kafka container
    sudo docker run -d --name kafka-server -p 9092:9092 siemtinel-bitnami-kafka-server -v -v /opt/siemtinel:/bitnami/kafka
    # create the topic siemtinel
    sudo docker exec -it kafka-server kafka-topics.sh --create --topic siemtinel --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092
}
show_linking_instructions() {
    echo "To link the sensor to the controller, you need to run the following command on the sensor:"
    echo "The IP address of the chosen interface is: $(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
}


install_logstash(){
    # get the version of logstash from .env file 
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-amd64.deb
            sudo dpkg -i logstash-$VERSION-amd64.deb
            ;;
        "centos" | "rhel")
            curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-x86_64.rpm
            sudo rpm -vi logstash-$VERSION-x86_64.rpm
            ;;
        "fedora")
            curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-x86_64.rpm
            sudo rpm -vi logstash-$VERSION-x86_64.rpm
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

configure_logstash(){
    sudo cp logstash/logstash.yml /etc/logstash/logstash.yml
    sudo cp logstash/logstash.conf /etc/logstash/pipeline.conf
    sudo systemctl enable logstash
    sudo systemctl start logstash
}
main() {
    choice=$(whiptail --title "Machine Type" --menu "Is this machine a controller or a sensor?" 15 60 2 \
        "1" "Controller" \
        "2" "Sensor" \
        3>&1 1>&2 2>&3)
        case $choice in
            1)
                install_docker
                start_project
                install_logstash
                ;;
            2)
                sensor_setup_info
                install_suricata
                suricata_network_setup
                install_latest_filebeat
                interactive_setup_filebeat
                install_kafka
                show_linking_instructions
                ;;
            *)
                echo "Invalid choice"
                ;;
        esac
}

main
