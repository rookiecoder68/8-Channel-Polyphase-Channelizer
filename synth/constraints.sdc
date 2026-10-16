# 100 MHz clock -> 10.0 ns period
create_clock -name clk -period 10.0 [get_ports clk]

# Assume 5% (0.5ns) margin for input arrival and output capture times
# Explicit port lists avoid unsupported collection commands in OpenSTA.
set_input_delay  0.5 -clock clk \
    [get_ports {rst_n s_valid s_data}]
set_output_delay 0.5 -clock clk \
    [get_ports {m_valid m_data_re m_data_im}]

# Set typical load characteristics
set_load 0.005 \
    [get_ports {m_valid m_data_re m_data_im}]

# Reset is asynchronous and is not part of the synchronous datapath timing.
set_false_path -from [get_ports rst_n]