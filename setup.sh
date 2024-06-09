#!/bin/bash

# Ensure necessary tools are installed
sudo apt-get install -y figlet whiptail tput

# Function to print a banner
print_banner() {
    clear
    figlet "Siem Sentinel"
}

# Function to display status messages with colors
show_message() {
    local color=$1
    local message=$2
    local reset_color="\033[0m"
    echo -e "${color}${message}${reset_color}"
}

# Function to display a spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    tput civis
    while [ "$(ps a | awk '{print $1}' | grep "$pid")" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    tput cnorm
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

# Function to install Suricata
install_suricata() {
    show_message "\033[1;34m" "[+] Installing Suricata and dependencies..."
    {
        sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y >/dev/null 2>&1
        sudo add-apt-repository ppa:oisf/suricata-stable -y >/dev/null 2>&1
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install suricata -y >/dev/null 2>&1
        sudo systemctl enable suricata >/dev/null 2>&1
        sudo systemctl stop suricata >/dev/null 2>&1
        sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml
        sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
        sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml
        sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml
        sudo suricata-update >/dev/null 2>&1
        sudo suricata-update list-sources >/dev/null 2>&1
        sudo suricata-update enable-source tgreen/hunting >/dev/null 2>&1
        sudo suricata -T -c /etc/suricata/suricata.yaml -v >/dev/null 2>&1
        sudo systemctl start suricata >/dev/null 2>&1
    } & spinner
    show_message "\033[1;32m" "[+] Suricata installation completed."
}

# Function to set up network interface
suricata_network_setup() {
    show_message "\033[1;34m" "[+] Setting up network interface..."
    {
        sudo ip link set $interface multicast off
        sudo ip link set $interface promisc on
        sudo ip link set $interface up
    } & spinner
    show_message "\033[1;32m" "[+] Network interface setup completed."
}

# Function to validate network interface
is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

# Function to gather sensor setup information
sensor_setup_info() {
    interfaces=$(ip link show | awk -F': ' '/state UP/ {print $2}')
    echo "Available network interfaces:"
    select interface in $interfaces; do
        if is_valid_interface "$interface"; then
            echo "Interface chosen: $interface"
            break
        else
            echo "Invalid interface. Please try again."
        fi
    done

    if [ -n "$interface" ]; then
        echo "Continuing with interface: $interface"
    else
        echo "No valid interface selected. Exiting."
        exit 1
    fi

    CONTROLLER_IP=$(whiptail --inputbox "Enter the IP address of the controller" 8 78 --title "Controller IP" 3>&1 1>&2 2>&3)
    echo "Controller IP: $CONTROLLER_IP"
    CONTROLLER_USERNAME=$(whiptail --inputbox "Enter the username of the controller" 8 78 --title "Controller Username" 3>&1 1>&2 2>&3)
    echo "Controller Username: $CONTROLLER_USERNAME"
    CONTROLLER_PASSWORD=$(whiptail --passwordbox "Enter the password of the controller" 8 78 --title "Controller Password" 3>&1 1>&2 2>&3)
    echo "Controller Password: **"
}

# Function to install Docker
install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            show_message "\033[1;34m" "[+] Installing Docker..."
            {
                sudo apt-get update >/dev/null 2>&1
                sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common >/dev/null 2>&1
                curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1
                sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y >/dev/null 2>&1
                sudo apt-get update >/dev/null 2>&1
                sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose >/dev/null 2>&1
            } & spinner
            show_message "\033[1;32m" "[+] Docker installation completed."
            ;;
        "centos" | "rhel")
            show_message "\033[1;34m" "[+] Installing Docker..."
            {
                sudo yum install -y yum-utils >/dev/null 2>&1
                sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1
                sudo yum install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
            } & spinner
            show_message "\033[1;32m" "[+] Docker installation completed."
            ;;
        "fedora")
            show_message "\033[1;34m" "[+] Installing Docker..."
            {
                sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo >/dev/null 2>&1
                sudo dnf install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1
            } & spinner
            show_message "\033[1;32m" "[+] Docker installation completed."
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

# Function to install the latest Filebeat
install_latest_filebeat() {
    show_message "\033[1;34m" "[+] Installing Filebeat..."
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    {
        case "$DISTRO" in
            "ubuntu" | "debian")
                curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb >/dev/null 2>&1
                sudo dpkg -i filebeat-$VERSION-amd64.deb >/dev/null 2>&1
                ;;
            "centos" | "rhel")
                curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
                sudo rpm -vi filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
                ;;
            "fedora")
                curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
                sudo rpm -vi filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1
                ;;
            *)
                echo "Unsupported distribution: $DISTRO"
                exit 1
                ;;
        esac
    } & spinner
    show_message "\033[1;32m" "[+] Filebeat installation completed."
}

# Function to set up Filebeat interactively
interactive_setup_filebeat() {
    sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_IP/$CONTROLLER_IP/g" /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_USERNAME/$CONTROLLER_USERNAME/g" /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_PASSWORD/$CONTROLLER_PASSWORD/g" /etc/filebeat/filebeat.yml
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    sudo systemctl enable filebeat
    sudo filebeat modules enable suricata
    sudo filebeat setup
    sudo systemctl start filebeat
}

# Function to start the project using Docker Compose
start_project() {
    sudo docker compose up setup
    sudo docker compose up -d
}

# Function to install Kafka
install_kafka() {
    show_message "\033[1;34m" "[+] Installing Kafka..."
    {
        sudo apt-get update >/dev/null 2>&1
        sudo apt-get install openjdk-8-jdk -y >/dev/null 2>&1
        sudo apt-get install zookeeperd -y >/dev/null 2>&1
        wget https://downloads.apache.org/kafka/3.7.0/kafka_2.12-3.7.0.tgz >/dev/null 2>&1
        tar -xzf 'kafka_2.12-3.7.0.tgz' >/dev/null 2>&1
        cd 'kafka_2.12-3.7.0'
        sudo sed -i 's/clientPort=2181/clientPort=2188/g' config/zookeeper.properties
        sudo sed -i 's/zookeeper.connect=localhost:2181/zookeeper.connect=localhost:2188/g' config/server.properties
        bin/zookeeper-server-start.sh config/zookeeper.properties &
        bin/kafka-server-start.sh config/server.properties &
        bin/kafka-topics.sh --create --topic siemtinel --bootstrap-server localhost:9092
    } & spinner
    show_message "\033[1;32m" "[+] Kafka installation completed."
}

# Main function
main() {
    print_banner
    choice=$(whiptail --title "Machine Type" --menu "Is this machine a controller or a sensor?" 15 60 2 \
        "1" "Controller" \
        "2" "Sensor" \
        3>&1 1>&2 2>&3)
    case $choice in
        1)
            install_docker
            start_project
            ;;
        2)
            sensor_setup_info
            install_suricata
            suricata_network_setup
            install_latest_filebeat
            interactive_setup_filebeat
            install_kafka
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

main
