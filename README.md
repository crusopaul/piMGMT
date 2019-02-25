# piMGMT.sh
A script I wrote to easily reconfigure pi-hole and stubby on my raspberry pi (in case my sd card dies again).

# Usage
piMGMT.sh uses dialog, as opposed whiptail, for its text-based GUI. To get it running:
````
sudo apt-get install dialog
wget https://github.com/crusopaul/piMGMT/raw/master/piMGMT.sh
chmod +x piMGMT.sh
./piMGMT.sh
````

# Warning
This script hasn't been tested thoroughly so the automated configuration of /etc/stubby.yml might fail to be loaded by the stubby service. If this happens, feel free to manually edit /etc/stubby.yml. Otherwise, updating pi-hole, stubby, and getdns should run smoothly.
