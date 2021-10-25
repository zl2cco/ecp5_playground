#include <stdint.h>
#include "mini-printf.h"

#define LED (*(volatile uint32_t*)0x02000000)

#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data (*(volatile uint32_t*)0x02000008)

#define sdram ((volatile uint32_t*)0x03000000) // 32'h0300_0000 - 32'h0310_0000

#define fb_write_buffer ((volatile uint32_t*)0x05000000)
#define fb_line_buffer  ((volatile uint32_t*)0x06000000)


#define time (*(volatile uint32_t*)0x04000000)

#define LINE_WIDTH 127


void putchar(char c)
{
    if (c == '\n')
        putchar('\r');
    reg_uart_data = c;
}

void print(const char *p)
{
    while (*p)
        putchar(*(p++));
}

void printhexbyte(uint8_t byte) {
    char str[2];

    str[1] = 0;

    if (byte <= 9) str[0] = '0' + byte;
    else           str[0] = 'A' + (byte - 10);

    print(str);
}

void printhex(uint32_t n) {
    uint8_t byte;

    print("0x");

    byte = (uint8_t)((n & 0xf0000000) >> 28);
    printhexbyte(byte);
    byte = (uint8_t)((n & 0x0f000000) >> 24);
    printhexbyte(byte);

    byte = (uint8_t)((n & 0x00f00000) >> 20);
    printhexbyte(byte);
    byte = (uint8_t)((n & 0x000f0000) >> 16);
    printhexbyte(byte);

    print(" ");

    byte = (uint8_t)((n & 0x0000f000) >> 12);
    printhexbyte(byte);
    byte = (uint8_t)((n & 0x00000f00) >> 8);
    printhexbyte(byte);

    byte = (uint8_t)((n & 0x000000f0) >> 4);
    printhexbyte(byte);
    byte = (uint8_t)(n & 0x0000000f);
    printhexbyte(byte);

}

void delay() {
    for (volatile int i = 0; i < 250000; i++)
        ;
}

void test_sdram(uint32_t start, uint32_t len) {
    uint32_t errors=0;
    char str[20];
    unsigned int num_cycles, num_instr, cputime_start, cputime_end;
 
    snprintf(str, 20, "%d", len);

    print("SDRAM test: ");
    printhex(start); print(" - "); printhex(start + len - 1);
    print("("); print(str); print(" words) : ");

   	__asm__ volatile ("rdcycle %0; rdinstret %1; rdtime %2" : "=r"(num_cycles), "=r"(num_instr), "=r"(cputime_start));
    for (uint32_t address=start; address < start+len; address++) {
        sdram[address] = address;
    }
    for (uint32_t address=start; address < start+len; address++) {
        if (sdram[address] != address)
           errors++;
    }
   	__asm__ volatile ("rdcycle %0; rdinstret %1; rdtime %2" : "=r"(num_cycles), "=r"(num_instr), "=r"(cputime_end));

    for (uint32_t address=start; address < start+len; address++) {
        if (sdram[address] == address)
           print(".");
        else {
           print("x");
           errors++;
        }
    }

    snprintf(str, 20, "%d", cputime_end - cputime_start);
    print(" Dur: "); print(str);

    snprintf(str, 20, "%d", errors);
    print(" ERRORS: "); print(str); print("\n");
}


void test_fb_buffers() {
    uint32_t errors=0;
    char str[20];
 
    print("Framebuffer test: \nWrite: ");
    for (uint32_t address=0; address < 256; address++) {
        fb_write_buffer[address] = address;
        fb_line_buffer[address] = address;
        if (address & 0x01)
            print("-");
    }
    print("\nRead: ");
    for (uint32_t address=0; address < 256; address++) {
        if ((fb_write_buffer[address] == address) && (fb_line_buffer[address] == address)) {
            if (address & 0x01)
                print(".");
        }
        else {
           print("x");
           errors++;
        }
    }

    snprintf(str, 20, "%d", errors);
    print(" ERRORS: "); print(str); print("\n\n");
}

void test_image() {
    for (uint32_t address=0; address < 256; address++) {
        if (address < 40) {
            fb_line_buffer[address] = 0xf800f800;
        }
        else if (address < 80) {
            fb_line_buffer[address] = 0x7e007e00;
        }
        else if (address < 120) {
            fb_line_buffer[address] = 0x001f001f;
        }
        else if (address < 160) {
            fb_line_buffer[address] = 0x84108410;
        }
        else if (address < 200) {
            fb_line_buffer[address] = 0xffffffff;
        }
        else  {
            fb_line_buffer[address] = 0x00000000;
        }
    }
}

void test_image_blank() {
    for (uint32_t address=0; address < 256; address++) {
        fb_line_buffer[address] = 0x00000000;
    }
}
void test_image_white() {
    for (uint32_t address=0; address < 256; address++) {
        fb_line_buffer[address] = 0xffffffff;
    }
}


int main() {
   uint32_t start = 0;
    uint32_t step  = LINE_WIDTH;
    int state = 0;

    // Set baud rate to 115200 (50MHz/115200 = 434)
    reg_uart_clkdiv = 434;
    

    test_image();

    while (1) {
        for (int i=0; i < 10; i++) delay();
        LED = 0xFF;

        test_sdram(start, step);
        start = start + step;
        if (start > (0x00100000 - step)) start = 0;

//        test_fb_buffers();
        switch (state++) {
            case 0:
                test_image();
                break;
            case 1:
                test_image_blank();
                break;
            case 2:
                test_image();
                break;
            case 3:
                test_image_white();
                break;
            default:
                state = 0;
        }

        LED = 0x00;
    }
}
