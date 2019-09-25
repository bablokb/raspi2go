#!/bin/bash
# --------------------------------------------------------------------------
# This script creates the USB-gadget by writing to the virtual filesystem
# /sys/kernel/config/usb_gadget
#
# Reference: https://github.com/ckuethe/usbarmory/wiki/USB-Gadgets

# Author: Bernhard Bablok
# License: GPL3
#
# Website: https://github.com/bablokb/raspi2go
#
# --------------------------------------------------------------------------

USBCONF_DIR="/sys/kernel/config/usb_gadget/g1"
NODE="USB0"
C=1

# --- initialize gadget   --------------------------------------------------

init_start() {

  echo 0x1d6b > idVendor  # Linux Foundation
  echo 0x0104 > idProduct # Multifunction Composite Gadget
  echo 0x0100 > bcdDevice # v1.0.0
  echo 0x0200 > bcdUSB    # USB2
  echo 0xEF   > bDeviceClass
  echo 0x02   > bDeviceSubClass
  echo 0x01   > bDeviceProtocol

  # OS descriptors
  mkdir -p os_desc
  echo 1       > os_desc/use
  echo 0xcd    > os_desc/b_vendor_code
  echo MSFT100 > os_desc/qw_sign

  mkdir -p strings/"$LANG_ID"
  echo "$SERIAL_NO" > strings/"$LANG_ID"/serialnumber
  echo "$MANUFACTURER" > strings/"$LANG_ID"/manufacturer 
  echo "$PRODUCT" > strings/"$LANG_ID"/product 

  mkdir -p "configs/c.$C/strings/$LANG_ID"
  echo "$DESCRIPTION" > "configs/c.$C/strings/$LANG_ID/configuration"
  ln -s "configs/c.$C" os_desc
  echo 250 > "configs/c.$C/MaxPower"
}

# --- initialize gadget   --------------------------------------------------

init_end() {
  ls /sys/class/udc > UDC
}

# --- create mass-storage gagdet   -------------------------------------------

create_storage() {
  # create (sparse) backing-file if necessary
  : "${USB_FILE:=/data/usb-mass-storage.img}"
  if [ ! -f "$USB_FILE" ]; then
    mkdir -p "${USB_FILE%/*}"
    dd if=/dev/zero of="$USB_FILE" bs="${USB_FILE_BLOCK_SIZE:-1M}" \
       seek="${USB_FILE_BLOCK_COUNT:-2048}" count=0
    mkfs.${USB_FS_TYPE:-ext4} "$USB_FILE"
  fi

  # configure gadget
  cd "$USBCONF_DIR"
  mkdir -p "functions/mass_storage.$NODE"
  echo 1 > "functions/mass_storage.$NODE/stall"
  echo 0 > "functions/mass_storage.$NODE/lun.0/cdrom"
  echo 0 > "functions/mass_storage.$NODE/lun.0/ro"
  echo 0 > "functions/mass_storage.$NODE/lun.0/nofua"
  echo "$USB_FILE" > "functions/mass_storage.$NODE/lun.0/file"

  ln -s "functions/mass_storage.$NODE" "configs/c.$C/"
}

# --- create serial gadget   -------------------------------------------------

create_serial() {
  mkdir -p "functions/acm.$NODE"
  ln -s "functions/acm.$NODE" "configs/c.$C/"
}

# --- create network gadget   ------------------------------------------------

create_network() {
  mkdir -p "functions/rndis.$NODE/os_desc/interface.rndis"

  echo RNDIS > "functions/rndis.$NODE/os_desc/interface.rndis/compatible_id"
  echo 5162001 > "functions/rndis.$NODE/os_desc/interface.rndis/sub_compatible_id"

  ln -s "functions/rndis.$NODE configs/c.$C/"
}

# --- create keyboard (Human Interface Device: HID) gadget   -----------------

create_hid() {
  cd "$USBCONF_DIR"
  mkdir -p functions/hid.$NODE

  echo 1 > "functions/hid.$NODE/protocol"
  echo 1 > "functions/hid.$NODE/subclass"
  echo 8 > "functions/hid.$NODE/report_length"
  echo -ne "\\x05\\x01\\x09\\x06\\xa1\\x01\\x05\\x07\\x19\\xe0\\x29\\xe7\\x15\\x00\\x25\\x01\\x75\\x01\\x95\\x08\\x81\\x02\\x95\\x01\\x75\\x08\\x81\\x03\\x95\\x05\\x75\\x01\\x05\\x08\\x19\\x01\\x29\\x05\\x91\\x02\\x95\\x01\\x75\\x03\\x91\\x03\\x95\\x06\\x75\\x08\\x15\\x00\\x25\\x65\\x05\\x07\\x19\\x00\\x29\\x65\\x81\\x00\\xc0" > "functions/hid.$NODE/report_desc"

  ln -s "functions/hid.$NODE" "configs/c.$C/"
}

# ---- main program   --------------------------------------------------------

# source configuration file
. /etc/raspi2go.conf

# load modules
modprobe libcomposite
sleep 1

# initialize gadget
mkdir -p "$USBCONF_DIR"
cd "$USBCONF_DIR"
init_start

# create configuration
[ "$USB_MASS_STORAGE" = 1 ] && create_storage
[ "$USB_SERIAL" = 1 ]       && create_serial
[ "$USB_ETHERNET" = 1 ]     && create_network
[ "$USB_HID" = 1 ]          && create_hid

init_end

# start additional services
[ "$USB_SERIAL" = 1 ] && systemctl start serial-getty@ttyGS0.service
