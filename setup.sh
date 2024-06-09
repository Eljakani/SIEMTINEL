#!/bin/bash

# Function to display project name using figlet
show_project_name() {
    clear
    # check if figlet is installed
    if ! [ -x "$(command -v figlet)" ]; then
        sudo apt install figlet -y >/dev/null 2>&1
    fi
    figlet "SIEMTINEL" -f slant
    echo -e "\e[34mSIEMTINEL - A Cloud-Based SIEM\e[0m"
}
show_whenfinished() {
    echo -e "\e[34m[+] The setup is complete. Please visit the controller at http://$CONTROLLER_IP:5601\e[0m"
}

# Function to show a spinner while a command is running
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

# Function to install suricata and copy the suricata.yml file
install_suricata() {
    DISTRO=$(detect_distro)
    echo -e "\e[34m[+] Installing prerequisites...\e[0m"
    sudo apt install wget curl nano software-properties-common dirmngr apt-transport-https gnupg gnupg2 ca-certificates lsb-release ubuntu-keyring unzip -y >/dev/null 2>&1 & spinner
    echo -e "\e[34m[+] Adding Suricata PPA...\e[0m"
    sudo add-apt-repository ppa:oisf/suricata-stable -y >/dev/null 2>&1 & spinner
    echo -e "\e[34m[+] Updating package list...\e[0m"
    sudo apt-get update >/dev/null 2>&1 & spinner
    echo -e "\e[34m[+] Installing Suricata...\e[0m"
    sudo apt-get install suricata -y >/dev/null 2>&1 & spinner
    sudo systemctl enable suricata >/dev/null 2>&1
    sudo systemctl stop suricata >/dev/null 2>&1
    sudo sed -i 's/# community-id: false/community-id: true/g' /etc/suricata/suricata.yaml
    sudo sed -i 's/# pcap:/pcap:/g' /etc/suricata/suricata.yaml
    sudo sed -i "s/interface: eth0/interface: $interface/g" /etc/suricata/suricata.yaml
    sudo sed -i 's/# use-mmap: yes/use-mmap: yes/g' /etc/suricata/suricata.yaml
    sudo suricata-update >/dev/null 2>&1
    sudo suricata-update list-sources >/dev/null 2>&1
    echo -e "\e[34m[+] Enabling Wazuh rules...\e[0m"
    sudo suricata-update enable-source tgreen/hunting >/dev/null 2>&1
    sudo suricata -T -c /etc/suricata/suricata.yaml -v >/dev/null 2>&1
    sudo systemctl start suricata >/dev/null 2>&1
}

suricata_network_setup() {
    sudo ip link set $interface multicast off >/dev/null 2>&1
    sudo ip link set $interface promisc on >/dev/null 2>&1
    sudo ip link set $interface up >/dev/null 2>&1
}

is_valid_interface() {
    local interface="$1"
    ip link show "$interface" >/dev/null 2>&1
}

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

install_docker() {
    DISTRO=$(detect_distro)
    case "$DISTRO" in
        "ubuntu" | "debian")
            echo -e "\e[34m[+] Installing Docker...\e[0m"
            sudo apt-get update >/dev/null 2>&1 & spinner
            sudo apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common >/dev/null 2>&1 & spinner
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add - >/dev/null 2>&1 & spinner
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" -y >/dev/null 2>&1 & spinner
            sudo apt-get update >/dev/null 2>&1 & spinner
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose >/dev/null 2>&1 & spinner
            ;;
        "centos" | "rhel")
            echo -e "\e[34m[+] Installing Docker...\e[0m"
            sudo yum install -y yum-utils >/dev/null 2>&1 & spinner
            sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo >/dev/null 2>&1 & spinner
            sudo yum install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 & spinner
            ;;
        "fedora")
            echo -e "\e[34m[+] Installing Docker...\e[0m"
            sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo >/dev/null 2>&1 & spinner
            sudo dnf install -y docker-ce docker-ce-cli containerd.io >/dev/null 2>&1 & spinner
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

install_latest_filebeat() {
    DISTRO=$(detect_distro)
    VERSION=$(grep ELASTIC_VERSION .env | cut -d '=' -f2)
    case "$DISTRO" in
        "ubuntu" | "debian")
            echo -e "\e[34m[+] Downloading Filebeat...\e[0m"
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-amd64.deb >/dev/null 2>&1 & spinner
            echo -e "\e[34m[+] Installing Filebeat...\e[0m"
            sudo dpkg -i filebeat-$VERSION-amd64.deb >/dev/null 2>&1 & spinner
            ;;
        "centos" | "rhel" | "fedora")
            echo -e "\e[34m[+] Downloading Filebeat...\e[0m"
            curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1 & spinner
            echo -e "\e[34m[+] Installing Filebeat...\e[0m"
            sudo rpm -vi filebeat-$VERSION-x86_64.rpm >/dev/null 2>&1 & spinner
            ;;
        *)
            echo "Unsupported distribution: $DISTRO"
            exit 1
            ;;
    esac
}

interactive_setup_filebeat() {
    sudo cp filebeat/filebeat.yml /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_IP/$CONTROLLER_IP/g" /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_USERNAME/$CONTROLLER_USERNAME/g" /etc/filebeat/filebeat.yml
    sudo sed -i "s/CONTROLLER_PASSWORD/$CONTROLLER_PASSWORD/g" /etc/filebeat/filebeat.yml
    sudo sed -i 's/# paths:/paths:/g' /etc/filebeat/filebeat.yml
    sudo sed -i 's/#   - \/var\/log\/*.log/   - \/var\/log\/suricata\/eve.json/g' /etc/filebeat/filebeat.yml
    sudo systemctl enable filebeat >/dev/null
    sudo filebeat modules enable suricata 
    sudo filebeat setup 
    sudo systemctl start filebeat 
}

start_project() {
    sudo docker compose up setup >/dev/null 2>&1 & spinner
    sudo docker compose up -d >/dev/null 2>&1 & spinner
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
            ;;
        2)
            sensor_setup_info
            install_suricata
            suricata_network_setup
            install_latest_filebeat
            interactive_setup_filebeat
            ;;
        *)
            echo "Invalid choice"
            ;;
    esac
}

main
