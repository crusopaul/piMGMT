#!/bin/bash

piManage () {
	sudo raspi-config
}

piholeInstall () {
	if [ -z "$(whereis pihole | sed "s/pihole://")" ]
	then
		curl -sSL https://install.pi-hole.net | bash
	else
		dialog --msgbox "Pi-hole is already installed" 5 32
	fi
}

piholeVersionCheck () {
	piholeNeedsUpdate=false
	versionString=$(pihole -v)
	curPiholeVersion=$(echo "$versionString" | \
		grep "Pi-hole" | \
		sed "s/  Pi-hole version is v//" | \
		sed "s/ .*//")
	latestPiholeVersion=$(echo "$versionString" | \
		grep "Pi-hole" | \
		sed "s/  Pi-hole version is v//" | \
		sed "s/.*Latest: v//" | \
		sed "s/)//")
	if [ ! $curPiholeVersion = $latestPiholeVersion ]
	then
		piholeNeedsUpdate=true
	fi
	
	adminNeedsUpdate=false
	versionString=$(pihole -v)
	curAdminVersion=$(echo "$versionString" | \
		grep "AdminLTE" | \
		sed "s/  AdminLTE version is v//" | \
		sed "s/ .*//")
	latestAdminVersion=$(echo "$versionString" | \
		grep "AdminLTE" | \
		sed "s/  AdminLTE version is v//" | \
		sed "s/.*Latest: v//" | \
		sed "s/)//")
	if [ ! $curAdminVersion = $latestAdminVersion ]
	then
		adminNeedsUpdate=true
	fi
	
	ftlNeedsUpdate=false
	versionString=$(pihole -v)
	curFTLVersion=$(echo "$versionString" | \
		grep "FTL" | \
		sed "s/  FTL version is v//" | \
		sed "s/ .*//")
	latestFTLVersion=$(echo "$versionString" | \
		grep "FTL" | \
		sed "s/  FTL version is v//" | \
		sed "s/.*Latest: v//" | \
		sed "s/)//")
	if [ ! $curFTLVersion = $latestFTLVersion ]
	then
		ftlNeedsUpdate=true
	fi
	
	if [[ $piholeNeedsUpdate = "true" || $adminNeedsUpdate = "true" || $ftlNeedsUpdate = "true" ]]
	then
		dialog --yesno "Updates available, would you like to update?" 5 48
		if [ $? -eq 0 ]
		then
			pihole -up
			dialog --msgbox "Pi-hole updated" 5 19
		fi
	else
		dialog --msgbox "Up to date" 5 14
	fi
}

piholeChangeWebAdminPass () {
	invalidInput=true
	while [ $invalidInput = "true" ]
	do
		password=$(dialog --stdout --insecure --passwordbox "Enter new web admin password:" 8 33)
		if [ $? -eq 0 ]
		then
			invalidInput="false"
		fi
	done
	pihole -a -p $password
	dialog --msgbox "Password set" 5 16
}

piholeChangeDNS () {
	dialog --msgbox "Implementing this feature is difficult, please manually do this with the web admin page." 6 50
}

piholeManageDNSSEC () {
	dialog --msgbox "At the moment, pi-hole will not manage DNSSEC from the command line. Please use the web admin page." 6 54
}

piholeManage () {
	configuringMiddle=true
	while [ $configuringMiddle = "true" ]
	do
		choice=$(dialog --stdout --menu "Please choose an option:" 11 $(tput cols) 5 \
			1 "Install pi-hole" \
			2 "Check for pi-hole updates" \
			3 "Change pi-hole web admin password" \
			4 "Change pi-hole upstream DNS" \
			5 "Enable/Disable pi-hole DNSSEC")
		case $choice in
			1) piholeInstall ;;
			2) piholeVersionCheck ;;
			3) piholeChangeWebAdminPass ;;
			4) piholeChangeDNS ;;
			5) piholeManageDNSSEC ;;
			"") configuringMiddle=false ;;
		esac
	done
}

getAptDependencies () {
	sudo apt update
	sudo apt install build-essential libssl-dev libtool m4 autoconf libev4 libyaml-dev libidn11 libuv1 libevent-core-2.1.6
	dialog --msgbox "Dependencies fetched" 5 24
}

getdnsInstall () {
	newestVersion=$(git ls-remote -h https://github.com/getdnsapi/getdns.git | \
		sed "s/.*refs\/heads\///g" | \
		sed "s/features.*//g" | \
		sed "s/bugfix.*//g" | \
		sed "s/devel.*//g" | \
		sed "s/master//g" | \
		sed "s/release\///g" | \
		sort -hr | \
		uniq | \
		head -n 1)
	git clone --branch release/$newestVersion https://github.com/getdnsapi/getdns.git
	cd getdns
	git submodule update --init
	libtoolize -ci
	autoreconf -fi
	./configure --prefix=/usr/local --enable-stub-only --without-libidn --without-libidn2 --with-ssl --without-stubby
	make
	sudo make install
	cd ..
	rm -rf getdns
	dialog --msgbox "Getdns installed" 5 20
}

getdnsVersionCheck () {
	currentVersion=$(pkg-config --modversion getdns | sed "s/-.*//")
	newestVersion=$(git ls-remote -h https://github.com/getdnsapi/getdns.git | \
		sed "s/.*refs\/heads\///g" | \
		sed "s/features.*//g" | \
		sed "s/bugfix.*//g" | \
		sed "s/devel.*//g" | \
		sed "s/master//g" | \
		sed "s/release\///g" | \
		sort -hr | \
		uniq | \
		head -n 1)
	if [ ! $currentVersion = $newestVersion ]
	then
		dialog --yesno "Update available, would you like to update?" 5 48
		if [ $? -eq 0 ]
		then
			getdnsInstall
			dialog --msgbox "Getdns updated" 5 18
			sudo systemctl restart stubby
		fi
	else
		dialog --msgbox "Up to date" 5 14
	fi
}

stubbyInstall () {
	newestVersion=$(git ls-remote -h https://github.com/getdnsapi/stubby.git | \
		grep -Po "\d\.\d\.\d" | \
		sort -hr | \
		head -n 1 )
	git clone --branch release/$newestVersion https://github.com/getdnsapi/stubby.git
	cd stubby
	autoreconf -fi
	./configure --prefix=/usr/local
	make
	sudo make install
	
	if [ ! -e /etc/stubby.yml ]
	then
		trimLineNumber=$(cat stubby.yml.example | \
			grep -n "############################ DEFAULT UPSTREAMS  ################################" | \
			sed "s/:.*//")
		trimLineNumber=$(expr $trimLineNumber - 1)
		echo "$(cat stubby.yml.example | head -n $trimLineNumber)" > stubby.yml.example
		echo -e "\n#### Custom DNS Servers ####" >> stubby.yml.example
		listenAddressLine=$(cat stubby.yml.example | \
			grep -n "^listen_addresses:" | \
			sed "s/:.*//" | \
			sort -hr | \
			head -n 1)
		echo -e "$(cat stubby.yml.example | head -n $listenAddressLine) \
			\n$(cat stubby.yml.example | tail -n +$(expr $listenAddressLine + 3))" > stubby.yml.example
		sudo install -Dm644 stubby.yml.example /etc/stubby.yml
	fi
	
	if [ ! -e /lib/systemd/system/stubby.service ]
	then
		cd systemd
		echo "[Unit]" > stubby.service
		echo "Description=stubby DNS resolver" >> stubby.service
		echo "Wants=network-online.target" >> stubby.service
		echo -e "After=network-online.target\n" >> stubby.service
		echo "[Service]" >> stubby.service
		echo "ExecStart=/usr/local/bin/stubby -C /etc/stubby.yml -v 7" >> stubby.service
		echo "Restart=on-abort" >> stubby.service
		echo -e "User=root\n " >> stubby.service
		echo "[Install]" >> stubby.service
		echo "WantedBy=multi-user.target" >> stubby.service
		sudo install -Dm644 stubby.service /lib/systemd/system/stubby.service
		cd ..
	fi
	
	if [ ! -e /usr/lib/tmpfiles.d/stubby.conf ]
	then
		sudo install -Dm644 systemd/stubby.conf /usr/lib/tmpfiles.d/stubby.conf
	fi
	
	cd ..
	rm -rf stubby/
	sudo ldconfig -v
	sudo systemctl enable stubby
	dialog --msgbox "Stubby installed" 5 20
}

stubbyVersionCheck () {
	currentVersion=$(stubby -V | sed "s/Stubby //")
	newestVersion=$(git ls-remote -h https://github.com/getdnsapi/stubby.git | \
		grep -Po "\d\.\d\.\d" | \
		sort -hr | \
		head -n 1 )
	if [ ! $currentVersion = $newestVersion ]
	then
		dialog --yesno "Update available, would you like to update?" 5 48
		if [ $? -eq 0 ]
		then
			stubbyInstall
			dialog --msgbox "Stubby updated" 5 18
		fi
	else
		dialog --msgbox "Up to date" 5 14
	fi
}

stubbyChangeDNS () {
	sudo sed -i "s/^  - address_data: /#  - address_data: /g" /etc/stubby.yml
	sudo sed -i "s/^    tls_auth_name: /#    tls_auth_name: /g" /etc/stubby.yml
	sudo sed -i "s/^    tls_pubkey_pinset:/#    tls_pubkey_pinset:/g" /etc/stubby.yml
	sudo sed -i "s/^      - digest: /#      - digest: /g" /etc/stubby.yml
	sudo sed -i "s/^        value: /#        value: /g" /etc/stubby.yml

	dnsNickname=""
	while [ -z $dnsNickname]
	do
		dnsNickname=$(dialog --stdout --inputbox "Please specify a nickname for the upstream DNS" 8 50)
		if [ -z $dnsNickname ]
		then
			dialog --msgbox "A default DNS nickname is required" 5 39
		fi
	done
	
	dnsEntryLineNumber=$(cat /etc/stubby.yml | \
		grep -n "^## $dnsNickname ##" | \
		sed "s/:.*//")
	if [ -n "$dnsEntryLineNumber" ]
	then
		dialog --yesno "Would you like to use the previous settings for this upstream DNS?" 5 70
		if [ $? -eq 0 ]
		then
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			sudo sed -i "${dnsEntryLineNumber}s/^#  - address_data: /  - address_data: /" /etc/stubby.yml
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			sudo sed -i "${dnsEntryLineNumber}s/^#    tls_auth_name: /    tls_auth_name: /" /etc/stubby.yml
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			sudo sed -i "${dnsEntryLineNumber}s/^#    tls_pubkey_pinset:/    tls_pubkey_pinset:/" /etc/stubby.yml
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			sudo sed -i "${dnsEntryLineNumber}s/^#      - digest: /      - digest: /" /etc/stubby.yml
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			sudo sed -i "${dnsEntryLineNumber}s/^#        value: /        value: /" /etc/stubby.yml
			sudo systemctl restart stubby
			dialog --msgbox "Stubby upstream DNS configured and stubby restarted" 5 55
			return 0
		fi
	fi
	
	dnsIP=""
	while [ -z $dnsIP]
	do
		dnsIP=$(dialog --stdout --inputbox "Please type the ip address of your preferred upstream DNS" 8 61)
		if [ -z $dnsIP ]
		then
			dialog --msgbox "A default upstream DNS is required" 5 38
		fi
	done
	
	dnsAuthName=""
	while [ -z $dnsAuthName]
	do
		dnsAuthName=$(dialog --stdout --inputbox "Please type the auth_name of your preferred upstream DNS" 8 60)
		if [ -z $dnsAuthName ]
		then
			dialog --msgbox "A default auth_name is required" 5 38
		fi
	done
	
	dialog --yesno "Does the DNS have a tls_pubkey_pinset" 5 41
	hasPubKey=$?
	digest=""
	checksum=""
	if [ $hasPubKey -eq 0 ]
	then
		while [ -z $digest ]
		do
			digest=$(dialog --stdout --inputbox "What is the digest" 8 23)
			if [ $digest -eq 0 ]
			then
				dialog --msgbox "A default digest is required" 5 32
			fi
		done
		while [ -z $checksum ]
		do
			checksum=$(dialog --stdout --inputbox "What is the checksum" 8 25)
			if [ $checksum -eq 0 ]
			then
				dialog --msgbox "A default checksum is required" 5 35
			fi
		done
	fi
	
	if [ -z "$(cat /etc/stubby.yml | grep "^## $dnsNickname ##")" ]
	then
		sudo dnsNickname="$dnsNickname" bash -c 'echo "## $dnsNickname ##" >> /etc/stubby.yml'
		sudo dnsIP=$dnsIP bash -c 'echo "  - address_data: $dnsIP" >> /etc/stubby.yml'
		sudo dnsAuthName=$dnsAuthName bash -c 'echo "    tls_auth_name: \"$dnsAuthName\"" >> /etc/stubby.yml'
		if [ $hasPubKey -eq 0 ]
		then
			sudo bash -c 'echo "    tls_pubkey_pinset:" >> /etc/stubby.yml'
			sudo digest=$digest bash -c 'echo "      - digest: \"$digest\"" >> /etc/stubby.yml'
			sudo checksum=$checksum bash -c 'echo "        value: $checksum" >> /etc/stubby.yml'
		fi
	else
		dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
		curLine=$(cat /etc/stubby.yml | \
			head -n $dnsEntryLineNumber | \
			tail -n 1)
		if [ -z "$(echo $curLine | grep \"^  - address_data: \")" ]
		then
			sudo dnsEntryLineNumber=$dnsEntryLineNumber dnsIP=$dnsIP bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $dnsEntryLineNumber - 1)) \
				\n$(echo "  - address_data: $dnsIP") \
				\n$(cat /etc/stubby.yml | tail -n +$dnsEntryLineNumber)" > /etc/stubby.yml'
		else
			sudo sed -i "${dnsEntryLineNumber}s/^#  - address_data:.*/  - address_data: $dnsIP/" /etc/stubby.yml
		fi
		
		dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
		curLine=$(cat /etc/stubby.yml | \
			head -n $dnsEntryLineNumber | \
			tail -n 1)
		if [ -z "$(echo $curLine | grep \"^    tls_auth_name: \")" ]
		then
			sudo dnsEntryLineNumber=$dnsEntryLineNumber dnsAuthName=$dnsAuthName bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $dnsEntryLineNumber - 1)) \
				\n$(echo "    tls_auth_name: \"$dnsAuthName\"") \
				\n$(cat /etc/stubby.yml | tail -n +$dnsEntryLineNumber)" > /etc/stubby.yml'
		else
			sudo sed -i "${dnsEntryLineNumber}s/^#    tls_auth_name:.*/    tls_auth_name: \"$dnsAuthName\"/" /etc/stubby.yml
		fi
		
		if [ $hasPubKey -eq 0 ]
		then
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			curLine=$(cat /etc/stubby.yml | \
				head -n $dnsEntryLineNumber | \
				tail -n 1)
			if [ -z "$(echo $curLine | grep \"^    tls_pubkey_pinset:\")" ]
			then
				sudo dnsEntryLineNumber=$dnsEntryLineNumber bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $dnsEntryLineNumber - 1)) \
					\n$(echo "    tls_pubkey_pinset:") \
					\n$(cat /etc/stubby.yml | tail -n +$dnsEntryLineNumber)" > /etc/stubby.yml'
			fi
			
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			curLine=$(cat /etc/stubby.yml | \
				head -n $dnsEntryLineNumber | \
				tail -n 1)
			if [ -z "$(echo $curLine | grep \"^      - digest: \")" ]
			then
				sudo dnsEntryLineNumber=$dnsEntryLineNumber digest=$digest bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $dnsEntryLineNumber - 1)) \
					\n$(echo "      - digest: $digest") \
					\n$(cat /etc/stubby.yml | tail -n +$dnsEntryLineNumber)" > /etc/stubby.yml'
			else
				sudo sed -i "${dnsEntryLineNumber}s/^#      - digest:.*/      - digest: $digest/" /etc/stubby.yml
			fi
			
			dnsEntryLineNumber=$(expr $dnsEntryLineNumber + 1)
			curLine=$(cat /etc/stubby.yml | \
				head -n $dnsEntryLineNumber | \
				tail -n 1)
			if [ -z "$(echo $curLine | grep \"^        value: \")" ]
			then
				sudo dnsEntryLineNumber=$dnsEntryLineNumber checksum=$checksum bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $dnsEntryLineNumber - 1)) \
					\n$(echo "        value: $checksum") \
					\n$(cat /etc/stubby.yml | tail -n +$dnsEntryLineNumber)" > /etc/stubby.yml'
			else
				sudo sed -i "${dnsEntryLineNumber}s/^#        value:.*/        value: $checksum/" /etc/stubby.yml
			fi
		fi
	fi
	sudo systemctl restart stubby
	dialog --msgbox "Stubby upstream DNS configured and stubby restarted" 5 55
}

stubbyChangeListenAddress () {
	listenAddress=""
	while [ -z $listenAddress ]
	do
		listenAddress=$(dialog --stdout --inputbox "Please type stubby's listen address, ports can be specified after a @ character\n\nFor example: 127.0.0.1@2053" 11 46)
		if [ -z $listenAddress ]
		then
			dialog --msgbox "A default listen address is required" 5 40
		fi
	done
	
	listenAddressLine=$(cat /etc/stubby.yml | \
		grep -n "^listen_addresses:" | \
		sed "s/:.*//" | \
		sort -hr | \
		head -n 1)
	listenAddressLine=$(expr $listenAddressLine + 1)
	if [ -z "$(cat /etc/stubby.yml | head -n $listenAddressLine | tail -n 1)" ]
	then
		sudo listenAddressLine="$listenAddressLine" listenAddress="$listenAddress" bash -c 'echo -e "$(cat /etc/stubby.yml | head -n $(expr $listenAddressLine - 1)) \
			\n  - $listenAddress \
			\n$(cat /etc/stubby.yml | tail -n +$listenAddressLine)" > /etc/stubby.yml'
	else
		sudo sed -i "${listenAddressLine}s/^  - .*/  - $listenAddress/" /etc/stubby.yml
	fi
	sudo systemctl restart stubby
	dialog --msgbox "Stubby listen address set" 5 29
}

stubbyManageDNSSEC () {
	dialog --yesno "Do you want DNSSEC?" 5 23
	if [ $? -eq 0 ]
	then
		sudo sed -i "s/^# dnssec: GETDNS_EXTENSION_TRUE/dnssec: GETDNS_EXTENSION_TRUE/" /etc/stubby.yml
		dialog --msgbox "DNSSEC enabled" 5 18
	else
		sudo sed -i "s/^ dnssec: GETDNS_EXTENSION_TRUE/# dnssec: GETDNS_EXTENSION_TRUE/" /etc/stubby.yml
		dialog --msgbox "DNSSEC disabled" 5 19
	fi
	sudo systemctl restart stubby
}

stubbyManage () {
	configuringMiddle=true
	while [ $configuringMiddle = "true" ]
	do
		choice=$(dialog --stdout --menu "Please choose an option:" 13 $(tput cols) 7 \
			1 "Fetch dependencies with apt" \
			2 "Install getdns (dependency of stubby)" \
			3 "Check for getdns updates" \
			4 "Install stubby" \
			5 "Check for stubby updates" \
			6 "Change stubby's upstream DNS" \
			7 "Change stubby's listen address"\
			8 "Enable/Disable stubby DNSSEC")
		case $choice in
			1) getAptDependencies ;;
			2) getdnsInstall ;;
			3) getdnsVersionCheck ;;
			4) stubbyInstall ;;
			5) stubbyVersionCheck ;;
			6) stubbyChangeDNS ;;
			7) stubbyChangeListenAddress ;;
			8) stubbyManageDNSSEC ;;
			"") configuringMiddle=false ;;
		esac
	done
}

main () {
	configuringTop="true"
	while [ $configuringTop = "true" ]
	do
		choice=$(dialog --stdout --menu "Please choose an option:" 9 $(tput cols) 3 \
			1 "Manage raspberry pi" \
			2 "Manage pi-hole" \
			3 "Manage stubby")
		case $choice in
			1) piManage ;;
			2) piholeManage ;;
			3) stubbyManage ;;
			"") configuringTop=false ;;
		esac
	done
}

main
