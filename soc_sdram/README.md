# Image processing of video from camera to RGB LCD on an ECP5 i5 board


## PicoRV32

## Memory map
0x00xx-xxxx     RAM
0x02xx-xxxx     IO memory mapped access
    0x0200-0000     LED
0x03xx-xxxx     SDRAM
0x04xx-xxxx     Timer





## UART

By default, the UART is not hooked up to the FTDI.
To make the UART work, you need to solder the following zero-ohm resistors:

* R34
* R35
* R21 (Optional for UART Activity LED)

