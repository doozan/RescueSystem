#!/bin/sh

#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
# 	Rescue System Installer
# 	by Jeff Doozan
#
# 	This is a script to write update the kernel and linux system on Pogoplug/DockStar mtd1 and mtd2

MIRROR=http://jeff.doozan.com/debian

VALID_UBOOT_MD5=$MIRROR/uboot/valid-uboot.md5
UIMAGE_MTD1_URL=$MIRROR/rescue/uImage-mtd1.img
ROOTFS_MTD2_URL=$MIRROR/rescue/rootfs-mtd2.img

FLASH_ERASEALL_URL=$MIRROR/uboot/flash_eraseall
NANDWRITE_URL=$MIRROR/uboot/nandwrite
NANDDUMP_URL=$MIRROR/uboot/nanddump
FW_PRINTENV_URL=$MIRROR/uboot/fw_printenv
FW_CONFIG_URL=$MIRROR/uboot/fw_env.config
UBIFORMAT_URL=$MIRROR/rescue/ubiformat


UIMAGE_MTD1=/tmp/uImage-mtd1.img
ROOTFS_MTD2=/tmp/rootfs-mtd2.img

FLASH_ERASEALL=/usr/sbin/flash_eraseall
NANDWRITE=/usr/sbin/nandwrite
NANDDUMP=/usr/sbin/nanddump
FW_PRINTENV=/usr/sbin/fw_printenv
FW_SETENV=/usr/sbin/fw_setenv
FW_CONFIG=/etc/fw_env.config
UBIFORMAT=/usr/sbin/ubiformat


verify_md5 ()
{
  local file=$1
  local md5=$2

  local check_md5=$(cat "$md5" | cut -d' ' -f1) 
  local file_md5=$(md5sum "$file" | cut -d' ' -f1)  

  if [ "$check_md5" = "$file_md5" ]; then
    return 0
  else
    return 1
  fi
}

download_and_verify ()
{
  local file_dest=$1
  local file_url=$2

  local md5_dest="$file_dest.md5"
  local md5_url="$file_url.md5"

  # Always download a fresh MD5, in case a newer version is available
  if [ -f "$md5_dest" ]; then rm -f "$md5_dest"; fi
  wget -O "$md5_dest" "$md5_url"
  # retry the download if it failed
  if [ ! -f "$md5_dest" ]; then
    wget -O "$md5_dest" "$md5_url"
    if [ ! -f "$md5_dest" ]; then
      return 1 # Could not get md5
    fi
  fi

  # If the file already exists, check the MD5
  if [ -f "$file_dest" ]; then
    verify_md5 "$file_dest" "$md5_dest"
    if [ "$?" -ne "0" ]; then
      rm -f "$md5_dest"
      return 0
    else
      rm -f "$file_dest"
    fi
 fi

  # Download the file
  wget -O "$file_dest" "$file_url"
  # retry the download if it failed
  verify_md5 "$file_dest" "$md5_dest"
  if [ "$?" -ne "0" ]; then  
    # Download failed or MD5 did not match, try again
    if [ -f "$file_dest" ]; then rm -f "$file_dest"; fi
    wget -O "$file_dest" "$file_url"
    verify_md5 "$file_dest" "$md5_dest"
    if [ "$?" -ne "0" ]; then  
      rm -f "$md5_dest"
      return 1
    fi
  fi

  rm -f "$md5_dest"
  return 0
}

install ()
{
  local file_dest=$1
  local file_url=$2   
  local file_pmask=$3  # Permissions mask
  
  echo "# checking for $file_dest..."

  # Install target file if it doesn't already exist
  if [ ! -s "$file_dest" ]; then
    echo ""
    echo "# Installing $file_dest..."

    # Check for read-only filesystem by testing
    #  if we can delete the existing 0 byte file
    #  or, if we can create a 0 byte file
    local is_readonly=0
    if [ -f "$file_dest" ]; then
      rm -f "$file_dest" 2> /dev/null
    else
      touch "$file_dest" 2> /dev/null
    fi
    if [ "$?" -ne "0" ]; then
      local is_readonly=0
      mount -o remount,rw /
    fi
    rm -f "$file_dest" 2> /dev/null
        
    download_and_verify "$file_dest" "$file_url"
    if [ "$?" -ne "0" ]; then
      echo "## Could not install $file_dest from $file_url, exiting."
      if [ "$is_readonly" = "1" ]; then
        mount -o remount,ro /
      fi
      exit 1
    fi

    chmod $file_pmask "$file_dest"

    if [ "$is_readonly" = "1" ]; then
      mount -o remount,ro /
    fi

    echo "# Successfully installed $file_dest."
  fi

  return 0
}


if [ -d /usr/local/cloudengines/ -o -f /etc/rescue.version ]; then
  echo "This script must be run from outside your Pogoplug install or Rescue System."
  echo "Please boot from a USB device and try again."
  exit 1
fi

if [ "$1" != "--noprompt" ]; then

  echo ""
  echo "This script will install a rescue system on your NAND."
  echo "It will OVERWRITE ALL OF THE POGOPLUG FILES."
  echo ""
  echo "This script will replace the kernel on on mtd1 and the rootfs on mtd2."
  echo ""
  echo "This installer will only work on a Seagate Dockstar or Pogoplug Pink."
  echo "Do not run this installer on any other device."
  echo ""
  echo "By typing ok, you agree to assume all liabilities and risks "
  echo "associated with running this installer."
  echo ""
  echo -n "If you agree, type 'ok' and press ENTER to continue: "

  read IS_OK
  if [ "$IS_OK" != "OK" -a "$IS_OK" != "Ok" -a "$IS_OK" != "ok" ];
  then
    echo "Exiting. Rescue system was not installed."
    exit 1
  fi

fi

# Install required utilities

install "$NANDWRITE"        "$NANDWRITE_URL"         755
install "$NANDDUMP"         "$NANDDUMP_URL"          755
install "$UBIFORMAT"        "$UBIFORMAT_URL"         755
install "$FLASH_ERASEALL"   "$FLASH_ERASEALL_URL"    755
install "$FW_PRINTENV"      "$FW_PRINTENV_URL"       755
install "$FW_CONFIG"        "$FW_CONFIG_URL"         644
if [ ! -f "$FW_SETENV" ]; then
  ln -s "$FW_PRINTENV" "$FW_SETENV" 2> /dev/null
  if [ "$?" -ne "0" ]; then
    mount -o remount,rw /
    ln -s "$FW_PRINTENV" "$FW_SETENV"
    mount -o remount,ro /
  fi
fi


### Check uBoot

# dump mtd1 and compare the checksum, to make sure it's the latest version
echo "## Verifying new uBoot..."

$NANDDUMP -no -l 0x80000 -f /tmp/uboot-mtd0-dump /dev/mtd0
wget -O "/tmp/valid-uboot.md5" "$VALID_UBOOT_MD5"

CURRENT_UBOOT_MD5=$(md5sum "/tmp/uboot-mtd0-dump" | cut -d' ' -f1)
rm /tmp/uboot-mtd0-dump
UBOOT_IS_CURRENT=$(grep $CURRENT_UBOOT_MD5 /tmp/valid-uboot.md5 | grep current)
rm /tmp/valid-uboot.md5

if [ "$UBOOT_DETAILS" == "" ]; then
  echo "##"
  echo "## uBoot is not up-to-date"
  echo "## Please install the newest uBoot and then re-run this installer."
  echo "##"
  exit 1
else

echo "## uBoot is good"
echo ""
echo "# Downloading Rescue System"


download_and_verify "$UIMAGE_MTD1" "$UIMAGE_MTD1_URL"
if [ "$?" -ne "0" ]; then
  echo "## uImage could not be downloaded, or the MD5 does not match."
  echo "## Exiting. No changes were made to your NAND systems."
  exit 1
fi

download_and_verify "$ROOTFS_MTD2" "$ROOTFS_MTD2_URL"
if [ "$?" -ne "0" ]; then
  echo "## rootfs could not be downloaded, or the MD5 does not match."
  echo "## Exiting. No changes were made to your NAND systems."
  exit 1
fi


echo ""
echo "# Installing Rescue System"
echo ""

$FLASH_ERASEALL /dev/mtd1
$NANDWRITE /dev/mtd1 $UIMAGE_MTD1

if [ "$?" -ne "0" ]; then
  echo "Installation failed."
  exit 1
fi

$FLASH_ERASEALL /dev/mtd2
$UBIFORMAT /dev/mtd2 -s 512 -f $ROOTFS_MTD2 -y

if [ "$?" -ne "0" ]; then
  echo "Installation failed."
  exit 1
fi

# Newer uBoot environments have a 'rescue_installed' flag that we can set
ENV_RESCUE_INSTALLED=`$FW_PRINTENV rescue_installed | cut -d'=' -f 2-`
if [ "$ENV_RESCUE_INSTALLED" != "" ]; then
  $FW_SETENV rescue_installed 1

# Older uBoot environments need to be configured for the rescue image
else
  $FW_SETENV set_bootargs_rescue 'setenv bootargs console=$console ubi.mtd=2 root=ubi0:rootfs ro rootfstype=ubifs $mtdparts'
  $FW_SETENV bootcmd_rescue 'run set_bootargs_rescue; nand read.e 0x800000 0x100000 0x400000; bootm 0x800000'
  $FW_SETENV bootcmd_pogo 'run bootcmd_rescue'
fi


echo "# Rescue System installation has completed successfully."

