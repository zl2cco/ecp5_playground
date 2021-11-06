use picorv32_pac::LED;

pub struct Led {
    registers: LED,
}

#[allow(dead_code)]
impl Led {
    pub fn new(registers: LED) -> Self {
        registers.csr.reset();

        Self { registers }
    }

    pub fn on(&mut self) {
        self.registers.csr.write(|w| {w.led0().set_bit()});
    }

    pub fn off(&mut self) {
        self.registers.csr.write(|w| {w.led0().clear_bit()});
    }

    pub fn set(&mut self, val: u32) {
        self.registers.csr.write_with_zero(|w| unsafe {w.bits(val)});
    }


}