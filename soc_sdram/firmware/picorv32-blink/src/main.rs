#![no_std]
#![no_main]

extern crate panic_halt;

use picorv32_pac;
//use led::LED;
use riscv_rt::entry;

//mod timer;
mod led;
mod print;

//use timer::Timer;
use led::Led;


//const SYSTEM_CLOCK_FREQUENCY: u32 = 21_000_000;

// This is the entry point for the application.
// It is not allowed to return.

fn real_main() -> ! {
    let peripherals = picorv32_pac::Peripherals::take().unwrap();

    print::print_hardware::set_hardware(peripherals.UART);
    print::print_hardware::set_divider(434); // Set baud to 1MBaud


    //let mut timer = Timer::new(peripherals.TIMER0);
    let mut led = Led::new(peripherals.LED);
    led.off();

    //let led0 = ledstring.read_rgb(0);
    //println!("r{:#04x} g{:#04x} b{:#04x}", led0.r, led0.g, led0.b);

    let mut div: u32 = 0x00;

    print!("a");
    loop {

        div += 1;
        if div == 3125000 {
            print!("b");
            led.on();
        }
        else if div == 6240000 {
            print!("c");
            led.off();
            div = 0;
        }    
        //leds.toggle();
        //msleep(&mut timer, 160);
    }
}

#[entry]
fn main() -> ! {
    real_main();
}

/*fn msleep(timer: &mut Timer, ms: u32) {
    timer.disable();

    timer.reload(0);
    timer.load(SYSTEM_CLOCK_FREQUENCY / 1_000 * ms);

    timer.enable();

    // Wait until the time has elapsed
    while timer.value() > 0 {}
}*/
