#!/bin/bash
# Autor: Filip Valder (filip.valder@vsb.cz)
# Datum: 6.6.2011
# Popis: Nastroj pro distribucne nezavislou inspekci linuxoveho systemu (proprietarni verze)
# Nazev: trachta.sh
# Verze: STABILNI


# Konfigurace

# Jazyk
export LANG=C

# Spolecna konfigurace
function conf ( ) {
	HOSTNAME_DOMAIN=`hostname -d`
	HOSTNAME_FQDN=`hostname -f`
	HOSTNAME_SHORT=`hostname -s`
	DISTS=(
		"/etc/redhat-release|centos_rhel|CentOS/RHEL"
		"/etc/debian_version|debian_ubuntu|Debian/Ubuntu"
		"/etc/SuSE-release|sles|SLES"
	)
}

# Konfigurace distribuci
function conf_centos_rhel ( ) {
	SERVICES_CHKCONFIG_2="on"
	SERVICES_CHKCONFIG_3="on"
	SERVICES_CHKCONFIG_4="on"
	SERVICES_CHKCONFIG_5="on"
}
function conf_debian_ubuntu ( ) {
	SERVICES_CHKCONFIG_2="on"
	SERVICES_CHKCONFIG_3="on"
	SERVICES_CHKCONFIG_4="on"
	SERVICES_CHKCONFIG_5="on"
}
function conf_sles ( ) {
	SERVICES_CHKCONFIG_3="on"
	SERVICES_CHKCONFIG_5="on"
}
function conf_unknown ( ) {
	return
}


# Funkce

# Vystredit text
function center () {
	ALIGN=$[(75-${#1})/2]
	printf %-${ALIGN}s%s\\n "" "$1"
}

# Iniciace kontrol
function check ( ) {
	check_system
	check_localization
	check_net
	check_users
	check_timezone
	check_time
	check_filesystems
	check_services
	check_ssh
	check_postfix
	check_snmp
	check_nrpe
	check_backup
	check_other
	check_$1
}

# Spolecne kontroly
function check_backup ( ) {
	I=0
	PRE="Zalohovani"
	echo "* $PRE"
	MSG0="HP Data Protector je spravne zavedeny v services"
	MSG1="HP Data Protector neni spravne zavedeny v services"
	grep -q "^omni.*5555/tcp" /etc/services && ! grep -q "^[^#]*personal-agent.*5555/tcp" /etc/services && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	MSG0="verejny klic zalohovaciho serveru je zavedeny"
	MSG1="verejny klic zalohovaciho serveru neni zavedeny"
	grep -q "hp_data_protector" ~/.ssh/authorized_keys 2> /dev/null && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	MSG0="sluzba omni je nainstalovana"
	MSG1="sluzba omni neni nainstalovana"
	echo "$XINETD_ON" | grep -q " omni" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_filesystems ( ) {
	I=0
	PRE="Souborove systemy"
	echo "* $PRE"
	for FS in `grep "ext3" /etc/mtab | cut -d " " -f 1` ; do
		tune2fs -l $FS | grep -q "Filesystem state.*clean" || { FS_DAMAGED="$FS_DAMAGED $FS" && let I++ ; }
	done
	MSG0="ext3 jsou ciste"
	MSG1="poskozene ext3:"
	[ $I -eq 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$FS_DAMAGED"
}
function check_localization () {
	I=0
	PRE="Lokalizace"
	echo "* $PRE"
	locale -a | grep -q "cs_CZ.utf8" && let I++
	locale -a | grep -q "en_US.utf8" && let I++
	MSG0="alespon jedno vhodne locale je nainstalovano:"
	MSG1="zadne vhodne locale neni nainstalovano"
	if [ $I -ge 1 ] ; then
		log 0 "$PRE: $MSG0"
		log_list "`locale -a | egrep \"cs_CZ.utf8|en_US.utf8\"`"
	else
		log 1 "$PRE: $MSG1"
	fi
}
function check_net () {
	I=0
	PRE="Sit"
	echo "* $PRE"
	log 2 "$PRE: FQDN je '$HOSTNAME_FQDN'"
	host $HOSTNAME_FQDN >& /dev/null && HOST="`host $HOSTNAME_FQDN`"
	for IP in `echo $HOST | sed -r "s/.* has( IPv6)? address //"` ; do
		host "$IP" | grep -q "domain name pointer $HOSTNAME_FQDN\.$" || IP_NOPTR="$IP_NOPTR $IP"
	done
	MSG0="vsechny pridelene IP adresy maji reverzni zaznam"
	MSG1="pridelene IP adresy, ktere nemaji reverzni zaznam:"
	for IP in $IP_NOPTR ; do
		log_list "$IP"
	done
	[ $I -eq 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	for IF in `ifconfig -a | grep "^\w" | grep -v "^sit[0-9]*" | cut -d " " -f 1` ; do
		ifconfig "$IF" | egrep -q "inet6? addr" || { IF_NOIP="$IF_NOIP $IF" && let I++ ; }
	done
	MSG0="vsechna rozhrani maji prirazenou IP adresu"
	MSG1="rozhrani, ktera nemaji prirazenou IP adresu:"
	[ $I -eq 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$IF_NOIP"
	MSG0="iptables obsahuji nejaka pravidla"
	MSG1="iptables neobsahuji zadna pravidla"
	[ `iptables -L -n | egrep -cv "^Chain|^target|^$"` -ne 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	MSG0="IPv6 adresa je pridelena"
	MSG1="IPv6 adresa neni pridelena"
	if host "$HOSTNAME_FQDN" | grep -q "has IPv6 address" ; then
		log 0 "$PRE: $MSG0"
	else
		log 2 "$PRE: $MSG1"
		return
	fi
	MSG0="ip6tables jsou nainstalovane"
	MSG1="ip6tables nejsou nainstalovane"
	which ip6tables >& /dev/null && log 0 "$PRE: $MSG0" || { log 1 "$PRE: $MSG1" && return ; }
	MSG0="ip6tables obsahuji nejaka pravidla"
	MSG1="ip6tables neobsahuji zadna pravidla"
	[ `ip6tables -L -n | egrep -cv "^Chain|^target|^$"` -ne 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_nrpe () {
	I=0
	PRE="NRPE"
	echo "* $PRE"
	MSG0="nrpe je nainstalovany"
	MSG1="nrpe neni nainstalovany"
	if which nrpe >& /dev/null ; then
		log 0 "$PRE: $MSG0"
	else
		log 1 "$PRE: $MSG1"
		return
	fi
	MSG0="nasledujici prikazy jsou registrovane:"
	MSG1="zadne prikazy nejsou registrovane"
	for CMD in `grep "^[^#]*command\[" /etc/nagios/nrpe.cfg | sed "s/.*command\[\(.*\)\].*/\1/"` ; do
		CMDS="$CMDS $CMD"
		let I++
	done
	[ $I -ne 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$CMDS"
}
function check_other () {
	I=0
	PRE="Ostatni"
	echo "* $PRE"
	MSG0="dconf je nainstalovany"
	MSG1="dconf neni nainstalovany"
	which dconf >& /dev/null && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
	MSG0="logrotate.conf obsahuje parametr compress"
	MSG1="logrotate.conf neobsahuje parametr compress"
	egrep -q "^[^#]*compress($|\W)" /etc/logrotate.conf && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
	MSG0="logrotate.conf obsahuje parametr dateext"
	MSG1="logrotate.conf neobsahuje parametr dateext"
	egrep -q "^[^#]*dateext($|\W)" /etc/logrotate.conf && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
}
function check_postfix () {
	I=0
	PRE="Postfix"
	echo "* $PRE"
	MSG0="postfix je nainstalovany"
	MSG1="postfix neni nainstalovany"
	if which postfix >& /dev/null ; then
		log 0 "$PRE: $MSG0"
	else
		log 1 "$PRE: $MSG1"
		return
	fi
	ROOT="`postalias -q root /etc/aliases`"
	MSG0="alias 'root' je spravne nastaveny:"
	MSG1="alias 'root' neni spravne nastaveny"
	[ -n "$ROOT" ] && echo "$ROOT" | grep -q "@`echo $HOSTNAME_DOMAIN | sed \"s/\./\\\\\\\\./g\"`" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$ROOT"
	MSG0="myhostname odpovida tomuto stroji"
	MSG1="myhostname neodpovida tomuto stroji"
	postconf -h myhostname 2> /dev/null | egrep -q "^($HOSTNAME_FQDN|$HOSTNAME_SHORT)$" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	MSG0="myhostname je FQDN"
	MSG1="myhostname neni FQDN"
	! postconf 2>&1 | grep -q "My hostname .* is not a fully qualified name" && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
	MSG0="relayhost je spravne nastaveny"
	MSG1="relayhost neni spravne nastaveny"
	for MX in `host $HOSTNAME_DOMAIN 2> /dev/null | grep "mail is handled by" | sed "s/.* mail is handled by [0-9]* \(.*\)\./\1/"` ; do
		[ "`postconf -h relayhost`" = "$MX" ] && let I++
	done
	[ $I -ne 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_services () {
	I=0
	PRE="Sluzby"
	echo "* $PRE"
	MSG0="cron je zapnuty"
	MSG1="cron je vypnuty"
	pgrep cron > /dev/null && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log 2 "$PRE: naslouchajici sluzby (PID/nazev)"
	for SRV in `netstat -lnp | egrep "^(tcp|udp).*[0-9]*/" | sed "s/.*[^0-9]\([0-9]*\/[^ :]*\).*/\1/" | sort -n | uniq` ; do
		SRV_NAME="`echo \"$SRV\" | cut -d \"/\" -f 2`"
		SRV_LISTENING="$SRV_LISTENING $SRV_NAME"
		log 3 "$SRV"
	done
	SRV_LISTENING="`echo \"$SRV_LISTENING\" | sed -re \"s/ dhclient| xinetd//g\" -e \"s/ master/ postfix/\" -e \"s/ postmaster/ postgresql/\"`"
	MSG0="sprava runlevelu je nainstalovana"
	MSG1="sprava runlevelu neni nainstalovana"
	if which chkconfig >& /dev/null ; then
		log 0 "$PRE: $MSG0"
	else
		log 1 "$PRE: $MSG1"
		return
	fi
	CHKCONFIG="`chkconfig --list`"
	for SRV in $SRV_LISTENING ; do
		echo "$CHKCONFIG" | sed "s/^\([^ ]*\)/\1 \1d/" | grep -q "[^ ]*$SRV[^ ]* .*2:$SERVICES_CHKCONFIG_2.*3:$SERVICES_CHKCONFIG_3.*4:$SERVICES_CHKCONFIG_4.*5:$SERVICES_CHKCONFIG_5" || SRV_OFF="$SRV_OFF $SRV"
	done
	MSG0="vsechny uvedene maji zapnute sve runlevely"
	MSG1="naslouchajici, ktere nemaji zapnute sve runlevely:"
	[ -z "$SRV_OFF" ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$SRV_OFF"
	echo "$CHKCONFIG" | grep -q "xinetd .*3:on.*4:on.*5:on" && let I++
	for XINETD_SRV in `echo "$CHKCONFIG" | grep -A 2147483647 "^xinetd based services" | grep "on$"` ; do
		XINETD_NAME="`echo \"$XINETD_SRV\" | sed -r \"s/[ 	:]|on$//g\"`"
		XINETD_ON="$XINETD_ON $XINETD_NAME"
	done
	MSG0="xinetd je zapnuty a ma zapnute sluzby:"
	MSG1="xinetd je zapnuty a ma vypnute sluzby"
	MSG2="xinetd je vypnuty a ma zapnute sluzby:"
	MSG3="xinetd je vypnuty a ma vypnute sluzby"
	if [ $I -ne 0 ] && [ -n "$XINETD_ON" ] ; then
		log 2 "$PRE: $MSG0"
		log_list "$XINETD_ON"
	elif [ $I -ne 0 ] && [ -z "$XINETD_ON" ] ; then
		log 1 "$PRE: $MSG1"
	elif [ $I -eq 0 ] && [ -n "$XINETD_ON" ] ; then
		log 2 "$PRE: $MSG2"
		log_list "$XINETD_ON"
	else
		log 0 "$PRE: $MSG3"
	fi
}
function check_snmp () {
	I=0
	PRE="SNMP"
	echo "* $PRE"
	MSG0="snmpd je nainstalovany"
	MSG1="snmpd neni nainstalovany"
	if which snmpd >& /dev/null ; then
		log 0 "$PRE: $MSG0"
	else
		log 1 "$PRE: $MSG1"
		return
	fi
	ROCOMMUNITY="`grep \"^[^#]*rocommunity\" /etc/snmp/snmpd.conf | awk \"{print \\$2}\"`"
	[ -z "$ROCOMMUNITY" ] && ROCOMMUNITY="`grep \"^[^#]*com2sec\" /etc/snmp/snmpd.conf | awk \"{print \\$4}\"`"
	MSG0="zkusebni snmpget byl uspesny"
	MSG1="zkusebni snmpget nebyl uspesny"
	snmpget -c $ROCOMMUNITY -v 1 localhost system.sysDescr.0 >& /dev/null && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_ssh () {
	I=0
	J=0
	K=0
	PRE="SSH"
	echo "* $PRE"
	SSHD="`sshd -T 2> /dev/null`"
	if [ -n "$SSHD" ] ; then
		[ `echo "$SSHD" | egrep -c "(kbdinteractiveauthentication|passwordauthentication) no"` -eq 2 ] || let I++
		echo "$SSHD" | grep -q "permitemptypasswords no" || let J++
		echo "$SSHD" | grep -q "usepam no" || let K++
	fi
	grep -q "^[^#]*PasswordAuthentication.*no" /etc/ssh/sshd_config || let I++
	MSG0="autentizace heslem je zakazana"
	MSG1="doporucuje se autentizace verejnym klicem"
	[ $I -eq 0 ] && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
	MSG0="prihlasovani prazdnym heslem je zakazane"
	MSG1="prihlasovani prazdnym heslem je povolene"
	grep -q "^[^#]*PermitEmptyPasswords.*yes" /etc/ssh/sshd_config && let J++
	[ $J -eq 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	MSG0="PAM autentizace je zakazana"
	MSG1="PAM autentizace je povolena"
	grep -q "^[^#]*UsePAM.*yes" /etc/ssh/sshd_config && let K++
	[ $K -eq 0 ] && log 0 "$PRE: $MSG0" || log 2 "$PRE: $MSG1"
}
function check_system () {
	I=0
	PRE="System"
	echo "* $PRE"
	SWAP_TOTAL="`free -b | grep \"^Swap\" | tr -s \" \" | cut -d \" \" -f 2`"
	SWAP_USED="`free -b | grep \"^Swap\" | tr -s \" \" | cut -d \" \" -f 3`"
	SWAP_RATIO=$[100*$SWAP_USED/$SWAP_TOTAL]
	MSG0="swap je zaplneny z $SWAP_RATIO%% sve kapacity"
	MSG1="swap je zaplneny z $SWAP_RATIO%% sve kapacity"
	[ $SWAP_RATIO -le 100 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_time () {
	I=0
	PRE="Cas"
	echo "* $PRE"
	MSG0="ntpd je nainstalovany"
	MSG1="ntpd neni nainstalovany"
	if which ntpd >& /dev/null ; then
		log 0 "$PRE: $MSG0"
		PEERS="`ntpq -c peers 2> /dev/null`"
		MSG0="hlavni ntp peer je dostupny"
		MSG1="zadny hlavni ntp peer neni dostupny"
		echo "$PEERS" | grep -q "^*" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
		MSG0="alespon jeden zalozni ntp kandidat je dostupny"
		MSG1="zadny zalozni ntp kandidat neni dostupny"
		echo "$PEERS" | grep -q "^+" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	else
		log 1 "$PRE: $MSG1"
		MSG0="ntpdate je nainstalovany"
		MSG1="ntpdate neni nainstalovany"
		which ntpdate >& /dev/null && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
		MSG0="cron pro ntpdate byl nalezen"
		MSG1="cron pro ntpdate nebyl nalezen"
		grep -ilr "^[^#]*ntpdate" /etc/cron* && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	fi
}
function check_timezone () {
	I=0
	PRE="Casova zona"
	echo "* $PRE"
	MSG0="stredoevropsky (letni) cas je nastaveny"
	MSG1="stredoevropsky (letni) cas neni nastaveny"
	tail -n 1 /etc/localtime | grep -q "CET-1CEST" && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
}
function check_users () {
	I=0
	PRE="Uzivatele"
	echo "* $PRE"
	while read LN ; do
		USER="`echo \"$LN\" | cut -d \":\" -f 1`"
		PASS="`echo \"$LN\" | cut -d \":\" -f 2`"
		[ -z "$PASS" ] && USER_NOPASS="$USER_NOPASS $USER" && let I++
	done < /etc/shadow
	MSG0="vsichni maji nastavene heslo"
	MSG1="$I nema nastavene heslo:"
	[ $I -eq 0 ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_list "$USER_NOPASS"
	WHO="`who | grep \"tty[0-9]*\"`"
	MSG0="na tty* nejsou zadna otevrena sezeni"
	MSG1="sezeni na tty*, ktera jsou otevrena:"
	[ -z "$WHO" ] && log 0 "$PRE: $MSG0" || log 1 "$PRE: $MSG1"
	log_line "$WHO"
}

# Kontroly distribuci
function check_centos_rhel ( ) {
	return
}
function check_debian_ubuntu ( ) {
	return
}
function check_sles ( ) {
	return
}
function check_unknown ( ) {
	return
}

# Hlavicka
function header () {
	echo
	center "Trachta na serveru $HOSTNAME_SHORT"
	center "(spusteno `date +%-d.%-m.%Y\ v\ %-H:%M:%S`)"
	echo "---------------------------------------------------------------------------"
	printf %-16s%s\\n "Linux verze:" "`uname -a`"
	for DIST in ${DISTS[@]} ; do
		DIST_FILE="`echo $DIST | cut -d \"|\" -f 1`"
		DIST_NAME="`echo $DIST | cut -d \"|\" -f 3`"
		[ -r "$DIST_FILE" ] && break
	done
	[ ! -r "$DIST_FILE" ] && DIST_NAME="neznámá"
	printf %-16s%s\\n "Distribuce:" "$DIST_NAME"
	lspci | grep -cq VMware && VIRT="ano" || VIRT="ne"
	printf %-16s%s\\n "Virt. stroj:" "$VIRT"
}

# Zaznam
function log ( ) {
	let SUM++
	case $1 in
		0)
			let OK++
			OFFSET=8
			STATE="ok"
		;;
		1)
			let ERR++
			OFFSET=8
			STATE="!!"
		;;
		2)
			let WARN++
			OFFSET=8
			STATE=".."
		;;
		3)
			let SUM--
			OFFSET=12
			STATE=""
		;;
	esac
	LOG="$LOG`printf %-${OFFSET}s%s\\\\\\\\n \"$STATE\" \"$2\"`"
}
function log_line ( ) {
	[ -z "$1" ] && return
	for LN in "$1" ; do
		log 3 "$LN"
	done
}
function log_list ( ) {
	SPLIT="`echo $1 | sed \"s/,/ /g\"`"
	for WRD in $SPLIT ; do
		log 3 "$WRD"
	done
}

# Hlavni funkce
function main ( ) {
	for DIST in ${DISTS[@]} ; do
		DIST_FILE="`echo $DIST | cut -d \"|\" -f 1`"
		DIST_FUNC="`echo $DIST | cut -d \"|\" -f 2`"
		[ -r "$DIST_FILE" ] && break
	done
	[ ! -r "$DIST_FILE" ] && conf_unknown || conf_$DIST_FUNC
	echo
	center "Kontroly"
	echo "---------------------------------------------------------------------------"
	[ ! -r "$DIST_FILE" ] && check unknown || check $DIST_FUNC
}

# Vysledky
function results () {
	echo
	center "Vysledky"
	echo "---------------------------------------------------------------------------"
	printf "$LOG"
	echo
	center "Shrnuti"
	echo "---------------------------------------------------------------------------"
	echo "* Kontrol celkem: ${SUM:-0}"
	echo "* Uspesne: ${OK:-0}"
	echo "* Chybne: ${ERR:-0}"
	echo "* Upozorneni: ${WARN:-0}"
	echo
}

## Ano/ne?
#function yes_no ( ) {
#	read -p "$1 (A/N/a/n)? " YES_NO
#	[ "$YES_NO" = "A" ] || [ "$YES_NO" = "a" ] && return 0
#	[ "$YES_NO" = "N" ] || [ "$YES_NO" = "n" ] && return 1
#	yes_no $1
#}


# Program (vse zformatovat)
{
	# Spusteni vyzaduje efektivni UID 0.
	[ "`id -u`" -eq 0 ] || { echo "Chyba: $0 vyzaduje spusteni pod uzivatelem 'root'." 1>&2 && exit 1 ; }
	# Konfigurace, hlavicka, hlavni funkce, vysledky
	conf ; header ; main ; results
} | fmt -s
