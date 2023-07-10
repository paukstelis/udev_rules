#!/bin/bash
#MIT License

#Copyright (c) 2022 Paul Paukstelis

#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:

#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.

#HE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.

if (( $EUID != 0 )); then
    echo "Please run as root (sudo)"
    exit
fi


# from stackoverflow.com/questions/3231804
prompt_confirm() {
    while true; do
        read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
        case $REPLY in
            [yY]) echo ; return 0 ;;
            [nN]) echo ; return 1 ;;
            *) printf " \033[31m %s \n\033[0m" "invalid input"
        esac
    done
}

detect_printer() {
    echo
    echo
    dmesg -C
    echo "Plug your printer in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$UDEV" ]] && [[ $counter -lt 60 ]]; do
        TEMPUSB=$(dmesg | sed -n -e 's/^.*\(cdc_acm\|ftdi_sio\|ch341\|cp210x\) \([0-9].*[0-9]\): \(tty.*\|FTD.*\|ch341-uart.*\|cp210x\).*/\2/p')
        UDEV=$(dmesg | sed -n -e 's/^.*GerialNumber: //p')
        counter=$(( $counter + 1 ))
        if [[ -n "$TEMPUSB" ]] && [[ -z "$UDEV" ]]; then
            break
        fi
        sleep 1
    done
    dmesg -C
}

detect_camera() {
    echo
    echo
    echo "Verify the camera is currently unplugged from USB....."
    if prompt_confirm "Is the camera you are trying to detect unplugged from USB?"; then
        readarray -t c1 < <(ls -1 /dev/v4l/by-id/*index0 2>/dev/null)
    fi
    dmesg -C
    echo "Plug your camera in via USB now (detection time-out in 1 min)"
    counter=0
    while [[ -z "$CAM" ]] && [[ $counter -lt 60 ]]; do
        CAM=$(dmesg | sed -n -e 's/^.*SerialNumber: //p')
        TEMPUSBCAM=$(dmesg | sed -n -e 's|^.*input:.*/\(.*\)/input/input.*|\1|p')
        counter=$(( $counter + 1 ))
        if [[ -n "$TEMPUSBCAM" ]] && [[ -z "$CAM" ]]; then
            break
        fi
        sleep 1
    done
    readarray -t c2 < <(ls -1 /dev/v4l/by-id/*index0)
    #https://stackoverflow.com/questions/2312762
    #TODO: what if there is more than one element?
    BYIDCAM=(`echo ${c2[@]} ${c1[@]} | tr ' ' '\n' | sort | uniq -u `)
    echo "V4L camera detected at $BYIDCAM"
    dmesg -C
}

do_printer() {
    echo "Enter the name for new printer/instance (no spaces):"
    read INSTANCE
    if [ -z "$INSTANCE" ]; then
        echo "No instance given. Exiting" 
        exit 1
    fi
    
    if prompt_confirm "Begin auto-detect printer serial number for udev entry?"
    then
        echo
        detect_printer
    else
        echo "OK. Restart when you are ready" ; exit 0
    fi
    
    if [ -z "$UDEV" ]; then
        echo "Printer Serial Number not detected"
        prompt_confirm "Do you want to use the physical USB port to assign the udev entry? If you use this any USB hubs and printers detected this way must stay plugged into the same USB positions on your machine as they are right now" || exit 0
        echo
        USB=$TEMPUSB
        echo "Your printer will be setup at the following usb address:"
        echo $USB 
        echo
    else
        echo "Serial number detected as: $UDEV" 
    fi
    
    echo
    
    if prompt_confirm "Ready to write udev entry. Do you want to proceed?"
    then
        #Printer udev identifier technique - either Serial number or USB port
        #Serial Number
        if [ -n "$UDEV" ]; then
            #echo $UDEV
            echo SUBSYSTEM==\"tty\", ATTRS{serial}==\"$UDEV\", SYMLINK+=\"printer_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
            echo This printer can now always be found at /dev/printer_$INSTANCE
        fi
        
        #USB port
        if [ -n "$USB" ]; then
            #echo $USB
            echo KERNELS==\"$USB\",SUBSYSTEM==\"tty\",SYMLINK+=\"printer_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
            echo This printer can now always be found at /dev/printer_$INSTANCE
        fi
        
        #Reset udev
        udevadm control --reload-rules
        udevadm trigger
        
    fi
    main_menu
}

do_camera() {
    echo "Unplug the camera you are going to install if is already plugged in"
    echo "Enter the name for new camera (no spaces):"
    read INSTANCE
    if [ -z "$INSTANCE" ]; then
        echo "No instance given. Exiting" 
        exit 1
    fi
    
    
    if prompt_confirm "Begin auto-detect printer serial number for udev entry?"
    then
        echo
        detect_camera
    else
        echo "OK. Restart when you are ready" ; exit 0
    fi
    
    #Failed state. Nothing detected
    if [ -z "$CAM" ] && [ -z "$TEMPUSBCAM" ] ; then
        echo
        echo -e "\033[0;31mNo camera was detected during the detection period.\033[0m"
        echo
        return
    fi
    
    if [ -z "$CAM" ]; then
        echo "Camera Serial Number not detected" 
        echo -e "Camera will be setup with physical USB address of \033[0;34m $TEMPUSBCAM.\033[0m" 
        echo "The camera will have to stay plugged into this location." 
        USBCAM=$TEMPUSBCAM
    else
        echo -e "Camera detected with serial number: \033[0;34m $CAM \033[0m" 
        check_sn "$CAM"
    fi
    
    #Serial Number
    if [ -n "$CAM" ]; then
        echo SUBSYSTEM==\"video4linux\", ATTRS{serial}==\"$CAM\", ATTR{index}==\"0\", SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
    #USB port camera
    if [ -n "$USBCAM" ]; then
        echo SUBSYSTEM==\"video4linux\",KERNELS==\"$USBCAM\", SUBSYSTEMS==\"usb\", ATTR{index}==\"0\", DRIVERS==\"uvcvideo\", SYMLINK+=\"cam_$INSTANCE\" >> /etc/udev/rules.d/99-octoprint.rules
    fi
    
    echo "Camera rule written. The camera will now be found at /dev/cam_$INSTANCE"
    #Reset udev
    udevadm control --reload-rules
    udevadm trigger
    main_menu
}

main_menu() {
    VERSION=0.0.2
    #reset
    UDEV=''
    TEMPUSB=''
    CAM=''
    TEMPUSBCAM=''
    INSTANCE=''
    echo
    echo
    echo "*************************"
    echo "udev_rules $VERSION"
    echo "*************************"
    echo
    PS3='Select udev rule to create: '
    
    options=("Printer rule" "USB camera rule" "Quit")
    
    
    select opt in "${options[@]}"
    do
        case $opt in
            "Printer rule")
                do_printer
            break ;;
            "USB camera rule")
                do_camera
            break ;;
            "Quit")
                exit 1
            ;;
            *) echo "invalid option $REPLY";;
        esac
        
    done
}

main_menu