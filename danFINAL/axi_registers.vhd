---------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 09/01/2025 12:02:35 AM
-- Design Name: 
-- Module Name: axi_lite_cfg_registers - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;
use work.axi_registers_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity axi_registers is
  generic(
    G_S_AXI_LITE_ADDR_WIDTH : integer := 9;
    G_S_AXI_LITE_DATA_WIDTH : integer := 32
  );
  port ( 
    clk : in std_logic;
    reset: in std_logic;
    
    -- Enable signal used to prevent changing the configuration while processing --
    cfg_en : in std_logic;
    
    -- AXI Lite interface --
    s_axi_lite_awaddr  : in std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-1 downto 0);
    s_axi_lite_awprot  : in std_logic_vector(2 downto 0);
    s_axi_lite_awvalid : in std_logic;
    s_axi_lite_awready : out std_logic;
    
    s_axi_lite_wdata  : in std_logic_vector(G_S_AXI_LITE_DATA_WIDTH-1 downto 0);
    s_axi_lite_wstrb  : in std_logic_vector((G_S_AXI_LITE_DATA_WIDTH/8)-1 downto 0);
    s_axi_lite_wvalid : in std_logic;
    s_axi_lite_wready : out std_logic;
    
    s_axi_lite_bresp  : out std_logic_vector(1 downto 0);
    s_axi_lite_bvalid : out std_logic;
    s_axi_lite_bready : in std_logic;
    
    s_axi_lite_araddr  : in std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-1 downto 0);
    s_axi_lite_arprot  : in std_logic_vector(2 downto 0);
    s_axi_lite_arvalid : in std_logic;
    s_axi_lite_arready : out std_logic;
    
    s_axi_lite_rdata  : out std_logic_vector(G_S_AXI_LITE_DATA_WIDTH-1 downto 0);
    s_axi_lite_rvalid : out std_logic;
    s_axi_lite_rready : in std_logic;
    s_axi_lite_rresp  : out std_logic_vector(1 downto 0);
    
    -- Output processing parameters --
    border_value : out std_logic_vector(7 downto 0);
    bord : out std_logic_vector(1 downto 0);
    bypass : out std_logic;
    mode : out std_logic;
    radius : out std_logic_vector(2 downto 0);
    img_width : out std_logic_vector(15 downto 0);
    img_height : out std_logic_vector (15 downto 0);
    coeff_scale : out std_logic_vector (15 downto 0);
        
    -- Array of 81 coefficient registers --
    coeff : out t_coeff_array
    
  );
end axi_registers;

architecture Behavioral of axi_registers is
    
    -- Address alignment --
    constant ADDR_LSB : natural := (G_S_AXI_LITE_DATA_WIDTH/32) + 1; --2
    
    constant REG_CTRL_ADDR        : std_logic_vector(6 downto 0) := "0000000"; -- 0x00
    constant REG_RAD_ADDR         : std_logic_vector(6 downto 0) := "0000001"; -- 0x01
    constant REG_COEFF_SCALE_ADDR : std_logic_vector(6 downto 0) := "0000010"; -- 0x02
    constant REG_IMG_W_ADDR       : std_logic_vector(6 downto 0) := "0000011"; -- 0x03
    constant REG_IMG_H_ADDR       : std_logic_vector(6 downto 0) := "0000100"; -- 0x04
    --
    ---
    -- Registers reg_coeff_WX are in pkg file i included in the beggining 
    --
    --
    
    -- Accelerators Configuration registers --
    signal reg_ctrl : std_logic_vector (15 downto 0);
    signal reg_radius : std_logic_vector (15 downto 0);
    signal reg_coeff_scale : std_logic_vector (15 downto 0);
    signal reg_img_w : std_logic_vector (15 downto 0);
    signal reg_img_h : std_logic_vector (15 downto 0);
    signal reg_coeff : t_coeff_array;
    
    -- Locked configuration registers during processing --
    signal reg_ctrl_locked : std_logic_vector (15 downto 0);
    signal reg_radius_locked : std_logic_vector (15 downto 0);
    signal reg_coeff_scale_locked : std_logic_vector (15 downto 0);
    signal reg_img_w_locked : std_logic_vector (15 downto 0);
    signal reg_img_h_locked : std_logic_vector (15 downto 0);
    signal reg_coeff_locked : t_coeff_array;
    
    -- AXI4-Lite internal signals --
    signal axi_awready : std_logic;
    signal axi_wready  : std_logic;
    signal axi_awaddr  : std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-1 downto 0);
    
    signal axi_bvalid  : std_logic;
    
    signal axi_arready : std_logic;
    signal axi_rvalid  : std_logic;
    signal axi_araddr  : std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-1 downto 0);

    signal reg_waddr : std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-ADDR_LSB-1 downto 0);
    signal reg_raddr : std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH-ADDR_LSB-1 downto 0);
    
    signal axi_write_ready : std_logic;
    signal axi_read_ready : std_logic;
    
    -- AXI4-Lite state machines --
    type fsm_read_state_type is  (ReadAddress,  ReadData);
    type fsm_write_state_type is (WriteDisabled, WriteAddress, WriteData, WriteStalled);
    
    signal fsm_axi_read_state : fsm_read_state_type;
    signal fsm_axi_write_state : fsm_write_state_type;
    
   signal cfg_en_d  : std_logic;
    signal cfg_en_d2 : std_logic;
  
begin

    -- AXI4-Lite write registers  -----------------------------------------------------------------------------------
    process (clk) is
    begin
        if (rising_edge(clk)) then    
            if (reset = '1') then
                reg_ctrl        <= (others => '0');
                reg_radius      <= (others => '0');
                reg_coeff_scale <= (others => '0');
                reg_img_w       <= (others => '0');
                reg_img_h       <= (others => '0');
                reg_coeff       <= (others => (others => '0'));
            else
                if (axi_write_ready = '1') then
                    -- Lower byte
                    if (s_axi_lite_wstrb(0) = '1') then
                        case (reg_waddr) is
                            when REG_CTRL_ADDR        => reg_ctrl(7 downto 0)        <= s_axi_lite_wdata(7 downto 0);
                            when REG_RAD_ADDR         => reg_radius(7 downto 0)      <= s_axi_lite_wdata(7 downto 0);
                            when REG_COEFF_SCALE_ADDR => reg_coeff_scale(7 downto 0) <= s_axi_lite_wdata(7 downto 0);
                            when REG_IMG_W_ADDR       => reg_img_w(7 downto 0)       <= s_axi_lite_wdata(7 downto 0);
                            when REG_IMG_H_ADDR       => reg_img_h(7 downto 0)       <= s_axi_lite_wdata(7 downto 0);
    
                            -- Reg_coeff_w bytes
                            when others =>
                                if (to_integer(unsigned(reg_waddr)) >= 16 and 
                                    to_integer(unsigned(reg_waddr)) <= 96) then
                                    reg_coeff(to_integer(unsigned(reg_waddr)) - 16)(7 downto 0)
                                        <= s_axi_lite_wdata(7 downto 0);
                                end if;
                        end case;
                    end if;
    
                    -- Upper byte
                    if (s_axi_lite_wstrb(1) = '1') then
                        case (reg_waddr) is
                            when REG_CTRL_ADDR        => reg_ctrl(15 downto 8)        <= s_axi_lite_wdata(15 downto 8);
                            when REG_RAD_ADDR         => reg_radius(15 downto 8)      <= s_axi_lite_wdata(15 downto 8);
                            when REG_COEFF_SCALE_ADDR => reg_coeff_scale(15 downto 8) <= s_axi_lite_wdata(15 downto 8);
                            when REG_IMG_W_ADDR       => reg_img_w(15 downto 8)       <= s_axi_lite_wdata(15 downto 8);
                            when REG_IMG_H_ADDR       => reg_img_h(15 downto 8)       <= s_axi_lite_wdata(15 downto 8);
    
                            -- Reg_coeff_w bytes
                            when others =>
                                if (to_integer(unsigned(reg_waddr)) >= 16 and 
                                    to_integer(unsigned(reg_waddr)) <= 96) then
                                    reg_coeff(to_integer(unsigned(reg_waddr)) - 16)(15 downto 8)
                                        <= s_axi_lite_wdata(15 downto 8);
                                end if;
                        end case;
                    end if;
                end if;
            end if;   
        end if;
    end process;
    
    -- AXI4-Lite read registers  -----------------------------------------------------------------------------------
    s_axi_lite_rdata(15 downto 0) <=
        reg_ctrl        when (reg_raddr = REG_CTRL_ADDR)        else
        reg_radius      when (reg_raddr = REG_RAD_ADDR)         else
        reg_coeff_scale when (reg_raddr = REG_COEFF_SCALE_ADDR) else
        reg_img_w       when (reg_raddr = REG_IMG_W_ADDR)       else
        reg_img_h       when (reg_raddr = REG_IMG_H_ADDR)       else
    
        
        reg_coeff(to_integer(unsigned(reg_raddr)) - 16)
            when (to_integer(unsigned(reg_raddr)) >= 16 and
                  to_integer(unsigned(reg_raddr)) <= 96) else
        (others => '0');
    
    -- Unused bits  -----------------------------------------------------------------------------------
    s_axi_lite_rdata(G_S_AXI_LITE_DATA_WIDTH-1 downto 16) <= (others => '0');

    -- Responses set to OKAY  -----------------------------------------------------------------------------------
    s_axi_lite_bresp <= "00";
    s_axi_lite_rresp <= "00";
    
     -- AXI4-Lite read state machine  -----------------------------------------------------------------------------------
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                axi_arready <= '0';
                axi_rvalid  <= '0';
                fsm_axi_read_state <= ReadAddress;
            else
                case (fsm_axi_read_state) is
                    when ReadAddress =>
                        axi_arready <= '1';
                        if (axi_arready = '1' and s_axi_lite_arvalid = '1') then
                            axi_araddr <= s_axi_lite_araddr;
                            axi_arready <= '0';
                            axi_rvalid <= '1';
                            fsm_axi_read_state <= ReadData;
                        end if;
                    when ReadData =>
                        if (s_axi_lite_rready = '1' and axi_rvalid = '1') then
                            axi_rvalid <= '0';
                            axi_arready <= '1';
                            fsm_axi_read_state <= ReadAddress;
                        end if;
                end case;
            end if;
        end if;
    end process;
    
    s_axi_lite_arready <= axi_arready;
    s_axi_lite_rvalid <= axi_rvalid;
    
    
    reg_raddr <= s_axi_lite_araddr(G_S_AXI_LITE_ADDR_WIDTH-1 downto ADDR_LSB) when (s_axi_lite_arvalid = '1') else
                        axi_araddr(G_S_AXI_LITE_ADDR_WIDTH-1 downto ADDR_LSB); 
                        
    -- AXI4-Lite write state machine  -----------------------------------------------------------------------------------
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                axi_awready <= '0';
                axi_wready  <= '0';
                axi_bvalid  <= '0';
                fsm_axi_write_state <= WriteAddress;
            else
                case (fsm_axi_write_state) is                                              
                    when WriteAddress =>
                        axi_awready <= '1';
                        axi_wready <= '1';
                    
                        if (axi_awready = '1' and s_axi_lite_awvalid = '1') then
                            axi_awaddr <= s_axi_lite_awaddr;
                            if (axi_wready = '1' and s_axi_lite_wvalid = '1') then
                                axi_bvalid <= '1';
                                if (s_axi_lite_bready = '0') then
                                    axi_awready <= '0';
                                    axi_wready <= '0';
                                    fsm_axi_write_state <= WriteStalled;
                                end if;
                            else
                                axi_awready <= '0';
                                fsm_axi_write_state <= WriteData;
                                if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                    axi_bvalid <= '0';
                                end if;
                            end if;
                        else
                            if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                axi_bvalid <= '0';
                            end if;
                        end if;
                        
                    when WriteData =>
                        if (axi_wready = '1' and s_axi_lite_wvalid = '1') then
                            axi_bvalid <= '1';
                            if (s_axi_lite_bready = '0') then
                                axi_awready <= '0';
                                axi_wready <= '0';
                                fsm_axi_write_state <= WriteStalled;
                            else
                                axi_awready <= '1';
                                axi_wready <= '1';
                                fsm_axi_write_state <= WriteAddress;
                            end if;
                        else
                            if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                                axi_bvalid <= '0';
                            end if;
                        end if;
                        
                    when WriteStalled =>
                        if (s_axi_lite_bready = '1' and axi_bvalid = '1') then
                            axi_bvalid <= '0';
                            axi_awready <= '1';
                            axi_wready <= '1';
                            fsm_axi_write_state <= WriteAddress;
                        end if;
                        
                    when others =>
                        axi_awready <= '0';
                        axi_wready <= '0';
                        axi_bvalid <= '0';
                        fsm_axi_write_state <= WriteAddress;
                end case;
            end if;
        end if;
     end process;    

    s_axi_lite_awready <= axi_awready;
    s_axi_lite_wready  <= axi_wready;
    s_axi_lite_bvalid <= axi_bvalid;
    
    axi_write_ready <= '1' when ((fsm_axi_write_state = WriteAddress and s_axi_lite_awvalid = '1' and s_axi_lite_wvalid = '1') or
                                 (fsm_axi_write_state = WriteData and axi_awready  = '1' and s_axi_lite_wvalid = '1')) else '0'; -- and axi_awready  = '1' 
    
    reg_waddr <= s_axi_lite_awaddr(G_S_AXI_LITE_ADDR_WIDTH-1 downto ADDR_LSB) when (s_axi_lite_awvalid = '1') else axi_awaddr(G_S_AXI_LITE_ADDR_WIDTH-1 downto ADDR_LSB);
    
    

    process(clk) is
    begin
        if rising_edge(clk) then
            cfg_en_d  <= cfg_en;
            cfg_en_d2 <= cfg_en_d;
        end if;
    end process;
    
        
    --Enable logic -----------------------------------------------------------------------------------
    process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                reg_ctrl_locked        <= (others => '0');
                reg_radius_locked      <= (others => '0');
                reg_coeff_scale_locked <= (others => '0');
                reg_img_w_locked       <= (others => '0');
                reg_img_h_locked       <= (others => '0');
            elsif cfg_en_d2 = '1' then
                reg_ctrl_locked        <= reg_ctrl;
                reg_radius_locked      <= reg_radius;
                reg_coeff_scale_locked <= reg_coeff_scale;
                reg_img_w_locked       <= reg_img_w;
                reg_img_h_locked       <= reg_img_h;
            end if;
        end if;
    end process;
    
    -- Coeff locked registers -- uses cfg_en_d
    process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                reg_coeff_locked <= (others => (others => '0'));
            elsif cfg_en_d = '1' then
                reg_coeff_locked <= reg_coeff;
            end if;
        end if;
    end process;
    
    -- Extract output fields from locked registers -- 
    border_value <=  reg_ctrl_locked(11 downto 4);
    bord <= reg_ctrl_locked(3 downto 2);
    bypass <= reg_ctrl_locked(1);
    mode <= reg_ctrl_locked(0);
    radius <= reg_radius_locked(2 downto 0);
    img_width <= reg_img_w_locked;
    img_height <= reg_img_h_locked;
    coeff_scale <= reg_coeff_scale_locked;
    coeff <= reg_coeff_locked;

end Behavioral;
