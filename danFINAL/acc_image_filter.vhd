
-- Company: 
-- Engineer: 
-- 
-- Create Date: 21.02.2026 23:10:52
-- Design Name: 
-- Module Name: acc_image_filter - Behavioral
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
use IEEE.numeric_std.all;
use work.axi_registers_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity acc_image_filter is
  Generic (
        C_MAX_IMG_WIDTH : integer := 512;
        C_MAX_RADIOUS : integer := 4;
        C_RADIUS : integer := 1;
        C_IMG_SIZE : integer := 128;
        G_S_AXI_LITE_ADDR_WIDTH : integer := 9;
        G_S_AXI_LITE_DATA_WIDTH : integer :=32
    );
  port ( 
    clk : in std_logic;
    -- Synchronous active high reset --
    reset : in std_logic;
  
    -- AXI LITE Interface for accelerators configuration registers--
    
    -- Read Address Channel --
    s_axi_lite_cfg_araddr : in std_logic_vector (G_S_AXI_LITE_ADDR_WIDTH - 1 downto 0);
    s_axi_lite_cfg_arprot : in std_logic_vector (2 downto 0);
    s_axi_lite_cfg_arready : out std_logic;
    s_axi_lite_cfg_arvalid : in std_logic;
    
    -- Read Channel --
    s_axi_lite_cfg_rdata : out std_logic_vector (G_S_AXI_LITE_DATA_WIDTH - 1 downto 0);
    s_axi_lite_cfg_rready : in std_logic;
    s_axi_lite_cfg_rvalid : out std_logic;
    s_axi_lite_cfg_rresp : out std_logic_vector (1 downto 0);
    
    -- Write Address Channel --
    s_axi_lite_cfg_awaddr : in std_logic_vector (G_S_AXI_LITE_ADDR_WIDTH - 1 downto 0);
    s_axi_lite_cfg_awprot : in std_logic_vector (2 downto 0);
    s_axi_lite_cfg_awready : out std_logic;
    s_axi_lite_cfg_awvalid : in std_logic;
    
    -- Write Channel --
    s_axi_lite_cfg_wdata : in std_logic_vector (G_S_AXI_LITE_DATA_WIDTH - 1 downto 0);
    s_axi_lite_cfg_wstrb : in std_logic_vector ((G_S_AXI_LITE_DATA_WIDTH/8) - 1 downto 0);
    s_axi_lite_cfg_wready : out std_logic;
    s_axi_lite_cfg_wvalid : in std_logic;
    
    -- Write Response Channel --
    s_axi_lite_cfg_bresp : out std_logic_vector (1 downto 0);
    s_axi_lite_cfg_bvalid : out std_logic;
    s_axi_lite_cfg_bready : in std_logic;
    
    -- AXI Stream interface --
    
    -- Input AXI Stream of pixels --
    s_axis_in_tdata : in std_logic_vector (7 downto 0);
    s_axis_in_tlast : in std_logic;
    s_axis_in_tready : out std_logic;
    s_axis_in_tvalid : in std_logic;
     
    -- Output AXI Strean of pixels --
    m_axis_out_tdata : out std_logic_vector (15 downto 0);
    m_axis_out_tlast : out std_logic;
    m_axis_out_tready : in std_logic;
    m_axis_out_tvalid : out std_logic
  );
end acc_image_filter;

architecture Behavioral of acc_image_filter is
    
    signal axis_out_tvalid : std_logic;
    signal axis_out_tlast : std_logic;
    
    signal bypass_pixel : std_logic_vector (7 downto 0);
    signal bypass_pixel_valid : std_logic;
    signal bypass_pixel_last : std_logic;

    -- Processing Parameters --
    signal border_value : std_logic_vector(7 downto 0);
    signal bord : std_logic_vector(1 downto 0);
    signal bypass : std_logic;
    signal mode : std_logic;
    signal radius : std_logic_vector(2 downto 0);
    signal img_width : std_logic_vector(15 downto 0);
    signal img_height : std_logic_vector (15 downto 0);
    signal coeff_scale : std_logic_vector (15 downto 0);
    
    -- Config regs enable --
    signal cfg_en : std_logic;
    
    signal pipeline_ready : std_logic;
    signal ready : std_logic;
    
    signal register_out_ready : std_logic;
    
    --Pixel registers 
    signal coeff : t_coeff_array;
    
    --Pixel output
    signal w_k : t_w_array;
    signal w_k_valid : std_logic;
    signal w_k_last : std_logic;
    
    ---------------------------------------
    signal pixel_new_8 : std_logic_vector(7 downto 0);
    signal pixel_new_16 : std_logic_vector(15 downto 0);
    
    signal mac_index   : integer range 0 to 81 := 0;
    signal mac_acc     : signed(31 downto 0) := (others => '0');
    signal mac_running : std_logic := '0';
    signal mac_done    : std_logic := '0';
    signal mac_done_d : std_logic := '0';
    signal w_k_last_delay : std_logic_vector(81 downto 0) := (others => '0');
    
    signal mac_sum_32 : signed(31 downto 0); 
    
begin

    AXI_REGISTERS: entity work.axi_registers
        generic map (
            G_S_AXI_LITE_ADDR_WIDTH => G_S_AXI_LITE_ADDR_WIDTH,
            G_S_AXI_LITE_DATA_WIDTH => G_S_AXI_LITE_DATA_WIDTH
        )
        port map (
            clk => clk,
            reset => reset,
            cfg_en => cfg_en,
            
            s_axi_lite_awaddr  => s_axi_lite_cfg_awaddr,
            s_axi_lite_awprot  => s_axi_lite_cfg_awprot,
            s_axi_lite_awvalid => s_axi_lite_cfg_awvalid,
            s_axi_lite_awready => s_axi_lite_cfg_awready,
            
            s_axi_lite_wdata  => s_axi_lite_cfg_wdata,
            s_axi_lite_wstrb  => s_axi_lite_cfg_wstrb,
            s_axi_lite_wvalid => s_axi_lite_cfg_wvalid,
            s_axi_lite_wready => s_axi_lite_cfg_wready,
            
            s_axi_lite_bresp  => s_axi_lite_cfg_bresp,
            s_axi_lite_bvalid => s_axi_lite_cfg_bvalid,
            s_axi_lite_bready => s_axi_lite_cfg_bready,
            
            s_axi_lite_araddr  => s_axi_lite_cfg_araddr,
            s_axi_lite_arprot  => s_axi_lite_cfg_arprot,
            s_axi_lite_arvalid => s_axi_lite_cfg_arvalid,
            s_axi_lite_arready => s_axi_lite_cfg_arready,
            
            s_axi_lite_rdata  => s_axi_lite_cfg_rdata,
            s_axi_lite_rvalid => s_axi_lite_cfg_rvalid,
            s_axi_lite_rready => s_axi_lite_cfg_rready,
            s_axi_lite_rresp  => s_axi_lite_cfg_rresp,
            
            border_value => border_value,
            bord => bord,
            bypass => bypass,
            mode => mode,
            radius => radius,
            img_width => img_width,
            img_height => img_height,
            coeff_scale => coeff_scale,
            coeff => coeff
        );
        
         
        
        AXI_IMAGE_BLOCK : entity work.axi_image_block
        generic map (
            C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
            C_MAX_RADIOUS   => C_MAX_RADIOUS,
            C_RADIUS        => C_RADIUS,
            C_IMG_SIZE      => C_IMG_SIZE
        )
        port map (
            clk                => clk,
            reset              => reset,
            border_value       => border_value,
            bord               => bord,
            radius             => radius,
            img_width          => img_width,
            img_height         => img_height,
            ready              => ready,
            s_axis_tdata       => s_axis_in_tdata,
            s_axis_tlast       => s_axis_in_tlast,
            s_axis_tvalid      => s_axis_in_tvalid,
            s_axis_tready      => s_axis_in_tready,
            bypass_pixel       => bypass_pixel,
            bypass_pixel_valid => bypass_pixel_valid,
            bypass_pixel_last  => bypass_pixel_last,
            w_k                => w_k,
            w_k_valid          => w_k_valid,
            w_k_last           => w_k_last
        );
        
    process(clk)is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                ready <= '0';
            else
                ready <= pipeline_ready;
            end if;
        end if;
    end process;
    
    pipeline_ready <= (not axis_out_tvalid) or m_axis_out_tready;

    process(clk) is
    begin
        if (rising_edge(clk)) then
            if reset = '1' then
                cfg_en <= '1';
            else
                if (cfg_en = '1') then
                    if (s_axis_in_tvalid = '1' ) then
                        cfg_en <= '0';
                    end if;
                else
                    if (axis_out_tlast = '1' and axis_out_tvalid = '1' and m_axis_out_tready = '1') then
                        cfg_en <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
--    process (w_k)is
--    begin
--        if(reset = '1')then
--            pixel_new_8 <=(others => '0');
--        else
--            for i in 0 to 80 loop
--                pixel_new_8 <= std_logic_vector(signed(w_k(i)* signed(coeff(i))+ signed(pixel_new_8));
--            end loop;
--        end if;
--    end process;
-- Add these signals


    process(clk) is
        variable mult_result : signed(23 downto 0);
        variable acc_shifted  : signed(31 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
                mac_index    <= 0;
                mac_acc      <= (others => '0');
                mac_running  <= '0';
                mac_done     <= '0';
                mac_done_d   <= '0';
                mac_sum_32   <= (others => '0');
                pixel_new_8  <= (others => '0');
                pixel_new_16 <= (others => '0');
            else
                mac_done   <= '0';
                mac_done_d <= mac_done;  -- delayed by 1 cycle to match mac_sum_32
                
                if w_k_valid = '1' and mac_running = '0' then
                    mac_acc     <= (others => '0');
                    mac_index   <= 0;
                    mac_running <= '1';
                elsif mac_running = '1' then
                    mult_result := signed(resize(unsigned(w_k(mac_index)), 8)) 
                                   * signed(coeff(mac_index));
                    mac_acc   <= mac_acc + resize(mult_result, 32);
                    mac_index <= mac_index + 1;
                    
                    if mac_index = 80 then
                        mac_running <= '0';
                        mac_done    <= '1';
                        
                        -- mac_sum_32 registered here, available next cycle
                        mac_sum_32 <= mac_acc + resize(mult_result, 32);
                        
                        -- pixel_new_8 computed directly, no lag needed
                        acc_shifted := shift_right(mac_acc + resize(mult_result, 32), 7);
                        if acc_shifted < 0 then
                            pixel_new_8 <= (others => '0');
                        elsif acc_shifted > 255 then
                            pixel_new_8 <= (others => '1');
                        else
                            pixel_new_8 <= std_logic_vector(acc_shifted(7 downto 0));
                        end if;
                    end if;
                end if;
                
                -- pixel_new_16 reads mac_sum_32, so assign it one cycle later
                if mac_done = '1' then
                    pixel_new_16 <= std_logic_vector(mac_sum_32(22 downto 7));
                end if;
                
            end if;
        end if;
    end process;
    
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                m_axis_out_tdata <= (others => '0');
                axis_out_tvalid  <= '0';
                axis_out_tlast   <= '0';
            else
                if (pipeline_ready = '1') then
                    if (bypass = '1') then
                        m_axis_out_tdata(15 downto 8) <= (others => '0');
                        m_axis_out_tdata(7 downto 0)  <= bypass_pixel;
                        axis_out_tvalid               <= bypass_pixel_valid;
                        axis_out_tlast                <= bypass_pixel_last;
                    else
                        if (mode = '0') then
                            m_axis_out_tdata(15 downto 8) <= (others => '0');
                            m_axis_out_tdata(7 downto 0)  <= pixel_new_8;
                        else
                            m_axis_out_tdata <= pixel_new_16;
                        end if;
                        axis_out_tvalid <= mac_done_d;
                        axis_out_tlast  <= w_k_last_delay(81);
                    end if;
                end if;
            end if;
        end if;
    end process;
     
     m_axis_out_tvalid <= axis_out_tvalid; 
     m_axis_out_tlast <= axis_out_tlast;
    
    process(clk) is
    begin
        if rising_edge(clk) then
            if reset = '1' then
                w_k_last_delay <= (others => '0');
            else
                w_k_last_delay <= w_k_last_delay(80 downto 0) & w_k_last;
            end if;
        end if;
    end process;

end Behavioral;
