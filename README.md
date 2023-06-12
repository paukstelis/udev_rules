# udev_rules
This is a stand-alone bash script for creating udev rules for 3D printers (or other devices) and USB web cameras. It is useful for host control software like OctoPrint to bind a udev rule to a specific printer or camera.

## Usage
The script requires administrator rights to write the rules. Run the script with `sudo ./udev_rules.sh` and follow the instructions. If a device does not have an exposed serial number, the physical USB address will be used instead. In those cases, devices MUST remain in the same USB positions to be correctly identified.
