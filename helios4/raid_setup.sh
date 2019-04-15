#!/bin/bash

LOG="./raid_setup.log"
CONTAINER="five-nines"

echo "WARNING!!! This will wipe ALL /dev/sdX disks!!"
read -p "Press CTRL+C to quit, or any other key to continue." -n1 -s

if [[ $EUID -ne 0 ]]; then
	echo -e "You need to run this script as root, or with sudo!\nExiting..."
	exit 1
fi

echo "A full log will be available in $LOG"

echo "Installing some necessary software.." 2>&1 | tee $LOG
apt update && apt install -y e2fsprogs mdadm pv smartmontools btrfs-tools hdparm

echo "Wiping all disks…" 2>&1 | tee $LOG
for Dev in /sys/block/sd* ; do
	[-e $Dev]
	&& pv -tpreb /dev/zero | dd of=/dev/${Dev##*/} bs=4096 conv=notrunc,noerror 2>&1 | tee $LOG
	&& sleep 2
done

echo "Running disk checks…" 2>&1 | tee $LOG
for Dev in /sys/block/sd* ; do
	[-e $Dev]
	&& badblocks -sv -t 0x00 /dev/${Dev##*/} 2>&1 | tee $LOG
	&& smartctl -t long -C /dev/${Dev##*/} 2>&1 | tee $LOG
	&& smartctl -H /dev/${Dev##*/} 2>&1 | tee $LOG
	&& smartctl -l selftest /dev/${Dev##*/} 2>&1 | tee $LOG
	&& sleep 2
done

echo "Setting up partitions…" 2>&1 | tee $LOG
for Dev in /sys/block/sd* ; do
	[-e $Dev]
	&& parted /dev/${Dev##*/} mklabel gpt 2>&1 | tee $LOG
	&& parted -a optimal /dev/${Dev##*/} mkpart primary 0% 100% 2>&1 | tee $LOG
	&& sleep 2
done

echo "Assembling RAID array…" 2>&1 | tee $LOG 
disks=()
for Dev in /sys/block/sd* ; do
	disks+=("/dev/${Dev##*/}")
done

mdadm --create --verbose /dev/md0 --level=6 --raid-devices=${#disks[@]}  ${disks[*]} 2>&1 | tee $LOG

echo "Installing required libraries for cryptodev and cryptsetup compilation…" 2>&1 | tee $LOG
# uncomment source repositories and install required libraries
sed -e "s/^# deb/deb/g" /etc/apt/sources.list
apt update && apt install -y build-essential uuid-dev libdevmapper-dev libpopt-dev pkg-config libgcrypt-dev libblkid-dev build-essential fakeroot devscripts debhelper install linux-headers-next-mvebu git

echo "Loading the Marvel CESA module and enabling it on boot…"  2>&1 | tee $LOG
modprobe marvell_cesa
echo "marvell_cesa" >> /etc/modules

echo "Downloading, compiling, and installing Cryptodev…" 2>&1 | tee $LOG
git clone https://github.com/cryptodev-linux/cryptodev-linux.git
cd cryptodev-linux/
make
make install
depmod -a
modprobe cryptodev
echo "cryptodev" >> /etc/modules
cd ..

echo "Downloading, compiling, and installing Cryptsetup 2…" 2>&1 | tee $LOG
wget -q -O - https://gitlab.com/cryptsetup/cryptsetup/-/archive/master/cryptsetup-master.tar.gz | tar xvzf &
cd cryptsetup-master/
./configure --prefix=/usr/local
ldconfig
cd ..

#don't continue until RAID sync completes.
spin='-\|/'
echo "Waiting for RAID sync to complete. This may take a while…" 2>&1 | tee $LOG
while [ -n "$(mdadm --detail /dev/md0 | grep -ioE 'State :.*resyncing')" ]; do
	i=$(( (i+1) %4 ))
	printf "\r${spin:$i:1}"
	sleep .1
done
echo "RAID sync complete!" 2>&1 | tee $LOG

echo -e "Creating crypt container.\nEnter passkey when prompted…" 2>&1 | tee $LOG
cryptsetup -v -y -c aes-cbc-essiv:sha256 -s 256 -- sector-size 4096 --type luks2 luksFormat /dev/md0 2>&1 | tee $LOG

echo -e "Opening crypt container and wiping it.\nAgain, enter passkey when prompted…" 2>&1 | tee $LOG
pv -tpreb /dev/zero | dd of=/dev/mapper/$CONTAINER bs=4096 conv=notrunc,noerror

echo "Formatting crypt container as btrfs…" 2>&1 | tee $LOG
mkfs.btrfs -s 4096 -d single -L CONTAINER /dev/mapper/$CONTAINER

echo "Mounting btrfs partition to /mnt/$CONTAINER" 2>&1 | tee $LOG
mkdir /mnt/$CONTAINER
mount /dev/mapper/$CONTAINER /mnt/$CONTAINER

echo  -e "All done!\nTo mount the crypt container just type the following in terminal as root:\ncryptsetup luksOpen /dev/md0 $CONTAINER\nmount /dev/mapper/$CONTAINER /mnt/$CONTAINER" 2>&1 | tee $LOG

exit 0

