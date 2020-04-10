#!/bin/bash
#-Metadata----------------------------------------------------#
#  Filename: OSINTer.sh             (last Updated: 2020-04-07)#
#-Info--------------------------------------------------------#
#  Post-install script for installing OSINT tools             #
#-Author(s)---------------------------------------------------#
#  xFreed0m ~ https://betheadversary.com/                     #
#  Most of the script is based (and parts copied and modified)#
#  From G0tmi1k os-scripts:                                   #
# (https://github.com/g0tmi1k/os-scripts)                     #
#-Operating System--------------------------------------------#
#  Designed for: Debian based systems                         #
#     Tested on: Ubuntu 19.10 Desktop [x64] (VM)              #

#--- Only used for stats at the end
start_time=$(date +%s)

##### (Cosmetic) Colour output
RED="\033[01;31m"      # Issues/Errors
GREEN="\033[01;32m"    # Success
YELLOW="\033[01;33m"   # Warnings/Information
BLUE="\033[01;34m"     # Heading
BOLD="\033[01;01m"     # Highlight
RESET="\033[00m"       # Normal

##### (Cosmetic) spinner to see that the command is running
# TBD Placeholder


STAGE=0                                                         # Where are we up to
TOTAL=$( grep '(${STAGE}/${TOTAL})' $0 | wc -l );(( TOTAL-- ))  # How many things have we got todo

# Let's log error to a log file for easier debug in case something failed
LOGFILE=/tmp/OSINTer_$(date +%F_%T).log

quiet=

case "$1" in
-q|--q|--qu|--qui|--quie|--quiet)
    quiet=1
    shift ;;
esac

if [ "$quiet" = 1 ]; then
  # print error to console and to the logfile
  exec 2> >(tee -ia $LOGFILE >&2)
else
  # print all output also to console and logfile
  exec >  >(tee -ia $LOGFILE)
  exec 2> >(tee -ia $LOGFILE >&2)
fi

# Banner
cat << "EOF"
_____ _____ _____ _   _ _____
|  _  /  ___|_   _| \ | |_   _|
| | | \ `--.  | | |  \| | | | ___ _ __
| | | |`--. \ | | | . ` | | |/ _ | '__|
\ \_/ /\__/ /_| |_| |\  | | |  __| |
\___/\____/ \___/\_| \_/ \_/\___|_|
by @xFreed0m
EOF



##### Check if we are running as root - else this script will fail (hard!)
if [[ "${EUID}" -ne 0 ]]; then
  echo -e ' '${RED}'[!]'${RESET}" This script must be ${RED}run as root${RESET}" 1>&2
  echo -e ' '${RED}'[!]'${RESET}" Quitting..." 1>&2
  exit 1
else
  echo -e " ${BLUE}[*]${RESET} ${BOLD}OSINTer starting...grab something to drink${RESET}"
  sleep 3s
fi

##### Fix display output for GUI programs (when connecting via SSH)
export DISPLAY=:0.0
export TERM=xterm

##### Check Internet access
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Checking ${GREEN}Internet access${RESET}"
#--- Can we ping google?
for i in {1..10}; do ping -c 1 -W ${i} www.google.com &>/dev/null && break; done
#--- Run this, if we can't
if [[ "$?" -ne 0 ]]; then
  echo -e ' '${RED}'[!]'${RESET}" ${RED}Possible DNS issues${RESET}(?)" 1>&2
  echo -e ' '${RED}'[!]'${RESET}" Will try and use ${YELLOW}DHCP${RESET} to 'fix' the issue" 1>&2
  chattr -i /etc/resolv.conf 2>/dev/null
  dhclient -r
  #--- Second interface causing issues?
  ip addr show eth1 &>/dev/null
  [[ "$?" == 0 ]] \
    && route delete default gw 192.168.155.1 2>/dev/null
  #--- Request a new IP
  dhclient
  dhclient eth0 2>/dev/null
  dhclient wlan0 2>/dev/null
  #--- Wait and see what happens
  sleep 15s
  _TMP="true"
  _CMD="$(ping -c 1 8.8.8.8 &>/dev/null)"
  if [[ "$?" -ne 0 && "$_TMP" == "true" ]]; then
    _TMP="false"
    echo -e ' '${RED}'[!]'${RESET}" ${RED}No Internet access${RESET}" 1>&2
    echo -e ' '${RED}'[!]'${RESET}" You will need to manually fix the issue, before re-running this script" 1>&2
  fi
  _CMD="$(ping -c 1 www.google.com &>/dev/null)"
  if [[ "$?" -ne 0 && "$_TMP" == "true" ]]; then
    _TMP="false"
    echo -e ' '${RED}'[!]'${RESET}" ${RED}Possible DNS issues${RESET}(?)" 1>&2
    echo -e ' '${RED}'[!]'${RESET}" You will need to manually fix the issue, before re-running this script" 1>&2
  fi
  if [[ "$_TMP" == "false" ]]; then
    (dmidecode | grep -iq virtual) && echo -e " ${YELLOW}[i]${RESET} VM Detected"
    (dmidecode | grep -iq virtual) && echo -e " ${YELLOW}[i]${RESET} ${YELLOW}Try switching network adapter mode${RESET} (e.g. NAT/Bridged)"
    echo -e ' '${RED}'[!]'${RESET}" Quitting..." 1>&2
    exit 1
  fi
else
  echo -e " ${YELLOW}[i]${RESET} ${YELLOW}Detected Internet access${RESET}" 1>&2
fi


##### adding google & kali default network repositories ~ http://docs.kali.org/general-use/kali-linux-sources-list-repositories
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Adding kali rolling default OS ${GREEN}network repositories${RESET}"
#--- validate sources key
apt-get -qq install gnupg
wget -q 'https://archive.kali.org/archive-key.asc'
apt-key add archive-key.asc
#--- To avoid kali sources taking over system packages
sh -c "echo 'Package: *'>/etc/apt/preferences.d/kali.pref; echo 'Pin: release a=kali-rolling'>>/etc/apt/preferences.d/kali.pref; echo 'Pin-Priority: 50'>>/etc/apt/preferences.d/kali.pref"
#--- Add network repositories
file=/etc/apt/sources.list; [ -e "${file}" ] && cp -n $file{,.bkup}
([[ -e "${file}" && "$(tail -c 1 ${file})" != "" ]]) && echo >> "${file}"
#--- Main
grep -q '^deb .* kali-rolling' "${file}" 2>/dev/null \
  || echo -e "\n# Kali Rolling\ndeb http://http.kali.org/kali kali-rolling main contrib non-free" >> "${file}"
#--- Source
grep -q '^deb-src .* kali-rolling' "${file}" 2>/dev/null \
  || echo -e "deb-src http://http.kali.org/kali kali-rolling main contrib non-free" >> "${file}"
#--- Disable CD repositories
sed -i '/kali/ s/^\( \|\t\|\)deb cdrom/#deb cdrom/g' "${file}"
#--- adding Google repository
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Adding Google ${GREEN}repositories${RESET}"
wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
echo -e "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> "${file}"
#--- incase we were interrupted
dpkg --configure -a
apt-get -qq update
if [[ "$?" -ne 0 ]]; then
  echo -e ' '${RED}'[!]'${RESET}" There was an ${RED}issue accessing network repositories${RESET}" 1>&2
  echo -e " ${YELLOW}[i]${RESET} Are the remote network repositories ${YELLOW}currently being sync'd${RESET}?"
  echo -e " ${YELLOW}[i]${RESET} Here is ${BOLD}YOUR${RESET} local network ${BOLD}repository${RESET} information (Geo-IP based):\n"
  curl -sI http://http.kali.org/README
  exit 1
fi

(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Setting static & protecting ${GREEN}DNS name servers${RESET}"
file=/etc/resolv.conf; [ -e "${file}" ] && cp -n $file{,.bkup}
chattr -i "${file}" 2>/dev/null
#--- Use both cloudflare and google DNS
echo -e 'nameserver 1.1.1.1\nnameserver 8.8.8.8' > "${file}"
#--- Protect it
chattr +i "${file}" 2>/dev/null

##### Update OS from network repositories
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) ${GREEN}Updating OS${RESET} from network repositories"
echo -e " ${YELLOW}[i]${RESET}  ...this ${BOLD}may take a while${RESET} depending on your Internet connection"
for FILE in clean autoremove; do apt-get -y -qq "${FILE}"; done         # Clean up      clean remove autoremove autoclean
export DEBIAN_FRONTEND=noninteractive
apt-get -qq update && APT_LISTCHANGES_FRONTEND=none apt-get -o Dpkg::Options::="--force-confnew" -y dist-upgrade --fix-missing 2>&1 \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

for FILE in clean autoremove; do apt-get -y -qq "${FILE}"; done         # Clean up - clean remove autoremove autoclean

##### Install bash completion - all users
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}bash completion${RESET}"
apt-get -y -qq install bash-completion \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
file=/etc/bash.bashrc; [ -e "${file}" ] && cp -n $file{,.bkup}   #~/.bashrc
sed -i '/# enable bash completion in/,+7{/enable bash completion/!s/^#//}' "${file}"
#--- Apply new configs
source "${file}"

##### Install git - all users
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}git${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
#--- Set as default editor
git config --global core.editor "vim"
#--- Set as default mergetool
git config --global merge.tool vimdiff
git config --global merge.conflictstyle diff3
git config --global mergetool.prompt false
#--- Set as default push
git config --global push.default simple

##### Install misc
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}misc${RESET}"
apt-get -y -qq install chromium-chromedriver curl golang python3 python3-pip build-essential libsqlite3-dev libseccomp-dev libsodium-dev publicsuffix cargo python python-pip \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2


##### Install libreoffice
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}LibreOffice${RESET} ~ This can take some time"
apt-get -y -qq install libreoffice \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install aptitude (needed for kali packages install)
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Aptitude${RESET}"
apt-get -y -qq install aptitude \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

#### TL OSINT Pkgs

##### Install GIMP
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}GIMP${RESET}"
apt-get -y -qq install gimp \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Flameshot
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Flameshot${RESET}"
apt-get -y -qq install flameshot \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Shotwell
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Shotwell${RESET}"
apt-get -y -qq install shotwell \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Audacity
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Audacity${RESET}"
apt-get -y -qq install audacity \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install SoundConverter
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}SoundConverter${RESET}"
apt-get -y -qq install soundconverter \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Darktable
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}SpiderFoot${RESET}"
apt-get -y -qq install darktable \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Photoflare
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Photoflare${RESET}"
apt-get -y -qq install photoflare \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install SimpleScreenRecorder
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}SimpleScreenRecorder${RESET}"
apt-get -y -qq install simplescreenrecorder \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install Peek
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Peek${RESET}"
apt-get -y -qq install peek \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install TOR
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}TOR${RESET}"
apt-get -y -qq install torbrowser-launcher \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install amass
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}amass${RESET}"
aptitude install -y -q -t kali-rolling amass \
  || echo -e ' '${RED}'[!] Issue with aptitude'${RESET} 1>&2

##### Install googler
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}googler${RESET}"
aptitude install -y -q -t kali-rolling googler \
  || echo -e ' '${RED}'[!] Issue with aptitude'${RESET} 1>&2

##### Install Google Chrome (needed for hunchly)
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Google Chrome${RESET}"
apt-get -y -qq install google-chrome-stable \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install maltego
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}maltego${RESET}"
aptitude install -y -q -t kali-rolling maltego \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install tinfoleak
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}tinfoleak${RESET}"
aptitude install -y -q -t kali-rolling tinfoleak \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2

##### Install stegosuite
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}stegosuite${RESET}"
apt-get -y -qq install stegosuite \
|| echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2





##### git installs

##### Install sn0int
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}sn0int${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/kpcyrd/sn0int.git /opt/sn0int-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
cd /opt/sn0int-git/ && cargo install -f --path . \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/sn0int-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install DumpsterDiver
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}DumpsterDiver${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/securing/DumpsterDiver.git /opt/DumpsterDiver-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/DumpsterDiver-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/DumpsterDiver-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install theHarvester
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}theHarvester${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/laramies/theHarvester.git /opt/theHarvester-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/theHarvester-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/theHarvester-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install instaloctrack
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}instaloctrack${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/bernsteining/instaloctrack.git /opt/instaloctrack-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/instaloctrack-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/instaloctrack-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install LittleBrother
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}LittleBrother${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/lulz3xploit/LittleBrother.git /opt/LittleBrother-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/LittleBrother-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/LittleBrother-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install skiptracer
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}skiptracer${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/xillwillx/skiptracer.git /opt/skiptracer-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/skiptracer-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/skiptracer-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install Photon
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Photon${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/s0md3v/Photon.git /opt/photon-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/photon-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/photon-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install sherlock
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Sherlock${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/sherlock-project/sherlock.git /opt/sherlock-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/sherlock-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/photon-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install Gasmask
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Gasmask${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/twelvesec/gasmask.git /opt/gasmask-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip install --progress-bar off -r /opt/gasmask-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip installing requirements'${RESET} 1>&2
pushd /opt/gasmask-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install fbi
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}fbi${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/xHak9x/fbi.git /opt/fbi-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip install --progress-bar off -r /opt/fbi-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip installing requirements'${RESET} 1>&2
pushd /opt/fbi-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install Sublist3r
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Sublist3r${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/aboul3la/Sublist3r.git /opt/sublist3r-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
pip3 install --progress-bar off -r /opt/sublist3r-git/requirements.txt \
  || echo -e ' '${RED}'[!] Issue when pip3 installing requirements'${RESET} 1>&2
pushd /opt/sublist3r-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install buster
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}buster${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/sham00n/buster.git /opt/buster-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
python3 /opt/buster-git/setup.py install \
  || echo -e ' '${RED}'[!] Issue when python3 installing requirements'${RESET} 1>&2
pushd /opt/buster-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install Infoga
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}Infoga${RESET}"
apt-get -y -qq install git \
  || echo -e ' '${RED}'[!] Issue with apt-get install'${RESET} 1>&2
git clone -q -b master https://github.com/m4ll0k/Infoga.git /opt/Infoga-git/ \
  || echo -e ' '${RED}'[!] Issue when git cloning'${RESET} 1>&2
python3 /opt/Infoga-git/setup.py install \
  || echo -e ' '${RED}'[!] Issue when python3 installing requirements'${RESET} 1>&2
pushd /opt/Infoga-git/ >/dev/null
git pull -q
popd >/dev/null

##### Install PhoneInfoga
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}PhoneInfoga${RESET}"
curl -s -L "https://github.com/sundowndev/phoneinfoga/releases/download/v2.0.5/phoneinfoga_$(uname -s)_$(uname -m).tar.gz" -o /opt/phoneinfoga.tar.gz \
  || echo -e ' '${RED}'[!] Issue with downloading'${RESET} 1>&2
mkdir /opt/phoneInfoga-git
tar xfv /opt/phoneinfoga.tar.gz -C /opt/phoneInfoga-git/
cp /opt/phoneInfoga-git/PhoneInfoga /usr/bin/phoneinfoga

##### Install youtube-dl
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}youtube-dl${RESET}"
 wget -q https://yt-dl.org/downloads/latest/youtube-dl -O /usr/local/bin/youtube-dl \
  || echo -e ' '${RED}'[!] Issue with downloading'${RESET} 1>&2
chmod a+rx /usr/local/bin/youtube-dl
cp /usr/local/bin/youtube-dl /usr/bin/youtube-dl

##### pip installs

##### Install h8mail
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}h8mail${RESET}"
pip3 install --progress-bar off h8mail \
|| echo -e ' '${RED}'[!] Issue with pip install'${RESET} 1>&2


##### Install twint
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}twint${RESET}"
pip3 install --progress-bar off twint \
|| echo -e ' '${RED}'[!] Issue with pip install'${RESET} 1>&2


##### Install instaLooter
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}twint${RESET}"
pip3 install --progress-bar off instaLooter \
|| echo -e ' '${RED}'[!] Issue with pip install'${RESET} 1>&2

##### Install checkdmarc
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) Installing ${GREEN}checkdmarc${RESET}"
pip3 install --progress-bar off checkdmarc \
|| echo -e ' '${RED}'[!] Issue with pip install'${RESET} 1>&2

########################################### End of script
##### Clean the system
(( STAGE++ )); echo -e "\n ${GREEN}[+]${RESET} (${STAGE}/${TOTAL}) ${GREEN}Cleaning${RESET} the system"
#--- Clean package manager
for FILE in clean autoremove; do apt-get -y -qq "${FILE}"; done
apt-get -y -qq purge $(dpkg -l | tail -n +6 | egrep -v '^(h|i)i' | awk '{print $2}')   # Purged packages
#--- Update slocate database
apt-get -y -qq install locate
updatedb
#--- Reset folder location
cd ~/ &>/dev/null
#--- Remove any history files (as they could contain sensitive info)
history -cw 2>/dev/null
for i in $(cut -d: -f6 /etc/passwd | sort -u); do
  [ -e "${i}" ] && find "${i}" -type f -name '.*_history' -delete
done

##### Done!
echo -e "\n ${YELLOW}[i]${RESET} Don't forget to:"
echo -e " ${YELLOW}[i]${RESET} + Check the log file (Did everything install? Any errors? (${RED}HINT: What's in RED${RESET}? the word 'issue' is in the log?)"
echo -e " ${YELLOW}[i]${RESET} + ${YELLOW}Reboot${RESET}"
(dmidecode | grep -iq virtual) \
  && echo -e " ${YELLOW}[i]${RESET} + Take a snapshot   (Virtual machine detected)"

##### Time taken
finish_time=$(date +%s)
echo -e "\n ${YELLOW}[i]${RESET} Time (roughly) taken: ${YELLOW}$(( $(( finish_time - start_time )) / 60 )) minutes${RESET}"
echo -e " ${YELLOW}[i]${RESET} Stages skipped: $(( TOTAL-STAGE ))"
echo -e '\n'${BLUE}'[*]'${RESET}' '${BOLD}'Done!'${RESET}'\n\a'
exit 0


# TODO:
# add spinner to visualize script didn't Heading
# Add TL packages from sheet
# identify if SSH and suggest running from a screen
# clean up output (only print stages & errors) finish implementing?
