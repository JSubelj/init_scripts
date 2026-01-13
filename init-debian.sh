#!/bin/bash
set -e

share_dir="/share"
host_share_dir="/nfs/share"
ip_host="10.6.10.95"
read -p "Enter the folder to install the script (default: $PWD): " install_folder
# Use the default folder if the user doesn't provide one
install_folder=${install_folder:-$PWD}

if [ "$EUID" -ne 0 ]; then
    sudo_prefix="sudo"
else
    sudo_prefix=""
fi


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
    echo "Getting email done"
    echo ""
}

install_advcp() {
    curl https://raw.githubusercontent.com/jarun/advcpmv/master/install.sh --create-dirs -o /tmp/advcpmv/install.sh && (cd /tmp/advcpmv && FORCE_UNSAFE_CONFIGURE=1 sh install.sh)
    /bin/cp /tmp/advcpmv/advcp /tmp/advcpmv/advmv /usr/local/bin  
    cd -
    /bin/rm -rf /tmp/advcpmv
    $sudo_prefix apt --purge autoremove patch gcc build-essential
}

# Function to install necessary packages
install_packages() {
    $sudo_prefix apt update
    $sudo_prefix apt install -y vim sudo zsh git curl rsync unzip python-is-python3 patch gcc build-essential
    install_advcp
    echo "Package install done"
    echo ""
}

# Function to configure email
configure_email() {
    get_email
    read -p "Select Internet Site and enter your hostname. Press enter to continue..."
    $sudo_prefix apt install libsasl2-modules postfix mailutils postfix-pcre
    $sudo_prefix cp /etc/postfix/main.cf $install_folder/.scripts/old
    read -p "Input valid gmail sender email: " email_sender
    read -p "Generate app password and post it (https://security.google.com/settings/security/apppasswords): " app_password_email
    $sudo_prefix sh -c "echo '[smtp.gmail.com]:587 $email_sender:$app_password_email' > /etc/postfix/sasl/sasl_passwd"
    $sudo_prefix postmap /etc/postfix/sasl/sasl_passwd
    $sudo_prefix chown root:root /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
    $sudo_prefix chmod 0600 /etc/postfix/sasl/sasl_passwd /etc/postfix/sasl/sasl_passwd.db
    $sudo_prefix sed -i '/^relayhost =/d' /etc/postfix/main.cf
    $sudo_prefix sh -c "echo 'relayhost = [smtp.gmail.com]:587' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_sasl_auth_enable = yes' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_sasl_security_options = noanonymous' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_sasl_password_maps = hash:/etc/postfix/sasl/sasl_passwd' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_tls_security_level = encrypt' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt' >> /etc/postfix/main.cf"
    $sudo_prefix sh -c "echo 'smtp_header_checks = pcre:/etc/postfix/smtp_header_checks' >> /etc/postfix/main.cf"
    # to rename from username to hostname
    $sudo_prefix sh -c "echo '/^From:.*/ REPLACE From: $HOSTNAME <$email_sender>' >> /etc/postfix/smtp_header_checks"
    
    $sudo_prefix systemctl restart postfix
    echo "Mail config succeeded" | mail -s "Mail config successful" $email_address
    echo ""
}

# Function to configure unattended upgrades
configure_unattended_upgrades() {
    $sudo_prefix apt install -y unattended-upgrades apt-listchanges
    $sudo_prefix dpkg-reconfigure -plow unattended-upgrades

    if $sudo_prefix cat /etc/postfix/main.cf | grep -q "[smtp.gmail.com]"; then
        read -p "Do you want to get an email when system upgrades (y/N)? " configure_email
        if [ "$configure_email" == "Y" ] || [ "$configure_email" == "y" ]; then
            get_email
            $sudo_prefix cp /etc/apt/apt.conf.d/50unattended-upgrades $install_folder/.scripts/old
            $sudo_prefix sh -c "sed -i 's/Unattended-Upgrade::Mail \"root\";/Unattended-Upgrade::Mail \"$email_address\";/' /etc/apt/apt.conf.d/50unattended-upgrades"
        fi
    fi

    echo "If you want to change the time (default 6.00) of the upgrade, change the file"
    echo "'/lib/systemd/system/apt-daily-upgrade.timer'"
    echo "And run: 'systemctl daemon-reload && systemctl restart apt-daily-upgrade.timer'"
    echo ""
}

# Function to install and configure zsh
install_and_configure_zsh() {
    echo "To install oh my zsh run this command:"
    echo ""
    echo 'sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"'
    echo ""
}

enable_nfs_share(){
    read -p "Check NFS share (y/N)?" check_nfs
    if [ "$check_nfs" == "y" ] || [ "$check_nfs" == "Y" ]; then
    if [ -d "$share_dir" ] && [ -f "$share_dir/permanent.txt" ]; then
        echo "Share is mounted correctly"
    else
           if $sudo_prefix cat /proc/1/environ | tr \\0 \\n | grep -q "container=lxc"; then
            echo "Container is CT"
            echo "Share is not mounted correctly"
            echo "On the host, run 'pct set <id-ct> -mp0 $host_share_dir,mp=$share_dir'"
    
        else
            $sudo_prefix cp /etc/fstab $install_folder/.scripts/old
            echo "Container is VM"
            $sudo_prefix apt install nfs-common
            $sudo_prefix mkdir -p $share_dir
            $sudo_prefix sh -c "echo '$ip_host:$host_share_dir $share_dir nfs defaults 0 0' >> /etc/fstab"
            $sudo_prefix systemctl daemon-reload
            $sudo_prefix mount -a
            fi
        fi
    fi
    echo ""
}

# Function to complete the installation
install_rcs() {
    get_email
    echo "If you want to add scripts that are in your path, add them to .scripts/bin"
    echo "If you want additional rc commands to run, add them to ~/.script/.zshrc_ext"

    # Ensure directories exist
    mkdir -p "$install_folder/.scripts"

    curl -s https://raw.githubusercontent.com/JSubelj/init_scripts/main/.aliases -o "$install_folder/.scripts/.aliases"
    curl -s https://raw.githubusercontent.com/JSubelj/init_scripts/main/.zshrc_init -o "$install_folder/.scripts/.zshrc_init"
    touch "$install_folder/.scripts/.zshrc_ext"

    # 1. Update EMAIL in .zshrc_init (Overwrites/Updates instead of appending)
    if grep -q "EMAIL=" "$install_folder/.scripts/.zshrc_init"; then
        sed -i "s|^EMAIL=.*|EMAIL='$email_address'|" "$install_folder/.scripts/.zshrc_init"
    else
        echo "EMAIL='$email_address'" >> "$install_folder/.scripts/.zshrc_init"
    fi

    # 2. Source the init script in .zshrc (Append if missing)
    LINE_TO_SOURCE=". $install_folder/.scripts/.zshrc_init"
    grep -qxF "$LINE_TO_SOURCE" "$install_folder/.zshrc" || echo "$LINE_TO_SOURCE" >> "$install_folder/.zshrc"

    # 3. Update ZSH_THEME (Standard sed replacement is usually safe to run twice)
    sed -i "s/^ZSH_THEME=.*/ZSH_THEME='alanpeabody'/" "$install_folder/.zshrc"

    # 4. Add DISABLE_UPDATE_PROMPT to the beginning (if missing)
    DISABLE_LINE='DISABLE_UPDATE_PROMPT=true'
    if ! grep -qxF "$DISABLE_LINE" "$install_folder/.zshrc"; then
        sed -i "1i $DISABLE_LINE" "$install_folder/.zshrc"
    fi

    echo "Script completed successfully."
    echo ""
}

undo_fstab(){
    if [ -f "$install_folder/.scripts/old/fstab" ]; then
        $sudo_prefix cp $install_folder/.scripts/old/fstab /etc/fstab
        $sudo_prefix systemctl daemon-reload
        $sudo_prefix mount -a
    fi
}

undo_postfix_main(){
    if [ -f "$install_folder/.scripts/old/main.cf" ]; then
        $sudo_prefix cp $install_folder/.scripts/old/main.cf /etc/postfix/main.cf
    fi
}

undo_50unattended-upgrades(){
    if [ -f "$install_folder/.scripts/old/50unattended-upgrades" ]; then
        $sudo_prefix cp $install_folder/.scripts/old/50unattended-upgrades /etc/apt/apt.conf.d/50unattended-upgrades
    fi
}

mkscriptsdir

# Main script
PS3="Select a function to run (or '7' to run all or '11' to exit): "
options=("Install Packages" "Configure Email" "Configure Unattended Upgrades" "Install and Configure Zsh" "Install_rcs" "Enable Nfs Share" "Run all" "Undo fstab changes" "Undo postfix main.cf changes" "Undo unattended-upgrades changes" "Exit")
select opt in "${options[@]}"; do
    case $REPLY in
        1) install_packages;;
        2) configure_email;;
        3) configure_unattended_upgrades;;
        4) install_and_configure_zsh;;
        5) install_rcs;;
        6) enable_nfs_share;;
        7) 
            install_packages
            configure_email
            configure_unattended_upgrades
            enable_nfs_share
            install_rcs
            install_and_configure_zsh
            exit 0;;
        8) undo_fstab;;
        9) undo_postfix_main.cf;;
        10) undo_50unattended-upgrades;;
        11) exit 0;;
        
        *) echo "Invalid option";;
    esac
done
