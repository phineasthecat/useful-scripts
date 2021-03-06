#!/bin/bash

# Armbian zram and log2zram installer script
# Requires Debian Jessie or newer and must be run by root or sudo
# By Franics Theodore Catte, 2019.
# system_prep function borrowed in part from armbian-hardware-optimization script

# functions

system_prep() {
	# set io scheduler
	for i in $( lsblk -idn -o NAME | grep -v zram ); do
		read ROTATE </sys/block/$i/queue/rotational
		case ${ROTATE} in
			1) # mechanical drives
				echo cfq >/sys/block/$i/queue/scheduler
				echo -e "[\e[0;32m ok \x1B[0m] Setting cfg I/O scheduler for $i"
				;;
			0) # flash based
				echo noop >/sys/block/$i/queue/scheduler
				echo -e "[\e[0;32m ok \x1B[0m] Setting noop I/O scheduler for $i"
				;;
		esac
	done

	CheckDevice=$(for i in /var/log /var / ; do findmnt -n -o SOURCE $i && break ; done)
	# adjust logrotate configs
	if [[ "${CheckDevice}" == "/dev/zram0" || "${CheckDevice}" == "armbian-ramlog" ]]; then
		for ConfigFile in /etc/logrotate.d/* ; do sed -i -e "s/\/log\//\/log.hdd\//g" "${ConfigFile}"; done
		sed -i "s/\/log\//\/log.hdd\//g" /etc/logrotate.conf
	else
		for ConfigFile in /etc/logrotate.d/* ; do sed -i -e "s/\/log.hdd\//\/log\//g" "${ConfigFile}"; done
		sed -i "s/\/log.hdd\//\/log\//g" /etc/logrotate.conf
	fi

	# unlock cpuinfo_cur_freq to be accesible by a normal user
	prefix="/sys/devices/system/cpu/cpufreq"
	for f in $(ls -1 $prefix 2> /dev/null)
	do
		[[ -f $prefix/$f/cpuinfo_cur_freq ]] && chmod +r $prefix/$f/cpuinfo_cur_freq 2> /dev/null
	done
	# older kernels
	prefix="/sys/devices/system/cpu/cpu0/cpufreq/"
	[[ -f $prefix/cpuinfo_cur_freq ]] && chmod +r $prefix/cpuinfo_cur_freq 2> /dev/null

	# enable compression where not exists
	find /etc/logrotate.d/. -type f | xargs grep -H -c 'compress' | grep 0$ | cut -d':' -f1 | xargs -L1 sed -i '/{/ a compress'
	sed -i "s/#compress/compress/" /etc/logrotate.conf


	# tweak ondemand cpufreq governor settings to increase cpufreq with IO load
	grep -q ondemand /etc/default/cpufrequtils
	if [ $? -eq 0 ]; then
		echo ondemand >/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
		cd /sys/devices/system/cpu
		for i in cpufreq/ondemand cpu0/cpufreq/ondemand cpu4/cpufreq/ondemand ; do
			if [ -d $i ]; then
				echo 1 >${i}/io_is_busy
				echo 25 >${i}/up_threshold
				echo 10 >${i}/sampling_down_factor
				echo 200000 >${i}/sampling_rate
			fi
		done
	fi
}

if ! [ 'cat /proc/modules | grep zram  &> /dev/null' ]; then
	# try and enable zram module if possible
	if insmod zram ; then
		echo -e 'zram\nlz4_compress\nlz4_decompress\nlz4hc_compress\nlz4\nlz4hc' >> /etc/modules
	fi
fi

# doublecheck if zram is enabled
if ! [ 'cat /proc/modules | grep zram  &> /dev/null' ]; then
	echo "It appears your kernel has no zram support; please install the zram kernel module!"
	exit 0
fi

# housekeeping
apt -y install rsync cpufrequtils
system_prep

# copy armbian scripts
mkdir /usr/lib/armbian
cp ./scripts/armbian-ramlog /usr/lib/armbian
cp ./scripts/armbian-zram-config /usr/lib/armbian
cp ./scripts/armbian-truncate-logs /usr/lib/armbian
cp ./scripts/armbian-common /usr/lib/armbian

# copy default configs
cp ./configs/armbian-ramlog.dpkg-dist  /etc/default/armbian-ramlog
cp ./configs/armbian-zram-config.dpkg-dist /etc/default/armbian-zram-config
cp ./configs/armbian-release /etc

# setup cronjobs
cp ./cron/armbian-truncate-logs /etc/cron.d/
cp ./cron/armbian-ram-logging /etc/cron.daily/
systemctl restart cron

# setup systemd services
cp ./services/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable armbian-ramlog armbian-zram-config
systemctl start armbian-ramlog armbian-zram-config

