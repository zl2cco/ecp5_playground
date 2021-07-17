#include <stdint.h>
#include "mini-printf.h"

#define LED (*(volatile uint32_t*)0x02000000)

#define reg_uart_clkdiv (*(volatile uint32_t*)0x02000004)
#define reg_uart_data (*(volatile uint32_t*)0x02000008)

#define sdram ((volatile uint32_t*)0x03000000) // 32'h0300_0000 - 32'h0310_0000

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

int nbits = 32;         /* length of arr in bits */
int nscratch = 11;   /* length of scratch in bytes */
char scratch[12];
uint16_t arr[2];
void double_dabble()
{
    int i, j, k;
    int smin = nscratch-2;    /* speed optimization */

    for (i=0; i < 2; ++i) {
        for (j=0; j < 16; ++j) {
            /* This bit will be shifted in on the right. */
            int shifted_in = (arr[i] & (1 << (15-j)))? 1: 0;

            /* Add 3 everywhere that scratch[k] >= 5. */
            for (k=smin; k < nscratch; ++k)
              scratch[k] += (scratch[k] >= 5)? 3: 0;

            /* Shift scratch to the left by one position. */
            if (scratch[smin] >= 8)
              smin -= 1;
            for (k=smin; k < nscratch-1; ++k) {
                scratch[k] <<= 1;
                scratch[k] &= 0xF;
                scratch[k] |= (scratch[k+1] >= 8);
            }

            /* Shift in the new bit from arr. */
            scratch[nscratch-1] <<= 1;
            scratch[nscratch-1] &= 0xF;
            scratch[nscratch-1] |= shifted_in;
        }
    }

    /* Remove leading zeros from the scratch space. */
    for (k=0; k < nscratch-1; ++k)
      if (scratch[k] != 0) break;
    nscratch -= k;

    for (i=0; i<nscratch+1; i++)
        scratch[i] = scratch[i+k];
//    memmove(scratch, scratch+k, nscratch+1);

    /* Convert the scratch space from BCD digits to ASCII. */
    for (k=0; k < nscratch; ++k)
      scratch[k] += '0';
    scratch[nscratch] = 0;

    return;
}

void delay() {
    for (volatile int i = 0; i < 250000; i++)
        ;
}

void test_sdram(uint32_t start, uint32_t len) {
    print("SDRAM test\n");

    uint32_t errors=0;
    uint32_t last=start;

    print("START  : "); printhex(start); print("\n");
    print("LENGTH : "); printhex(len); print("\n");

    printhex(start); print(" : ");
    for (uint32_t address=start; address < start+len; address++) {
        sdram[address] = address;
        print(".");
        if ((address - last) == LINE_WIDTH) {
            last = address+1;
            print("\n");
            printhex(address+1); print(" : ");
        }
    }

    delay();
    print("\nRead and Compare\n");
    last = start;
    printhex(start); print(" : ");
    for (uint32_t address=start; address < start+len; address++) {
        if (sdram[address] == address)
           print(".");
        else {
           print("x");
           errors++;
        }

        if ((address - last) == LINE_WIDTH) {
            last = address+1;
            print("\n");
            printhex(address+1); print(" : ");
        }
    }

    print("\n");

    print("Finish SDRAM test\n");
    print("Errors found: "); printhex(errors); print("\n\n\n\n");
}

int main() {
    uint32_t start = 0;
    uint32_t step  = LINE_WIDTH;

    reg_uart_clkdiv = 434;

    delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();
    
    print("Test BSS section...");
    time = 0;
    uint32_t start_time = time;
    for (uint32_t i=0; i<1000000; i++) {
        sdram[i] = i;
    }
    uint32_t end_time = time;

    arr[0] = (uint16_t)(0x0000FFFF&((end_time - start_time) >> 16));
    arr[1] = (uint16_t)(0x0000FFFF&((end_time - start_time)));
    double_dabble();
    print(scratch);

    print("\n\n\nTime to write (ticks per 10000) : "); printhex(end_time - start_time);

    start_time = time;
    for (uint32_t i=0; i<1000000; i++) {
        if (sdram[i] != i) print("E");
    }
    end_time = time;

    print("\nTime to read (ticks per 10000) : "); printhex(end_time - start_time);

    print("\n....DONE\n\n");

    delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();
    delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();
    delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();

//    test_sdram(0, 0x00100000);

    while (1) {
        LED = 0xFF;
        delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();
        LED = 0x00;

        test_sdram(start, step);
        start = start + step;
        if (start > (0x00100000 - step)) start = 0;

        delay();delay();delay();delay();delay();delay();delay();delay();delay();delay();
    }
}
