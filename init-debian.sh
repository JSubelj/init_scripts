#!/bin/bash
set -e

share_dir="/share"
host_share_dir="/share"
ip_host="10.6.10.95"
read -p "Enter the folder to install the script (default: $PWD): " install_folder
# Use the default folder if the user doesn't provide one
install_folder=${install_folder:-$PWD}


mkscriptsdir() {
   mkdir -p $install_folder/.scripts/bin
   mkdir -p $install_folder/.scripts/old
}

get_email(){
    if [ -z "$email_address" ]; then
        # Check if the EMAIL environment variable exists
        if [ -n "$EMAIL" ]; then
            email_address="$EMAIL"
            read -p "Is the stored email ($email_address) correct? (Y/n) " is_correct
            if [ "$is_correct" == "N" ] || [ "$is_correct" == "n" ]; then
                read -p "Input your email: " email_address
            fi
        else
            read -p "Input your email: " email_address
        fi
    fi
}

# Function to install necessary packages
install_packages() {
    sudo apt update
    sudo apt install -y vim sudo zsh git curl
}

# Function to configure email
configure_email() {
    get_email
    sudo cp /etc/postfix/main.cf $install_folder/.scripts/old
    read -p "Select Internet Site and enter your hostname. Press enter to continue..."
    sudo apt install libsasl2-modules postfix mailutils
    read -p "Input valid gmail sender email: " email_sender
    read -p "Generate app password and post it (https://security.google.com/settings/security/apppasswords): " app_password_email
    sudo sh -c "echo '[smtp.gmail.com]:587 $email_sender:$app_password_email' > /etc/postfix/sasl/sasl_passwd"
    sudo postmap /etc/postfix/sasl/sasl_passwd
    sudo chown root:root /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
    sudo chmod 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
    sudo sed -i '/^relayhost =/d' /etc/postfix/main.cf
    sudo sh -c "echo 'relayhost = [smtp.gmail.com]:587' >> /etc/postfix/main.cf"
    sudo sh -c "echo 'smtp_sasl_auth_enable = yes' >> /etc/postfix/main.cf"
    sudo sh -c "echo 'smtp_sasl_security_options = noanonymous' >> /etc/postfix/main.cf"
    sudo sh -c "echo 'smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd' >> /etc/postfix/main.cf"
    sudo sh -c "echo 'smtp_tls_security_level = encrypt' >> /etc/postfix/main.cf"
    sudo sh -c "echo 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt' >> /etc/postfix/main.cf"
    sudo systemctl restart postfix
    echo "Mail config succeeded" | mail -s "Mail config successful" $email_address
}

# Function to configure unattended upgrades
configure_unattended_upgrades() {
    sudo apt install -y unattended-upgrades apt-listchanges
    sudo dpkg-reconfigure -plow unattended-upgrades

    if sudo cat /etc/postfix/main.cf | grep -q "[smtp.gmail.com]"; then
        read -p "Do you want to get an email when system upgrades (y/N)? " configure_email
        if [ "$configure_email" == "Y" ] || [ "$configure_email" == "y" ]; then
            get_email
            sudo cp /etc/apt/apt.conf.d/50unattended-upgrades $install_folder/.scripts/old
            sudo sh -c "sed -i 's/Unattended-Upgrade::Mail \"root\";/Unattended-Upgrade::Mail \"$email_address\";/' /etc/apt/apt.conf.d/50unattended-upgrades"
        fi
    fi

    echo "If you want to change the time (default 6.00) of the upgrade, change the file"
    echo "'/lib/systemd/system/apt-daily-upgrade.timer'"
    echo "And run: 'systemctl daemon-reload && systemctl restart apt-daily-upgrade.timer'"
}

# Function to install and configure zsh
install_and_configure_zsh() {
    read "If you want to continue using the script select No when it prompts you for switching to zsh. Press enter to continue..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

enable_nfs_share(){
    read -p "Check NFS share (y/N)?" check_nfs
    if [ "$check_nfs" == "y" ] || [ "$check_nfs" == "Y" ]; then
	if [ -d "$share_dir" ] && [ -f "$share_dir/permanent.txt" ]; then
		echo "Share is mounted correctly"
	else
   		if sudo cat /proc/1/environ | tr \\0 \\n | grep -q "container=lxc"; then
            echo "Container is CT"
            echo "Share is not mounted correctly"
			echo "On the host, run 'pct set <id-ct> -mp0 $host_share_dir,mp=$share_dir'"
	
        else
            sudo cp /etc/fstab $install_folder/.scripts/old
			echo "Container is VM"
            sudo apt install nfs-common
            sudo mkdir -p $share_dir
            sudo sh -c "echo '$ip_host:$host_share_dir $share_dir nfs defaults 0 0' >> /etc/fstab"
            sudo systemctl daemon-reload
            sudo mount -a
        	fi
    	fi
    fi
}

# Function to complete the installation
install_rcs() {
    echo "If you want to add scripts that are in your path, add them to .scripts/bin"
    echo "If you want additional rc commands to run, add them to ~/.script/.zshrc_ext"

    curl https://raw.githubusercontent.com/JSubelj/init_scripts/main/.aliases -o $install_folder/.scripts/.aliases
    curl https://raw.githubusercontent.com/JSubelj/init_scripts/main/.zshrc_init -o $install_folder/.scripts/.zshrc_init
    touch $install_folder/.scripts/.zshrc_ext

    echo "EMAIL='$email_address'" >> $install_folder/.scripts/.zshrc_init
    echo ". $install_folder/.scripts/.zshrc_init" >> $install_folder/.zshrc
    . $install_folder/.zshrc
    echo "Script completed successfully."
}

mkscriptsdir

# Main script
PS3="Select a function to run (or '7' to run all or '8' to exit): "
options=("Install Packages" "Configure Email" "Configure Unattended Upgrades" "Install and Configure Zsh" "Install_rcs" "Enable Nfs Share" "Undo fstab changes" "Undo postfix main.cf changes" "Undo unattended-upgrades changes" "Exit")
select opt in "${options[@]}"; do
    case $REPLY in
        1) install_packages;;
        2) configure_email;;
        3) configure_unattended_upgrades;;
        4) install_and_configure_zsh;;
        5) install_rcs;;
	    6) enable_nfs_share;;
        8) undo_fstab
        9) undo_postfix_main.cf
        10) undo_50unattended-upgrades
        11) exit 0;;
        7) 
            install_packages
            configure_email
            configure_unattended_upgrades
	        enable_nfs_share
            install_and_configure_zsh
            install_rcs
            exit 0;;
        *) echo "Invalid option";;
    esac
done

