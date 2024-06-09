#!/bin/bash

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display a banner
display_banner() {
    echo -e "${PURPLE}"
    figlet "SiemTinel"
    echo -e "${NC}"
}

# Function to display a spinner
display_spinner() {
    local delay=0.1
    local spinner='/-\|'
    local counter=0
    while [ "$counter" -lt "$1" ]; do
        echo -ne "\r${YELLOW}[*]${NC} $2 ${YELLOW}${spinner:$counter:1}${NC}"
        counter=$((counter+1))
        sleep $delay
        counter=$((counter%4))
    done
    echo -e "\r${GREEN}[+]${NC} $2 completed."
}

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
    sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y &> /dev/null
    sudo add-apt-repository ppa:oisf/suricata-stable -y &> /dev/null
    sudo apt-get update &> /dev/null
    sudo apt-get install suricata -y &> /dev/null
    sudo systemctl enable suricata &> /dev/null
    sudo systemctl stop suricata &> /dev/null
    # community-id: true in /etc/suricata/suricata.yaml
    sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml &> /dev/null
    # find the line pcap: and under it, set the value of the variable interface to the device name for your system
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml &> /dev/null
    #replace the eth0 with the interface variable chosen by the user in the sensor_setup_info() function
    sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml &> /dev/null
    # #use-mmap: yes
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml &> /dev/null
    # enable capture-settings
    sudo suricata-update &> /dev/null
    sudo suricata-update list-sources &> /dev/null
    #TODO add the wazuuh rules
    sudo suricata-update enable-source tgreen/hunting &> /dev/null
    sudo suricata -T -c /etc/suricata/suricata.yaml -v &> /dev/null
    sudo systemctl start suricata &> /dev/null
}

suricata_network_setup(){
    # interface configuration
    sudo ip link set $interface multicast off &> /dev/null
    sudo ip link set $interface promisc on &> /dev/null
    sudo ip link set $interface up &> /dev/null
}

is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

sensor_setup_info(){
    # using whiptail to list all interfaces and make the user choose one to use as sniffer 
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
    # ask for the IP address of the controller
    CONTROLLER_IP=$(whiptail --inputbox "Enter the IP address of the controller" 8 78 --title "Controller IP" 3>&1 1>&2 2>&3)
    echo "Controller IP: $CONTROLLER_IP"
    # ask for the username of the controller and the password
    CONTROLLER_USERNAME=$(whiptail --inputbox "Enter the username of the controller" 8 78 --title "Controller Username" 3>&1 1>&2 2>&3)
    echo "Controller Username: $CONTROLLER_USERNAME"
    CONTROLLER_PASSWORD=$(whiptail --passwordbox "Enter the password of the controller" 8 78 --title "Controller Password" 3>&1 1>&2 2>&3)
    # password as **
    echo "Controller Password: **"
}

# Function to install Docker
install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            sudo apt-get update &> /dev/null
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common &> /dev/null
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - &> /dev/null
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" &> /dev/null
            sudo apt-get update &> /dev/null
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose &> /dev/null
            ;;
        "centos" | "rhel")
            sudo yum install -y yum-utils &> /dev/null
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo &> /dev/null
            sudo yum install -y docker-ce docker-ce-cli containerd.io &> /dev/null
            ;;
        "fedora")
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo &> /dev/null
            sudo dnf install -y docker-ce docker-ce-cli containerd.io &> /dev/null
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
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb &> /dev/null
            sudo dpkg -i filebeat-$VERSION-amd64.deb &> /dev/null
            ;;
       "centos" | "rhel")
           curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm &> /dev/null
           sudo rpm -vi filebeat-$VERSION-x86_64.rpm &> /dev/null
           ;;
       "fedora")
           curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm &> /dev/null
           sudo rpm -vi filebeat-$VERSION-x86_64.rpm &> /dev/null
           ;;
       *)
           echo "Unsupported distribution: $DISTRO"
           exit 1
           ;;
   esac
}

interactive_setup_filebeat() {
   sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml &> /dev/null

   sudo sed -i "s/CONTROLLER_IP/$CONTROLLER_IP/g" /etc/filebeat/filebeat.yml &> /dev/null
   # replace CONTROLLER_USERNAME in filebeat/filebeat.yml with the actual username
   sudo sed -i "s/CONTROLLER_USERNAME/$CONTROLLER_USERNAME/g" /etc/filebeat/filebeat.yml &> /dev/null
   # replace CONTROLLER_PASSWORD in filebeat/filebeat.yml with the actual password
   sudo sed -i "s/CONTROLLER_PASSWORD/$CONTROLLER_PASSWORD/g" /etc/filebeat/filebeat.yml &> /dev/null
   # add /var/log/suricata/eve.json to the paths in filebeat/filebeat.yml
   sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml &> /dev/null
   sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml &> /dev/null
   # enable and start the filebeat service
   sudo systemctl enable filebeat &> /dev/null
   # enable the suricata module
   sudo filebeat modules enable suricata &> /dev/null
   # setup the suricata module
   sudo filebeat setup &> /dev/null
   # start the filebeat service
   sudo systemctl start filebeat &> /dev/null
}

start_project() {
   sudo docker compose up setup &> /dev/null
   sudo docker compose up -d &> /dev/null
}

install_kafka() {
   # install java
   sudo apt-get update &> /dev/null
   sudo apt-get install openjdk-8-jdk -y &> /dev/null
   #install zookeeper 
   sudo apt-get install zookeeperd -y &> /dev/null
   # download and extract kafka
   wget https://downloads.apache.org/kafka/3.7.0/kafka_2.12-3.7.0.tgz &> /dev/null
   tar -xzf 'kafka_2.12-3.7.0.tgz' &> /dev/null
   
   cd 'kafka_2.12-3.7.0'

   # in config/zookeeper.properties change the clientPort from 2181 to 2188
   sudo sed -i 's/clientPort=2181/clientPort=2188/g' config/zookeeper.properties &> /dev/null
   
   # in config/server.properties change the zookeeper.connect=localhost:2181 to zookeeper.connect=localhost:2188
   sudo sed -i 's/zookeeper.connect=localhost:2181/zookeeper.connect=localhost:2188/g' config/server.properties &> /dev/null

   # start zookeeper
   bin/zookeeper-server-start.sh config/zookeeper.properties &> /dev/null
   # start kafka
   bin/kafka-server-start.sh config/server.properties &> /dev/null

   # create a topic
   bin/kafka-topics.sh --create --topic siemtinel --bootstrap-server localhost:9092 &> /dev/null
   # list the topics
   bin/kafka-topics.sh --list --bootstrap-server localhost:9092 &> /dev/null
}

main() {
   display_banner

   choice=$(whiptail --title "Machine Type" --menu "Is this machine a controller or a sensor?" 15 60 2 \
       "1" "Controller" \
       "2" "Sensor" \
       3>&1 1>&2 2>&3)
   case $choice in
       1)
           echo -e "${CYAN}[*] Installing Docker...${NC}"
           display_spinner 10 "Installing Docker"
           install_docker
           echo -e "${CYAN}[*] Starting project...${NC}"
           display_spinner 5 "Starting project"
           start_project
           ;;
       2)
           sensor_setup_info

           echo -e "${CYAN}[*] Installing Suricata...${NC}"
           display_spinner 20 "Installing Suricata"
           install_suricata

           echo -e "${CYAN}[*] Setting up Suricata network...${NC}"
           display_spinner 5 "Setting up Suricata network"
           suricata_network_setup

           echo -e "${CYAN}[*] Installing latest Filebeat...${NC}"
           display_spinner 10 "Installing latest Filebeat"
           install_latest_filebeat

           echo -e "${CYAN}[*] Setting up Filebeat...${NC}"
           display_spinner 5 "Setting up Filebeat"
           interactive_setup_filebeat

           echo -e "${CYAN}[*] Installing Kafka...${NC}"
           display_spinner 15 "Installing Kafka"
           install_kafka
           ;;
       *)
           echo -e "${RED}[!] Invalid choice${NC}"
           ;;
   esac
}

main