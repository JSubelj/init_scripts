# Init scripts for debian using Proxmox

To run script run 
```
wget https://raw.githubusercontent.com/JSubelj/init_scripts/main/init-debian-pre.sh -O init-debian-pre.sh && . init-debian-pre.sh
```
and then
```
wget https://raw.githubusercontent.com/JSubelj/init_scripts/main/init-debian.sh -O init-debian.sh && chmod +x ./init-debian.sh && ./init-debian.sh; rm ./init-debian.sh; rm ./init-debian-pre.sh; . ~/.zshrc
```

You may need sudo
```
apt update && apt install sudo -y
```
