#!/bin/bash

# This bash script was used to open or create an encrypted drive using Argon2 to derive a 256bit keyfile then
# using cryptsetup and LUKS2 to perform the actual encryption/decryption.

# It was written with the intention of using it as part of a liveUSB setup which included a seperate storage
# partition. Before closing the system the user can run the close_enc.sh script which will encrypt the partitions
# header making it appear as an unformatted partition providing some plausible deniability.

# This was my first proper bash script experimenting with password hashing, key generation and encryption. It's potentially
# flawed in some way, overkill, inefficient and definitely needs refining. I've not used it for a while now but re-looking
# at it I'm already resisting the urge to update and improve it. I may well update and improve it in the future.

# It works as follows:

# User inputs a password and then a pin number.

# Argon2 is configured to take approx 1 second on a Intel Core i3 CPU running at 2.3Ghz. This is to
# provide some brute-force resistance to the password/key file generation process.

# Argon2 takes a salt which has been used as a form of two factor authentication in the keyfile generation process.

# The second input is a pin number which is used to select 256 bytes from a different data source
# (another drive in this case but it could be a file if this script was so modified). At the moment this number
# must be at least 4 digits and start with anything greater than 0, eg 1000+...

# The alternative source is currently configured to be a block device containing random bytes which don’t
# change (the idea being the existence of a drive containing only random data provides some plausible deniability
# in the event of compromise).

# You could modify the script to accept bytes from a specific file if required...

# This ‘random’ salt, which the user selected using the number, is combined with the users password to derive
# the final keyfile which is used to open the LUKs partition.

# Without the password or the source from which the salt is obtained the final key cannot be generated.

# The user then selects the salt source, selecting another partition/block device containing random data eg. sdb1…

# The users password and the salt are then hashed together using sha256 to produce the actual 256bit password passed to Argon2.

# The user then selects a mount point which is within /media/ eg enc.

# Argon2 is then initiated using the password and salt. The process takes about 1 second however you could modify
# $ints and $mem to vary this. The outputted data is saved to a file named pwd stored in the ramdisk.

# Cryptsetup is configured to use LUKs2 and also using Argon2 to derive the final key from the keyfile, this process
# takes about 10 seconds with 650 iterations and 16384 memory. Cryptsetup uses aes-xts-plain64be which I 'think' is
# the most secure.

# The user is then presented with the option of either formatting the selected partition or mounting it using
# cryptsetup.

# To format the selected partition the user must type YES in uppercase – to prevent accidental formatting.
# The drive is formatted using ext4 and mounted to whatever the user input as the mount point and is ready to be used.

# Otherwise cryptsetup checks to see if the selected partition is a LUKs partition and tries to mount the drive
# using the generated keyfile.

# If the drive is not a valid LUKs partiton the script will backup the first 4Mb of the drive (the header)
# and then attempt to decrypt it using openssl - close_enc.sh can be used to encrypt the header.

# Once again the script will check that the header is a valid LUKs partition, if so the now decrypted header will
# be written to the partition and mounted using the keyfile. This prevents the user from accidentally selecting
# the wrong partition, overwriting the header with garbage and then causing themself a load of grief!

# This script should be run as root.

# This script is provided as is and without any warranty. Use it at your own peril.

# It should NOT be used in a serious security setup unless you have validated the code and are happy with how it
# works and the limitations therein. This script should be encrypted or hidden in some way otherwise an attacker
# could read it and will know that drives containing 'random' data may not be so random after all.

# You are free to use, edit and redistribute as you see fit.

# Author: James @ www.nooneshere.co.uk
# Date: 2018


# Argon2 params (takes 1s to calculate password hash using an Intel Core I3 CPU @ 2.3Ghz)
ints=1500
mem=5

# Mount a usable 250mb folder in ram
sudo mkdir /media/ram
sudo mount -t tmpfs -o size=250M tmpfs /media/ram/

# Install Argron2 for KDF if not already installed
if [ "$(type argon2)" != "argon2 is /usr/bin/argon2" ]
then
sudo apt install argon2
fi

echo "Mount or encrypt drive..."
echo "Type 'exit' to quit."
echo

# Obtain user password and check input
read -sp "Input password: " pwd
echo

# Exit if exit typed
if [ "$pwd" == "exit" ]
then
    echo "Exiting..."
    exit
fi

# Skip bytes for generating password salt $pin_num
read -sp "Enter PIN (must not start with a 0): " pin_num
echo

# Check if not a number then exit with error
re='^[0-9]+$'
if ! [[ $pin_num =~ $re ]] ; then
   echo "error: Not a number" >&2; exit 1
fi

# 
pin_num=$(( ($pin_num * 5) -745 ))

# Select keyfile source $kfsrce
echo
lsblk
echo

read -p "Password salt source eg. sdx#: " kfsrce
echo

# IF not a block device exit
if [ ! -b "/dev/$kfsrce" ]
then
	echo "Not a block device... Exiting!"
	exit
fi

read -p "Select drive to open/encrypt eg. sdx#: " e_drv
echo

# IF not a block device exit
if [ ! -b "/dev/$e_drv" ]
then
	echo "Not a block device... Exiting!"
	exit
fi

# Obtain cryptsetup map
read -p "Input drive mount point under /media/ eg enc: " map
echo

# IF not no map given then exit
if [ "$map" == "" ]
then
	echo "No map specified... Exiting!"
	exit
fi

# Exit if exit typed
if [ "$map" == "exit" ]
then
    echo "Exiting..."
    exit
fi

# Get 256byte salt from drive random data source (repalce null with newline)
salt="$(sudo dd if=/dev/$kfsrce skip=$pin_num bs=192 count=1 iflag=skip_bytes status=none | tr '\0' '\n' | base64 -w 0)"


# Hash the password with a random salt sha256
pwd="$(echo $pwd$salt | sha256sum | head -c64)"

echo "Generating keyfile... Please wait..."
echo

# Hash the password with a salt using Argon2i and generate a keyfile with raw data
echo -n $pwd | argon2 $salt -id -t $ints -m $mem -p 4 -l 32 -r | perl -ne 's/([0-9a-f]{2})/print chr hex $1/gie' > /media/ram/pwd

echo "Keyfile generated!"

# Ask to format the drive if new drive/data
echo
read -p "New device, format?? ALL DATA WILL BE LOST!! Type 'YES' otherwise ignore: " fmat
echo

if [ "$fmat" == "YES" ]
then
    echo "Creating new encrypted device..."
 # Use Argon2id with 650 interations and 16384kb memory
    sudo cryptsetup luksFormat /dev/$e_drv /media/ram/pwd --type luks2 --hash sha512 --cipher aes-xts-plain64be --key-size 512 --sector-size 4096 --use-random --pbkdf argon2id --pbkdf-force-iterations 650 --pbkdf-memory 16384


# Open the encrypted device
    sudo cryptsetup open /dev/$e_drv $map --type luks2 --key-file /media/ram/pwd

# Format device with ext4 file system
	sudo mkfs -t ext4 /dev/mapper/$map

# Mount device
	sudo mkdir /media/$map
	sudo mount /dev/mapper/$map /media/$map
	sudo chown -R laptop /media/$map

else
# Open the encrypted device

# Check if Luks header is valid
    if [[ "$(sudo cryptsetup -v isLuks /dev/$e_drv)" = "Command successful." ]]
    then
    # Open encrypted device
        echo "Opening device..."
        sudo cryptsetup open /dev/$e_drv $map --type luks2 --key-file /media/ram/pwd

    # Mount encrypted device
        sudo mkdir /media/$map
        sudo mount /dev/mapper/$map /media/$map
        sudo chown -R laptop /media/$map
    else
    # Decrypt header using pwd

		# Backup 4mb header in case wrong drive selected
		echo "Backing up header to /media/ram/backup.h..."
		sudo dd if=/dev/$e_drv of=/media/ram/backup.h bs="$(( 1024*1024*4 ))" count=1 status=none

    # Get encrypted header from drive
        echo "Getting encrypted header from device"
        sudo dd if=/dev/$e_drv of=/media/ram/head_$map.c bs="$(( 1024*1024*4 ))" count=1 status=none

    # Decrypt header using keyfile
        echo "Decrypting header file with pwd..."
        key="$(sha256sum /media/ram/pwd | head -c64)";  iv="$(sha256sum /media/ram/pwd | head -c4)"
        sudo openssl enc -d -aes-256-cbc -in /media/ram/head_$map.c -out /media/ram/head_$map.h -nopad -nosalt -K $key -iv $iv
        
    # Check if header decrypted to luks header
        if [[ "$(sudo cryptsetup -v isLuks /media/ram/head_$map.h)" = "Command successful." ]]
        then
        # Restore decrypted LUKs header (if wrong drive selected restore with backup.h)
            echo "Restoring decrypted header..."
            sudo dd if=/media/ram/head_$map.h of=/dev/$e_drv bs="$(( 1024*1024*4 ))" count=1 status=none
            
            # Shred the temp headder files
            sudo shred -fun 5 /media/ram/head_$map.h
			sudo shred -fun 5 /media/ram/head_$map.c

        # Open encrypted device
            echo "Opening device..."
            sudo cryptsetup open /dev/$e_drv $map --type luks2 --key-file /media/ram/pwd
            echo "Done - now mounting device"

        # Mount encrypted device
            sudo mkdir /media/$map
            sudo mount /dev/mapper/$map /media/$map
            sudo chown -R laptop /media/$map
            echo "Mounted!"

        else
            echo "Wrong password used, exiting..."
        fi

    fi

fi

# Clean up variables and files generated
echo "Clearing variables and files"
key="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
iv="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
pin_num="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
salt="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
pwd="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"

# sudo shred -fun 5 /media/ram/pwd

# Remove the tmp ramdisk
sudo umount -lf /media/ram
sudo rmdir --ignore-fail-on-non-empty /media/ram

echo "Completed...!"