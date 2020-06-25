#!/bin/sh
# CakeQOS-Merlin - port for Merlin firmware supported routers
# Site: https://github.com/ttgapers/cakeqos-merlin
# Thread: https://www.snbforums.com/threads/release-cakeqos-merlin.64800/
# Credits: robcore, Odkrys, ttgapers, jackiechun, maghuro, Adamm, Jack Yaz

#########################################################
##               _                                     ##
##              | |                                    ##
##    ___  __ _ | | __ ___          __ _   ___   ___   ##
##   / __|/ _` || |/ // _ \ ______ / _` | / _ \ / __|  ##
##  | (__ |(_| ||   <|  __/|______| (_| || (_) |\__ \  ##
##   \___|\__,_||_|\_\\___|        \__, | \___/ |___/  ##
##                                    | |              ##
##                                    |_|              ##
##                                                     ##
##      https://github.com/ttgapers/cakeqos-merlin     ##
##                                                     ##
#########################################################

# shellcheck disable=SC2086

readonly SCRIPT_VERSION="v1.0.0"
readonly SCRIPT_NAME="cake-qos"
readonly SCRIPT_NAME_FANCY="CakeQOS-Merlin"
readonly SCRIPT_BRANCH="master"
readonly SCRIPT_DIR="/jffs/addons/${SCRIPT_NAME}"
readonly SCRIPT_CFG="${SCRIPT_DIR}/${SCRIPT_NAME}.cfg"

readonly CRIT="\\e[41m"
readonly ERR="\\e[31m"
readonly WARN="\\e[33m"
readonly PASS="\\e[32m"

[ -z "$(nvram get odmpid)" ] && RMODEL=$(nvram get productid) || RMODEL=$(nvram get odmpid) #get router model

if [ -f "$SCRIPT_CFG" ]; then
	. "$SCRIPT_CFG"
fi

Print_Output(){
	if [ "$1" = "true" ]; then
		logger -t "$SCRIPT_NAME_FANCY" "$2"
		printf "\\e[1m$3%s: $2\\e[0m\\n" "$SCRIPT_NAME_FANCY - $SCRIPT_VERSION"
	else
		printf "\\e[1m$3%s: $2\\e[0m\\n" "$SCRIPT_NAME_FANCY - $SCRIPT_VERSION"
	fi
}

git_install() {
	mkdir -p /jffs/addons/cake-qos
	/usr/sbin/curl --retry 3 "https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/"$SCRIPT_BRANCH"/cake-qos.sh" -o "/jffs/addons/cake-qos/cake-qos"
	chmod 0755 /jffs/addons/cake-qos/cake-qos
	sh /jffs/addons/cake-qos/cake-qos install
}

Filter_Version(){
	grep -m1 -oE 'v[0-9]{1,2}([.][0-9]{1,2})([.][0-9]{1,2})'
}

Validate_Bandwidth(){
	if echo "$1" | /bin/grep -oq "^[1-9][0-9]*\.\?[0-9]*$"; then
		return 0
	else
		return 1
	fi
}

Write_Config(){
	{
		printf '%s\n' "##############################################"
		printf '%s\n' "## Generated By Cake - Do Not Manually Edit ##"
		printf '%-43s %s\n' "## $(date +"%b %d %T")" "##"
		printf '%s\n\n' "##############################################"
		printf '%s\n' "## Installer ##"
		printf '%s="%s"\n' "dlspeed" "$dlspeed"
		printf '%s="%s"\n' "upspeed" "$upspeed"
		printf '%s="%s"\n' "queueprio" "$queueprio"
		printf '%s="%s"\n' "extraoptions" "$extraoptions"
		printf '\n%s\n' "##############################################"
	} > "$SCRIPT_CFG"
}

cake_check(){
	STATUS_UPLOAD=$(tc qdisc | grep -E '^qdisc cake .* dev eth0 root')
	STATUS_DOWNLOAD=$(tc qdisc | grep -E '^qdisc cake .* dev ifb9eth0 root')
	if [ -n "$STATUS_UPLOAD" ] && [ -n "$STATUS_DOWNLOAD" ]; then
		return 0
	else
		return 1
	fi
}

cake_download(){
	if [ ! -L "/opt/bin/${SCRIPT_NAME}" ] || [ "$(readlink /opt/bin/${SCRIPT_NAME})" != "${SCRIPT_DIR}/${SCRIPT_NAME}" ]; then
		rm -rf /opt/bin/${SCRIPT_NAME}
		ln -s "${SCRIPT_DIR}/${SCRIPT_NAME}" "/opt/bin/${SCRIPT_NAME}"
	fi

	VERSIONS_ONLINE=$(/usr/sbin/curl -fsL --retry 3 --connect-timeout 3 "https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/versions.txt")
	if [ -n "$VERSIONS_ONLINE" ]; then
		VERSION_LOCAL_CAKE=$(opkg list_installed | grep "^sched-cake-oot - " | awk -F " - " '{print $2}' | cut -d- -f-4)
		VERSION_LOCAL_TC=$(opkg list_installed | grep "^tc-adv - " | awk -F " - " '{print $2}')
		VERSION_ONLINE_CAKE=$(echo "$VERSIONS_ONLINE" | awk -F "|" '{print $1}')
		VERSION_ONLINE_TC=$(echo "$VERSIONS_ONLINE" | awk -F "|" '{print $2}')
		VERSION_ONLINE_SUFFIX=$(echo "$VERSIONS_ONLINE" | awk -F "|" '{print $3}')
		if [ "$VERSION_LOCAL_CAKE" != "$VERSION_ONLINE_CAKE" ] || [ "$VERSION_LOCAL_TC" != "$VERSION_ONLINE_TC" ] || [ ! -f "/opt/lib/modules/sch_cake.ko" ] || [ ! -f "/opt/sbin/tc" ]; then
			case "$RMODEL" in
			RT-AC86U)
				FILE1_TYPE="1"
			;;
			RT-AX88U)
				FILE1_TYPE="ax"
			;;
			*)
				Print_Output "false" "Cake isn't yet compatible with ASUS $RMODEL, keep watching our thread!" "$CRIT"
				exit 1
			;;
			esac
			FILE1="sched-cake-oot_${VERSION_ONLINE_CAKE}-${FILE1_TYPE}_${VERSION_ONLINE_SUFFIX}.ipk"
			FILE2="tc-adv_${VERSION_ONLINE_TC}_${VERSION_ONLINE_SUFFIX}.ipk"
			FILE1_OUT="sched-cake-oot.ipk"
			FILE2_OUT="tc-adv.ipk"
			/usr/sbin/curl -fsL --retry 3 --connect-timeout 3 "https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/${FILE1}" -o "/opt/tmp/${FILE1_OUT}"
			/usr/sbin/curl -fsL --retry 3 --connect-timeout 3 "https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/${FILE2}" -o "/opt/tmp/${FILE2_OUT}"

			if [ -f "/opt/tmp/$FILE1_OUT" ] && [ -f "/opt/tmp/$FILE2_OUT" ]; then
				if [ "$1" = "update" ]; then
					opkg --autoremove remove sched-cake-oot
					opkg --autoremove remove tc-adv
				fi
				/opt/bin/opkg install "/opt/tmp/$FILE1_OUT"
				/opt/bin/opkg install "/opt/tmp/$FILE2_OUT"
				rm "/opt/tmp/$FILE1_OUT" "/opt/tmp/$FILE2_OUT"
			else
				Print_Output "true" "There was an error downloading the cake binaries, please try again." "$ERR"
				exit 1
			fi
		else
			Print_Output "false" "Your cake binaries are up-to-date." "$PASS"
		fi
	fi

	if [ "$1" = "update" ]; then
		REMOTE_VERSION=$(/usr/sbin/curl -fsL --retry 3 https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/${SCRIPT_NAME}.sh | Filter_Version)
		LOCALMD5="$(md5sum "$0" | awk '{print $1}')"
		REMOTEMD5="$(/usr/sbin/curl -fsL --retry 3 https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/${SCRIPT_NAME}.sh | md5sum | awk '{print $1}')"

		if [ -n "$REMOTE_VERSION" ]; then
			if [ "$LOCALMD5" != "$REMOTEMD5" ]; then
				if [ "$SCRIPT_VERSION" != "$REMOTE_VERSION" ]; then
					Print_Output "true" "New CakeQOS-Merlin detected ($REMOTE_VERSION, currently running $SCRIPT_VERSION), updating..." "$WARN"
				else
					Print_Output "true" "Local and server md5 don't match, updating..." "$WARN"
				fi
				/usr/sbin/curl -fsL --retry 3 https://raw.githubusercontent.com/ttgapers/cakeqos-merlin/${SCRIPT_BRANCH}/${SCRIPT_NAME}.sh -o "${SCRIPT_DIR}/${SCRIPT_NAME}"
				chmod 0755 "${SCRIPT_DIR}/${SCRIPT_NAME}"
				exit 0
			else
				Print_Output "false" "You are running the latest $SCRIPT_NAME_FANCY script ($REMOTE_VERSION, currently running $SCRIPT_VERSION), skipping..." "$PASS"
			fi
		fi
	fi
}

cake_start(){

	if [ -z "$dlspeed" ]; then
		Print_Output "true" "Download Speed value missing - Please configure this to proceed" "$WARN"
		exit 1
	elif [ -z "$upspeed" ]; then
		Print_Output "true" "Upload Speed value missing - Please configure this to proceed" "$WARN"
		exit 1
	elif [ -z "$queueprio" ]; then
		Print_Output "true" "Queue Priority value missing - Please configure this to proceed" "$WARN"
		exit 1
	fi

	# Cleanup old script entries
	rm -rf "/jffs/addons/$SCRIPT_NAME.d" 2> /dev/null
	sed -i '\~# cake-qos~d' /jffs/scripts/firewall-start /jffs/scripts/services-start 2>/dev/null

	# Add to nat-start
	if [ ! -f "/jffs/scripts/nat-start" ]; then
		echo "#!/bin/sh" > /jffs/scripts/nat-start
		echo >> /jffs/scripts/nat-start
	elif [ -f "/jffs/scripts/nat-start" ] && ! head -1 /jffs/scripts/nat-start | grep -qE "^#!/bin/sh"; then
		sed -i '1s~^~#!/bin/sh\n~' /jffs/scripts/nat-start
	fi
	if ! grep -qF "${SCRIPT_DIR}/${SCRIPT_NAME} start & # $SCRIPT_NAME_FANCY" /jffs/scripts/nat-start; then
		sed -i '\~# CakeQOS-Merlin~d' /jffs/scripts/nat-start
		echo "${SCRIPT_DIR}/${SCRIPT_NAME} start & # $SCRIPT_NAME_FANCY" >> /jffs/scripts/nat-start
		chmod 0755 /jffs/scripts/nat-start
	fi

	# Add to services-stop
	if [ ! -f "/jffs/scripts/services-stop" ]; then
		echo "#!/bin/sh" > /jffs/scripts/services-stop
		echo >> /jffs/scripts/services-stop
	elif [ -f "/jffs/scripts/services-stop" ] && ! head -1 /jffs/scripts/services-stop | grep -qE "^#!/bin/sh"; then
		sed -i '1s~^~#!/bin/sh\n~' /jffs/scripts/services-stop
	fi
	if ! grep -qF "# CakeQOS-Merlin" /jffs/scripts/services-stop; then
		echo "${SCRIPT_DIR}/${SCRIPT_NAME} stop"' # '"$SCRIPT_NAME_FANCY" >> /jffs/scripts/services-stop
		chmod 0755 /jffs/scripts/services-stop
	fi

	if [ "$(nvram get qos_enable)" = "1" ]; then
		nvram set qos_enable="0"
		nvram save
		service "restart_qos;restart_firewall" >/dev/null 2>&1
		Print_Output "true" "Disabling Asus QOS" "$WARN"
		exit 1
	fi

	entwaretimer="0"
	while [ ! -f "/opt/bin/sh" ] && [ "$entwaretimer" -lt "10" ]; do
		entwaretimer="$((entwaretimer + 1))"
		Print_Output "true" "Entware isn't ready, waiting 10 sec - Attempt #$entwaretimer" "$WARN"
		sleep 10
	done
	if [ "$entwaretimer" -ge "100" ]; then
		Print_Output "true" "Entware didn't start in 100 seconds, please check" "$CRIT"
		exit 1
	fi

	cake_stop

	if [ ! -f "/opt/lib/modules/sch_cake.ko" ] || [ ! -f "/opt/sbin/tc" ]; then
		Print_Output "true" "Cake binaries missing - Exiting" "$CRIT"
		exit 1
	fi

	cru a "$SCRIPT_NAME_FANCY" "*/60 * * * * ${SCRIPT_DIR}/${SCRIPT_NAME} checkrun"

	Print_Output "true" "Starting - settings: ${dlspeed}Mbit | ${upspeed}Mbit | $queueprio | $extraoptions" "$PASS"
	runner disable 2>/dev/null
	fc disable 2>/dev/null
	fc flush 2>/dev/null
	nvram set runner_disable="1"
	nvram commit
	insmod /opt/lib/modules/sch_cake.ko 2>/dev/null
	/opt/sbin/tc qdisc replace dev eth0 root cake bandwidth "${upspeed}Mbit" nat "$queueprio" $extraoptions # options needs to be left unquoted to support multiple extra parameters
	ip link add name ifb9eth0 type ifb
	/opt/sbin/tc qdisc del dev eth0 ingress 2>/dev/null
	/opt/sbin/tc qdisc add dev eth0 handle ffff: ingress
	/opt/sbin/tc qdisc del dev ifb9eth0 root 2>/dev/null
	/opt/sbin/tc qdisc add dev ifb9eth0 root cake bandwidth "${dlspeed}Mbit" nat wash ingress "$queueprio" $extraoptions # options needs to be left unquoted to support multiple extra parameters
	ifconfig ifb9eth0 up
	/opt/sbin/tc filter add dev eth0 parent ffff: protocol all prio 10 u32 match u32 0 0 flowid 1:1 action mirred egress redirect dev ifb9eth0
}

cake_stop(){
	if cake_check; then
		Print_Output "true" "Stopping" "$PASS"
		cru d "$SCRIPT_NAME_FANCY"
		sed -i '\~# CakeQOS-Merlin~d' /jffs/scripts/nat-start /jffs/scripts/services-stop 2>/dev/null
		/opt/sbin/tc qdisc del dev eth0 ingress 2>/dev/null
		/opt/sbin/tc qdisc del dev ifb9eth0 root 2>/dev/null
		/opt/sbin/tc qdisc del dev eth0 root 2>/dev/null
		ip link del ifb9eth0
		rmmod sch_cake 2>/dev/null
		fc enable
		runner enable
		nvram set runner_disable="0"
		nvram commit
	fi
}


Cake_Header(){
	clear
	printf "\\n"
	printf "\\e[1m#########################################################\\e[0m\\n"
	printf "\\e[1m##               _                                     ##\\e[0m\\n"
	printf "\\e[1m##              | |                                    ##\\e[0m\\n"
	printf "\\e[1m##    ___  __ _ | | __ ___          __ _   ___   ___   ##\\e[0m\\n"
	printf "\\e[1m##   / __|/ _  || |/ // _ \ ______ / _  | / _ \ / __|  ##\\e[0m\\n"
	printf "\\e[1m##  | (__ |(_| ||   <|  __/|______| (_| || (_) |\__ \  ##\\e[0m\\n"
	printf "\\e[1m##   \___|\__,_||_|\_\\\\\___|        \__, | \___/ |___/  ##\\e[0m\\n"
	printf "\\e[1m##                                    | |              ##\\e[0m\\n"
	printf "\\e[1m##                                    |_|              ##\\e[0m\\n"
	printf "\\e[1m##                                                     ##\\e[0m\\n"
	printf "\\e[1m##                  %s on %-9s                ##\\e[0m\\n" "$SCRIPT_VERSION" "$RMODEL"
	printf "\\e[1m##                                                     ##\\e[0m\\n"
	printf "\\e[1m##      https://github.com/ttgapers/cakeqos-merlin     ##\\e[0m\\n"
	printf "\\e[1m##                                                     ##\\e[0m\\n"
	printf "\\e[1m#########################################################\\e[0m\\n"
	printf "\\n"
}

Cake_Menu(){
	Cake_Header
	reloadmenu="1"
	printf "\\e[1mSelect an option\\e[0m\\n"
	echo "[1]  --> Start cake"
	echo "[2]  --> Stop cake"
	echo "[3]  --> Check cake status"
	echo "[4]  --> Change cake settings"
	echo
	echo "[5]  --> Check for updates"
	echo "[6]  --> Install $SCRIPT_NAME_FANCY"
	echo "[7]  --> Uninstall $SCRIPT_NAME_FANCY"
	echo
	echo "[e]  --> Exit"
	echo
	printf "\\e[1m#####################################################\\e[0m\\n"
	echo
	while true; do
		printf "[1-7]: "
		read -r "menu1"
		echo
		case "$menu1" in
			1)
				option1="start"
				break
			;;
			2)
				option1="stop"
				break
			;;
			3)
				option1="status"
				break
			;;
			4)
				option1="settings"
				while true; do
					echo "Select Setting To Modify:"
					printf '%-35s | %-40s\n' "[1]  --> Download Speed" "$(if [ -n "$dlspeed" ]; then echo "[${dlspeed} Mbit]"; else echo "[Unset]"; fi)"
					printf '%-35s | %-40s\n' "[2]  --> Upload Speed" "$(if [ -n "$upspeed" ]; then echo "[${upspeed} Mbit]"; else echo "[Unset]"; fi)"
					printf '%-35s | %-40s\n' "[3]  --> Queue Priority" "$(if [ -n "$queueprio" ]; then echo "[${queueprio}]"; else echo "[Unset]"; fi)"
					printf '%-35s | %-40s\n' "[4]  --> Extra Options" "$(if [ -n "$extraoptions" ]; then echo "[${extraoptions}]"; else echo "[Unset]"; fi)"
					echo
					printf '%-35s\n' "[e]  --> Exit"
					echo
					printf "[1-4]: "
					read -r "menu2"
					echo
					case "$menu2" in
						1)
							option2="dlspeed"
							echo "Please enter your download speed:"
							printf "[Mbit]: "
							read -r "option3"
							echo
							if ! Validate_Bandwidth "$option3"; then
								echo "${option3} is not a valid number!"
								unset "option2" "option3"
								continue
							fi
							break
						;;
						2)
							option2="upspeed"
							echo "Please enter your upload speed:"
							printf "[Mbit]: "
							read -r "option3"
							echo
							if ! Validate_Bandwidth "$option3"; then
								echo "${option3} is not a valid number!"
								unset "option2" "option3"
								continue
							fi
							break
						;;
						3)
							option2="queueprio"
							while true; do
								echo "Select Queue Priority Type:"
								echo "[1]  --> besteffort (default)"
								echo "[2]  --> diffserv3"
								echo "[3]  --> diffserv4"
								echo "[4]  --> diffserv8"
								echo
								printf "[1-4]: "
								read -r "menu3"
								echo
								case "$menu3" in
									1|"")
										option3="besteffort"
										break
									;;
									2)
										option3="diffserv3"
										break
									;;
									3)
										option3="diffserv4"
										break
									;;
									4)
										option3="diffserv8"
										break
									;;
									e|exit|back|menu)
										unset "option1" "option2"
										clear
										Cake_Menu
										break
									;;
									*)
										echo "$menu3 Isn't An Option!"
										echo
									;;
								esac
							done
							break
						;;
						4)
							option2="extraoptions"
							echo "Please enter your extra options:"
							printf "[Options]: "
							read -r "option3"
							echo
							break
						;;
						e|exit|back|menu)
							unset "option1" "option2" "option3"
							clear
							Cake_Menu
							break
						;;
					esac
				done
				break
			;;
			5)
				option1="update"
				break
			;;
			6)
				option1="install"
				break
			;;
			7)
				option1="uninstall"
				break
			;;
			e)
				Cake_Header
				printf "\\n\\e[1mThanks for using %s!\\e[0m\\n\\n\\n" "$SCRIPT_NAME_FANCY"
				exit 0
			;;
			*)
				echo "$menu1 Isn't An Option!"
				echo
			;;
		esac
	done
}

if [ -z "$1" ]; then
	Cake_Menu
fi

if [ -n "$option1" ]; then
	set "$option1" "$option2" "$option3"
fi

case $1 in
	start)
		cake_start
	;;
	stop)
		cake_stop
	;;
	status)
		if cake_check; then
			Print_Output "false" "Running..." "$PASS"
			Print_Output "false" "> Download Status:" "$PASS"
			echo "$STATUS_DOWNLOAD"
			Print_Output "false" "> Upload Status:" "$PASS"
			echo "$STATUS_UPLOAD"
		else
			Print_Output "false" "Not running..." "$WARN"
		fi
	;;
	settings)
		case "$2" in
			dlspeed)
				if ! Validate_Bandwidth "$3"; then echo "${3} is not a valid number!"; echo; exit 2; fi
				dlspeed="${3}"
			;;
			upspeed)
				if ! Validate_Bandwidth "$3"; then echo "${3} is not a valid number!"; echo; exit 2; fi
				upspeed="${3}"
			;;
			queueprio)
				case "$3" in
					besteffort)
						queueprio="besteffort"
					;;
					diffserv3)
						queueprio="diffserv3"
					;;
					diffserv4)
						queueprio="diffserv4"
					;;
					diffserv8)
						queueprio="diffserv8"
					;;
					*)
						echo "Command Not Recognized, Please Try Again"
						echo; exit 2
					;;
				esac
			;;
			extraoptions)
				extraoptions="$3"
			;;
		esac
		Write_Config
		if cake_check; then
			cake_start
		fi
	;;
	install)
		if [ "$(nvram get jffs2_scripts)" != "1" ]; then
			nvram set jffs2_scripts=1
			nvram commit
			Print_Output "true" "Custom JFFS scripts enabled - Please manually reboot to apply changes - Exiting" "$CRIT"
			exit 1
		fi

		cake_download

		if [ -z "$dlspeed" ]; then
			while true; do
				echo
				echo "Please enter your download speed:"
				printf "[Mbit]: "
				read -r "dlspeed"
				echo
				if ! Validate_Bandwidth "$dlspeed"; then
					echo "${dlspeed} is not a valid number!"
					continue
				fi
				break
			done

		fi
		if [ -z "$upspeed" ]; then
			while true; do
				echo
				echo "Please enter your upload speed:"
				printf "[Mbit]: "
				read -r "upspeed"
				echo
				if ! Validate_Bandwidth "$upspeed"; then
					echo "${upspeed} is not a valid number!"
					continue
				fi
				break
			done
		fi
		if [ -z "$queueprio" ]; then
			while true; do
				echo
				echo "Select Queue Prioity Type:"
				echo "[1]  --> besteffort (default)"
				echo "[2]  --> diffserv3"
				echo "[3]  --> diffserv4"
				echo "[4]  --> diffserv8"
				echo
				printf "[1-4]: "
				read -r "menu3"
				echo
				case "$menu3" in
					2)
						queueprio="diffserv3"
						break
					;;
					3)
						queueprio="diffserv4"
						break
					;;
					4)
						queueprio="diffserv8"
						break
					;;
					1|*)
						queueprio="besteffort"
						break
					;;
				esac
			done
		fi
		if [ -z "$extraoptions" ]; then
			echo
			echo "Please enter your extra options:"
			printf "[Options]: "
			read -r "extraoptions"
			echo
		fi
		Write_Config
		cake_start
	;;
	update)
		if [ "$(nvram get jffs2_scripts)" != "1" ]; then
			nvram set jffs2_scripts=1
			nvram commit
			Print_Output "true" "Custom JFFS scripts enabled - Please manually reboot to apply changes - Exiting" "$CRIT"
			exit 1
		fi
		cake_download "update"
	;;
	uninstall)
		cake_stop
		sed -i '\~# CakeQOS-Merlin~d' /jffs/scripts/nat-start /jffs/scripts/services-stop
		opkg --autoremove remove sched-cake-oot
		opkg --autoremove remove tc-adv
		rm -rf "/jffs/scripts/${SCRIPT_NAME}" "/opt/bin/${SCRIPT_NAME}" "${SCRIPT_DIR}"
		exit 0
	;;
	checkrun)
		if ! cake_check; then
			Print_Output "true" "Not running, forcing start..." "$CRIT"
			cake_start
		fi
	;;
	installer)
		Print_Output "false" "Downloading CakeQoS-Merlin installer..." "$PASS"
		git_install
                if [ ! -L "/opt/bin/${SCRIPT_NAME}" ] || [ "$(readlink /opt/bin/${SCRIPT_NAME})" != "${SCRIPT_DIR}/${SCRIPT_NAME}" ]; then
			rm -rf /opt/bin/${SCRIPT_NAME}
			ln -s "${SCRIPT_DIR}/${SCRIPT_NAME}" "/opt/bin/${SCRIPT_NAME}"
		fi
		Print_Output "false" "CakeQoS-Merlin installed! Please run it using 'cake-qos' and use Option 1 to start it. Let the magic begin!" "$PASS"
		exit 0
	;;
	*)
		Print_Output "false" "Usage: $SCRIPT_NAME {install|update|start|status|stop|uninstall} (start has required parameters)" "$WARN"
		echo
		Print_Output "false" "install:   only downloads and installs necessary $SCRIPT_NAME binaries" "$PASS"
		Print_Output "false" "update:    update $SCRIPT_NAME binaries (if any available)" "$PASS"
		Print_Output "false" "start:     configure and start $SCRIPT_NAME" "$PASS"
		Print_Output "false" "status:    check the current status of $SCRIPT_NAME" "$PASS"
		Print_Output "false" "stop:      stop $SCRIPT_NAME" "$PASS"
		Print_Output "false" "uninstall: stop $SCRIPT_NAME, remove from startup, and remove cake binaries" "$PASS"
	;;
esac
if [ -n "$reloadmenu" ]; then echo; echo; printf "[i] Press Enter To Continue..."; read -r "reloadmenu"; exec "$0"; fi
