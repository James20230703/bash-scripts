#!/bin/bash

####################################################################

# Argon2 params (takes 1s to calculate password hash)
ints=1500
mem=5 

# Install argron2 for KDF
if [ "$(type argon2)" != "argon2 is /usr/bin/argon2" ]
then
sudo apt install argon2
fi

echo Mount or encrypt drive...
echo

# Obtain user password and check input
read -sp "Password: " pwd
echo

# Exit if exit typed
if [ "$pwd" == "exit" ]
then
    echo "Exiting..."
    exit
fi

# Skip bytes for generating password salt $pin_num
read -sp "Enter PIN: " pin_num
echo

re='^[0-9]+$'
if ! [[ $pin_num =~ $re ]] ; then
   echo "error: Not a number" >&2; exit 1
fi

pin_num=$(( ($pin_num * 5) -745 ))

# Select keyfile source $kfsrce
echo
lsblk
echo

read -p "Keyfile source eg. sdx#: " kfsrce
echo

# Get 256byte salt from drive random data source (repalce null with newline)
salt="$(sudo dd if=/dev/$kfsrce skip=$pin_num bs=192 count=1 iflag=skip_bytes status=none | tr '\0' '\n' | base64 -w 0)"


# Hash the password with a random salt sha256
pwd="$(echo $pwd$salt | sha256sum | head -c64)"

echo Generating keyfile... Please wait...
echo

# Hash the password with a salt using Argon2i and generate a keyfile with raw data
echo -n $pwd | argon2 $salt -id -t $ints -m $mem -p 4 -l 32 -r | perl -ne 's/([0-9a-f]{2})/print chr hex $1/gie' > /media/ram/pwd

echo Keyfile generated!

key="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
iv="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
pin_num="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
salt="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"
pwd="$(dd if=/dev/urandom bs=128 count=1 status=none | tr '\0' '\n')"