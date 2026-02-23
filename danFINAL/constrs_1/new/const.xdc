create_clock -period 10.000 -name clk [get_ports clk]

set_multicycle_path -setup 3 -from [get_cells {cfg_en_reg}] \
    -to [get_cells {AXI_REGISTERS/reg_img_w_locked_reg*}]
set_multicycle_path -hold  2 -from [get_cells {cfg_en_reg}] \
    -to [get_cells {AXI_REGISTERS/reg_img_w_locked_reg*}]
    
set_multicycle_path -setup 3 -from [get_cells {cfg_en_reg}] \
    -to [get_cells {AXI_REGISTERS/reg_*_locked_reg*}]
set_multicycle_path -hold  2 -from [get_cells {cfg_en_reg}] \
    -to [get_cells {AXI_REGISTERS/reg_*_locked_reg*}]