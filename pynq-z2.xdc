
#-- pynq-z2 board

#-- System clock (125 MHz)
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports {clk}]

#-- LEDs: led0 clk25 heartbeat, led1 rx blip, led2 tx blip, led3 sticky bad-FCS
set_property -dict { PACKAGE_PIN R14   IOSTANDARD LVCMOS33 } [get_ports {leds[0]}]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports {leds[1]}]
set_property -dict { PACKAGE_PIN N16   IOSTANDARD LVCMOS33 } [get_ports {leds[2]}]
set_property -dict { PACKAGE_PIN M14   IOSTANDARD LVCMOS33 } [get_ports {leds[3]}]

#-- Pins from the official PYNQ-Z2 base.xdc (H16 clock, R14/P14/N16/M14 LEDs)
