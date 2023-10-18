if [ "$EUID" -ne 0 ]; then
    sudo_prefix="sudo"
else
    sudo_prefix=""
fi

read -p "Enter the folder to install the script (default: $PWD): " install_folder
# Use the default folder if the user doesn't provide one
install_folder=${install_folder:-$PWD}

if [ "$EUID" -ne 0 ]; then
    sudo_prefix="sudo"
else
    sudo_prefix=""
fi

$sudo_prefix apt update
$sudo_prefix apt install -y vim sudo zsh git curl
echo "Package install done"
echo ""

sh -c "$(wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -O -)"
