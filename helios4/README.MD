### ABOUT:
a couple scripts I use(d) when setting up and maintaining my Helios4 NAS.

these were tailored to my setup, and you should edit them to suit your needs. also note that some of this is untested, so use with caution!!

### USAGE:
raid_setup.sh for creating my RAID setup on a fresh install of Armbian Bionic on a Helios 4
raid_healthcheck.sh will check for btrfs errors and run an md sync, then btrfs check if needed.
dedupe_setup.sh example script for setting up out-of-band btrfs deduplication, using duperemover and cron.

### NOTES:
If you're using Samba shares, I recommend using btrfs subvolumes for shared folders.

Create shared folders as btrfs subvolumes like so (five-nines used as an example):
btrfs subvolume create /mnt/five-nines/@test
brtfs subvolume create /mnt/five-nines/@test/.snapshots

The .snapshot directory allows creating and deleting snapshots like so:
btrfs subvolume snapshot -r /mnt/five-nines/@test /mnt/five-nines/@test/.snapshots/@GMT_`date +%Y.%m.%d-%H.%M.%S`
btrfs subvolume delete /mnt/five-nines/@test/.snapshots/@GMT_2019.04.15-11.55.05

Automating snapshots is possible, too.

Add the following to your samba config under each share to enable previous history in Windows:

> [test]
> 	<-snip->
> 	vfs objects = shadow_copy2
> 	shadow:format = @GMT_%Y.%m.%d-%H.%M.%S
> 	shadow:sort = desc
> 	shadow:snapdir = .snapshots