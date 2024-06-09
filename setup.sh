#!/bin/bash

# Load figlet for project name
install_figlet() {
    if ! command -v figlet &> /dev/null; then
        sudo apt-get install figlet -y > /dev/null 2>&1
    fi
}

show_project_name() {
    install_figlet
    figlet -c "Project Name"
}

# Function to display a spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Function to print colored messages
print_message() {
    local color=$1
    local message=$2
    echo -e "\033[${color}m${message}\033[0m"
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
    print_message "32" "[+] Installing dependencies..."
    (sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y > /dev/null 2>&1) & spinner
    print_message "32" "[+] Adding Suricata repository..."
    (sudo add-apt-repository ppa:oisf/suricata-stable -y > /dev/null 2>&1) & spinner
    print_message "32" "[+] Updating package list..."
    (sudo apt-get update > /dev/null 2>&1) & spinner
    print_message "32" "[+] Installing Suricata..."
    (sudo apt-get install suricata -y > /dev/null 2>&1) & spinner
    print_message "32" "[+] Enabling and stopping Suricata service..."
    (sudo systemctl enable suricata > /dev/null 2>&1 && sudo systemctl stop suricata > /dev/null 2>&1) & spinner

    # Modify suricata.yaml
    print_message "32" "[+] Configuring Suricata..."
    (sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
    sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml) & spinner

    # Enable Suricata sources
    print_message "32" "[+] Updating Suricata rules..."
    (sudo suricata-update > /dev/null 2>&1 && sudo suricata-update list-sources > /dev/null 2>&1
    sudo suricata-update enable-source tgreen/hunting > /dev/null 2>&1
    sudo suricata -T -c /etc/suricata/suricata.yaml -v > /dev/null 2>&1) & spinner

    print_message "32" "[+] Starting Suricata..."
    (sudo systemctl start suricata > /dev/null 2>&1) & spinner
}

suricata_network_setup() {
    print_message "32" "[+] Setting up network interface..."
    (sudo ip link set $interface multicast off > /dev/null 2>&1
    sudo ip link set $interface promisc on > /dev/null 2>&1
    sudo ip link set $interface up > /dev/null 2>&1) & spinner
}

is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

sensor_setup_info() {
    interfaces=$(ip link show | awk -F': ' '/state UP/ {print $2}')
    print_message "34" "Available network interfaces:"
    select interface in $interfaces; do
        if is_valid_interface "$interface"; then
            print_message "34" "Interface chosen: $interface"
            break
        else
            print_message "31" "Invalid interface. Please try again."
        fi
    done

    if [ -n "$interface" ]; then
        print_message "34" "Continuing with interface: $interface"
    else
        print_message "31" "No valid interface selected. Exiting."
        exit 1
    fi

    CONTROLLER_IP=$(whiptail --inputbox "Enter the IP address of the controller" 8 78 --title "Controller IP" 3>&1 1>&2 2>&3)
    print_message "34" "Controller IP: $CONTROLLER_IP"
    CONTROLLER_USERNAME=$(whiptail --inputbox "Enter the username of the controller" 8 78 --title "Controller Username" 3>&1 1>&2 2>&3)
    print_message "34" "Controller Username: $CONTROLLER_USERNAME"
    CONTROLLER_PASSWORD=$(whiptail --passwordbox "Enter the password of the controller" 8 78 --title "Controller Password" 3>&1 1>&2 2>&3)
    print_message "34" "Controller Password: **"
}

install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            print_message "32" "[+] Installing Docker on Ubuntu/Debian..."
            (sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common > /dev/null 2>&1
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - > /dev/null 2>&1
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /dev/null 2>&1
            sudo apt-get update > /dev/null 2>&1
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose > /dev/null 2>&1) & spinner
            ;;
        "centos" | "rhel")
            print_message "32" "[+] Installing Docker on CentOS/RHEL..."
            (sudo yum install -y yum-utils > /dev/null 2>&1
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo > /dev/null 2>&1
            sudo yum install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1) & spinner
            ;;
        "fedora")
            print_message "32" "[+] Installing Docker on Fedora..."
            (sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo > /dev/null 2>&1
            sudo dnf install -y docker-ce docker-ce-cli containerd.io > /dev/null 2>&1) & spinner
            ;;
        *)
            print_message "31" "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_latest_filebeat() {
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            print_message "32" "[+] Installing Filebeat on Ubuntu/Debian..."
            (curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb > /dev/null 2>&1
            sudo dpkg -i filebeat-$VERSION-amd64.deb > /dev/null 2>&1) & spinner
            ;;
        "centos" | "rhel")
            print_message "32" "[+] Installing Filebeat on CentOS/RHEL..."
            (curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm > /dev/null 2>&1
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm > /dev/null 2>&1) & spinner
            ;;
        "fedora")
            print_message "32" "[+] Installing Filebeat on Fedora..."
            (curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm > /dev/null 2>&1
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm > /dev/null 2>&1) & spinner
            ;;
        *)
            print_message "31" "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

interactive_setup_filebeat() {
    print_message "32" "[+] Configuring Filebeat..."
    (sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml > /dev/null 2>&1
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    sudo systemctl enable filebeat > /dev/null 2>&1
    sudo systemctl start filebeat > /dev/null 2>&1) & spinner
}

start_project() {
    print_message "32" "[+] Starting project..."
    (sudo docker compose up setup > /dev/null 2>&1
    sudo docker compose up -d > /dev/null 2>&1) & spinner
}

install_kafka() {
    print_message "32" "[+] Installing Kafka..."
    (sudo docker build -t siemtinel-bitnami-kafka-server kafka/ > /dev/null 2>&1
    sudo mkdir -p /opt/siemtinel > /dev/null 2>&1
    sudo docker run -d --name kafka-server -p 9092:9092 siemtinel-bitnami-kafka-server -v -v /opt/siemtinel:/bitnami/kafka > /dev/null 2>&1
    sudo docker exec -it kafka-server kafka-topics.sh --create --topic siemtinel --partitions 1 --replication-factor 1 --bootstrap-server localhost:9092 > /dev/null 2>&1) & spinner
}

show_linking_instructions() {
    print_message "34" "To link the sensor to the controller, you need to run the following command on the sensor:"
    print_message "34" "The IP address of the chosen interface is: $(ip -4 addr show $interface | grep -oP '(?<=inet\s)\d+(\.\d+){3}')"
}

install_logstash() {
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            print_message "32" "[+] Installing Logstash on Ubuntu/Debian..."
            (curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-amd64.deb > /dev/null 2>&1
            sudo dpkg -i logstash-$VERSION-amd64.deb > /dev/null 2>&1) & spinner
            ;;
        "centos" | "rhel")
            print_message "32" "[+] Installing Logstash on CentOS/RHEL..."
            (curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-x86_64.rpm > /dev/null 2>&1
            sudo rpm -vi logstash-$VERSION-x86_64.rpm > /dev/null 2>&1) & spinner
            ;;
        "fedora")
            print_message "32" "[+] Installing Logstash on Fedora..."
            (curl -L -O https://artifacts.elastic.co/downloads/logstash/logstash-$VERSION-x86_64.rpm > /dev/null 2>&1
            sudo rpm -vi logstash-$VERSION-x86_64.rpm > /dev/null 2>&1) & spinner
            ;;
        *)
            print_message "31" "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

configure_logstash() {
    print_message "32" "[+] Configuring Logstash..."
    (sudo cp logstash/logstash.yml /etc/logstash/logstash.yml > /dev/null 2>&1
    sudo cp logstash/logstash.conf /etc/logstash/pipeline.conf > /dev/null 2>&1
    sudo systemctl enable logstash > /dev/null 2>&1
    sudo systemctl start logstash > /dev/null 2>&1) & spinner
}

main() {
    show_project_name
    choice=$(whiptail --title "Machine Type" --menu "Is this machine a controller or a sensor?" 15 60 2 \
        "1" "Controller" \
        "2" "Sensor" \
        3>&1 1>&2 2>&3)
    case $choice in
        1)
            install_docker
            start_project
            install_logstash
            configure_logstash
            ;;
        2)
            sensor_setup_info
            install_suricata
            suricata_network_setup
            install_latest_filebeat
            interactive_setup_filebeat
            install_docker
            install_kafka
            show_linking_instructions
            ;;
        *)
            print_message "31" "Invalid choice"
            ;;
    esac
}

main