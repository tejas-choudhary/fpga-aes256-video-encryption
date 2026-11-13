create_clock -name sys_clk -period 37.037 -waveform {0 18.518} [get_ports {sys_clk}]
create_clock -name cam_pclk -period 41.667 -waveform {0 20.833} [get_ports {cam_pclk}]
set_clock_groups -asynchronous -group [get_clocks {sys_clk}] -group [get_clocks {cam_pclk}]