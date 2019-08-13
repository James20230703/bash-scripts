#!/bin/bash

# This script complements open_enc.sh and is used to unmount the encrypted partition and optionally encrypt
# the partition header providing some plausible deniability.

# 4Mb is copied from the drive header and then encrypted using openssl and the keyfile and written back.

# Openssl is configured so that the header size does not change. No padding or salt is used. Probably not the
# most secure option however if it's size were to change it could overwrite more data and actually corrupt the
# drive.

# Encrypting the header in this way is not intended to secure the underlying data, that is done by the LUKs
# encryption itself.

# This additional process is intended to obscure the header of the drive from forensic analysis by implying
# that the drive contains only random/unformatted data. I’m not a forensic examiner so this may not be the
# right way to achieve this - this script was written as an experiment

# This script is provided as is and without any warranty. Use it at your own peril.
# It should not be used in a serious security setup unless you have validated the code and are happy with how it
# works and the limitations therein.

# You are free to use, edit and redistribute as you see fit.

# Author: James @ www.nooneshere.co.uk
# Date: 2018

echo "Close encrypted device..."
echo "Type 'exit' to quit."

# Mount a usable 250mb folder in ram
sudo mkdir /media/ram
sudo mount -t tmpfs -o size=250M tmpfs /media/ram/

# List mounted encrypted drives
ls /dev/mapper/

# Input the cryptsetup mountpoint
read -p "Input drive map? Eg 'enc': " map
echo

# Exit if exit typed
if [ "$map" == "exit" ]
then
    echo "Exiting..."
    exit
fi

# Unmout and close the drive and remove the mountpoint from /media/
echo "Unmounting and locking $map..."
sudo umount /media/$map
sudo cryptsetup close $map
sudo rmdir /media/$map

echo "Device unmounted and locked..."

read -p "Obsecure device headder? 'Y' or 'N' (default NO): " obs
echo

# Obsecure device headder
if [ "$obs" == "Y" ]
then

	# List devices
	echo
	lsblk
	echo
	
	read -p "Select device to encrypt header using pwd keyfile? Eg. 'sdx#': " e_drv
	echo

	# Backup 4mb header in case wrong drive selected
	echo "Backing up header to /media/ram/backup.h..."
	sudo dd if=/dev/$e_drv of=/media/ram/backup.h bs="$(( 1024*1024*4 ))" count=1 status=none

	# IF the device IS a luks device continue else exit
	if [[ "$(sudo cryptsetup -v isLuks /dev/$e_drv)" = "Command successful." ]]
	then
		# Backup the luks header to file
		echo "Getting device header file..."
	    sudo cryptsetup luksHeaderBackup /dev/$e_drv --header-backup-file /media/ram/head_$map.h

	    # IF KEY generated and available else create new KEY
	    if [ -e /media/ram/pwd ]
	    then

		    # Encrypt luks header
		    echo "Encrypting device header..."
			key="$(sha256sum /media/ram/pwd | head -c64)"
			iv="$(sha256sum /media/ram/pwd | head -c4)"
			sudo openssl aes-256-cbc -in /media/ram/head_$map.h -out /media/ram/head_$map.c -nopad -nosalt -K $key -iv $iv

	    else
	    	# Run script to generate KEY file
	    	./gen_keyfile.sh
	    fi

		# Replace luks header with encrypted header
		echo "Writing encrypted header to /dev/$e_drv..."
		sudo dd if=/media/ram/head_$map.c of=/dev/$e_drv bs="$(( 1024*1024*4 ))" count=1 status=none

		# Shred files for headder encryption
		echo "Shredding files..."
		sudo shred -fun 5 /media/ram/backup.h
		sudo shred -fun 5 /media/ram/head_$map.h
		sudo shred -fun 5 /media/ram/head_$map.c
		sudo shred -fun 5 /media/ram/pwd

		# Remove the tmp ramdisk
		sudo umount -lf /media/ram
		sudo rmdir --ignore-fail-on-non-empty /media/ram

		echo "Device closed and header encrypted..."
	else
		echo "Not a luks device, exiting..."
		exit
	fi

fi

echo "Completed...!"