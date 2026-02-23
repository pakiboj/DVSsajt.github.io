----------------------------------------------------------------------------------
-- Testbench for acc_image_filter
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.axi_registers_pkg.all;

entity acc_image_filter_tb is
end acc_image_filter_tb;

architecture Behavioral of acc_image_filter_tb is

    ----------------------------------------------------------------------------
    -- Component declaration
    ----------------------------------------------------------------------------
    component acc_image_filter is
        Generic (
            C_MAX_IMG_WIDTH : integer := 512;
            C_MAX_RADIOUS   : integer := 4;
            C_RADIUS        : integer := 1;
            C_IMG_SIZE      : integer := 9;
            G_S_AXI_LITE_ADDR_WIDTH : integer := 9;
            G_S_AXI_LITE_DATA_WIDTH : integer := 32
        );
        port (
            clk : in std_logic;
            reset : in std_logic;
            
            -- AXI-Lite interface
            s_axi_lite_cfg_araddr  : in  std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH - 1 downto 0);
            s_axi_lite_cfg_arprot  : in  std_logic_vector(2 downto 0);
            s_axi_lite_cfg_arready : out std_logic;
            s_axi_lite_cfg_arvalid : in  std_logic;
            s_axi_lite_cfg_rdata   : out std_logic_vector(G_S_AXI_LITE_DATA_WIDTH - 1 downto 0);
            s_axi_lite_cfg_rready  : in  std_logic;
            s_axi_lite_cfg_rvalid  : out std_logic;
            s_axi_lite_cfg_rresp   : out std_logic_vector(1 downto 0);
            s_axi_lite_cfg_awaddr  : in  std_logic_vector(G_S_AXI_LITE_ADDR_WIDTH - 1 downto 0);
            s_axi_lite_cfg_awprot  : in  std_logic_vector(2 downto 0);
            s_axi_lite_cfg_awready : out std_logic;
            s_axi_lite_cfg_awvalid : in  std_logic;
            s_axi_lite_cfg_wdata   : in  std_logic_vector(G_S_AXI_LITE_DATA_WIDTH - 1 downto 0);
            s_axi_lite_cfg_wstrb   : in  std_logic_vector((G_S_AXI_LITE_DATA_WIDTH/8) - 1 downto 0);
            s_axi_lite_cfg_wready  : out std_logic;
            s_axi_lite_cfg_wvalid  : in  std_logic;
            s_axi_lite_cfg_bresp   : out std_logic_vector(1 downto 0);
            s_axi_lite_cfg_bvalid  : out std_logic;
            s_axi_lite_cfg_bready  : in  std_logic;
            
            -- AXI-Stream interface
            s_axis_in_tdata   : in  std_logic_vector(7 downto 0);
            s_axis_in_tlast   : in  std_logic;
            s_axis_in_tready  : out std_logic;
            s_axis_in_tvalid  : in  std_logic;
            m_axis_out_tdata  : out std_logic_vector(15 downto 0);
            m_axis_out_tlast  : out std_logic;
            m_axis_out_tready : in  std_logic;
            m_axis_out_tvalid : out std_logic
        );
    end component;

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------
    constant CLK_PERIOD : time := 10 ns;
    constant IMG_W      : integer := 128;
    constant IMG_H      : integer := 128;
    
    -- Register addresses (byte addresses, word-aligned)
    constant ADDR_REG_CTRL        : std_logic_vector(8 downto 0) := "000000000"; -- 0x000
    constant ADDR_REG_RADIUS      : std_logic_vector(8 downto 0) := "000000100"; -- 0x004
    constant ADDR_REG_COEFF_SCALE : std_logic_vector(8 downto 0) := "000001000"; -- 0x008
    constant ADDR_REG_IMG_W       : std_logic_vector(8 downto 0) := "000001100"; -- 0x00C
    constant ADDR_REG_IMG_H       : std_logic_vector(8 downto 0) := "000010000"; -- 0x010
    constant ADDR_REG_COEFF_START : std_logic_vector(8 downto 0) := "001000000"; -- 0x040 (coeff[0])
    

    ----------------------------------------------------------------------------
    -- Signals
    ----------------------------------------------------------------------------
    signal clk   : std_logic := '0';
    signal reset : std_logic := '1';
    
    -- AXI-Lite (9-bit address)
    signal s_axi_lite_cfg_araddr  : std_logic_vector(8 downto 0) := (others => '0');
    signal s_axi_lite_cfg_arprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_lite_cfg_arready : std_logic;
    signal s_axi_lite_cfg_arvalid : std_logic := '0';
    signal s_axi_lite_cfg_rdata   : std_logic_vector(31 downto 0);
    signal s_axi_lite_cfg_rready  : std_logic := '0';
    signal s_axi_lite_cfg_rvalid  : std_logic;
    signal s_axi_lite_cfg_rresp   : std_logic_vector(1 downto 0);
    signal s_axi_lite_cfg_awaddr  : std_logic_vector(8 downto 0) := (others => '0');
    signal s_axi_lite_cfg_awprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_lite_cfg_awready : std_logic;
    signal s_axi_lite_cfg_awvalid : std_logic := '0';
    signal s_axi_lite_cfg_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_lite_cfg_wstrb   : std_logic_vector(3 downto 0) := (others => '0');
    signal s_axi_lite_cfg_wready  : std_logic;
    signal s_axi_lite_cfg_wvalid  : std_logic := '0';
    signal s_axi_lite_cfg_bresp   : std_logic_vector(1 downto 0);
    signal s_axi_lite_cfg_bvalid  : std_logic;
    signal s_axi_lite_cfg_bready  : std_logic := '0';
    
    -- AXI-Stream
    signal s_axis_in_tdata   : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_in_tlast   : std_logic := '0';
    signal s_axis_in_tready  : std_logic;
    signal s_axis_in_tvalid  : std_logic := '0';
    signal m_axis_out_tdata  : std_logic_vector(15 downto 0);
    signal m_axis_out_tlast  : std_logic;
    signal m_axis_out_tready : std_logic := '1';
    signal m_axis_out_tvalid : std_logic;
    
    signal test_done : boolean := false;

begin

    ----------------------------------------------------------------------------
    -- DUT instantiation
    ----------------------------------------------------------------------------
    DUT : acc_image_filter
        generic map (
            C_MAX_IMG_WIDTH => 512,
            C_MAX_RADIOUS   => 4,
            C_RADIUS        => 1,
            C_IMG_SIZE      => 9,
            G_S_AXI_LITE_ADDR_WIDTH => 9,
            G_S_AXI_LITE_DATA_WIDTH => 32
        )
        port map (
            clk   => clk,
            reset => reset,
            
            s_axi_lite_cfg_araddr  => s_axi_lite_cfg_araddr,
            s_axi_lite_cfg_arprot  => s_axi_lite_cfg_arprot,
            s_axi_lite_cfg_arready => s_axi_lite_cfg_arready,
            s_axi_lite_cfg_arvalid => s_axi_lite_cfg_arvalid,
            s_axi_lite_cfg_rdata   => s_axi_lite_cfg_rdata,
            s_axi_lite_cfg_rready  => s_axi_lite_cfg_rready,
            s_axi_lite_cfg_rvalid  => s_axi_lite_cfg_rvalid,
            s_axi_lite_cfg_rresp   => s_axi_lite_cfg_rresp,
            s_axi_lite_cfg_awaddr  => s_axi_lite_cfg_awaddr,
            s_axi_lite_cfg_awprot  => s_axi_lite_cfg_awprot,
            s_axi_lite_cfg_awready => s_axi_lite_cfg_awready,
            s_axi_lite_cfg_awvalid => s_axi_lite_cfg_awvalid,
            s_axi_lite_cfg_wdata   => s_axi_lite_cfg_wdata,
            s_axi_lite_cfg_wstrb   => s_axi_lite_cfg_wstrb,
            s_axi_lite_cfg_wready  => s_axi_lite_cfg_wready,
            s_axi_lite_cfg_wvalid  => s_axi_lite_cfg_wvalid,
            s_axi_lite_cfg_bresp   => s_axi_lite_cfg_bresp,
            s_axi_lite_cfg_bvalid  => s_axi_lite_cfg_bvalid,
            s_axi_lite_cfg_bready  => s_axi_lite_cfg_bready,
            
            s_axis_in_tdata   => s_axis_in_tdata,
            s_axis_in_tlast   => s_axis_in_tlast,
            s_axis_in_tready  => s_axis_in_tready,
            s_axis_in_tvalid  => s_axis_in_tvalid,
            m_axis_out_tdata  => m_axis_out_tdata,
            m_axis_out_tlast  => m_axis_out_tlast,
            m_axis_out_tready => m_axis_out_tready,
            m_axis_out_tvalid => m_axis_out_tvalid
        );

    ----------------------------------------------------------------------------
    -- Clock generation
    ----------------------------------------------------------------------------
    clk_gen : process
    begin
        while not test_done loop
            clk <= '0'; wait for CLK_PERIOD / 2;
            clk <= '1'; wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus process
    ----------------------------------------------------------------------------
    stim_proc : process
        variable pixel_val : unsigned(7 downto 0);
        
        procedure do_reset is
        begin
            reset <= '1';
            wait for 10 * CLK_PERIOD;
            reset <= '0';
            wait for 5 * CLK_PERIOD;
        end procedure;
        
        procedure axi_write(addr : std_logic_vector(8 downto 0); 
                           data : std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            s_axi_lite_cfg_awaddr <= addr;
            s_axi_lite_cfg_awvalid <= '1';
            s_axi_lite_cfg_wdata <= data;
            s_axi_lite_cfg_wvalid <= '1';
            s_axi_lite_cfg_wstrb <= "1111";
            s_axi_lite_cfg_bready <= '1';
            
            wait until rising_edge(clk) and s_axi_lite_cfg_awready = '1';
            s_axi_lite_cfg_awvalid <= '0';
            
            wait until rising_edge(clk) and s_axi_lite_cfg_wready = '1';
            s_axi_lite_cfg_wvalid <= '0';
            
            wait until rising_edge(clk) and s_axi_lite_cfg_bvalid = '1';
            s_axi_lite_cfg_bready <= '0';
            
            wait for 2 * CLK_PERIOD;
        end procedure;
        
        procedure configure_test1 is
        begin
            report "================================================";
            report "Configuring Test 1: Box 3x3 filter, bord=11, bypass=0, mode=0";
            report "================================================";
            
            -- REG_CTRL: border_value[11:4]=0xFF, bord[3:2]=11, bypass[1]=0, mode[0]=0
            axi_write(ADDR_REG_CTRL, x"00000FF0");  -- 0xFF << 4 | 0xC
            
            -- REG_RADIUS: radius[2:0]=001
            axi_write(ADDR_REG_RADIUS, x"00000001");
            
            -- REG_COEFF_SCALE: scale = 1.0/81.0 ≈ 0.0123 in Q16 format ≈ 807
            axi_write(ADDR_REG_COEFF_SCALE, x"00000327");
            
            -- REG_IMG_W: 128
            axi_write(ADDR_REG_IMG_W, x"00000080");
            
            -- REG_IMG_H: 128
            axi_write(ADDR_REG_IMG_H, x"00000080");
            
            -- Configure coefficients: center 3x3 = 3, rest = 0
            -- Coefficients 30-32, 39-41, 48-50 should be 3
            for i in 0 to 80 loop
                if (i >= 30 and i <= 32) or (i >= 39 and i <= 41) or (i >= 48 and i <= 50) then
                    axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(i*4, 9)), 
                             x"00000003");
                else
                    axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(i*4, 9)), 
                             x"00000000");
                end if;
            end loop;
        end procedure;
        
        procedure configure_test2 is
        begin
            report "================================================";
            report "Configuring Test 2: Bypass mode";
            report "================================================";
            
            -- REG_CTRL: border_value[11:4]=0xFF, bord[3:2]=11, bypass[1]=1, mode[0]=0
            axi_write(ADDR_REG_CTRL, x"00000FF2");  -- Set bypass bit
        end procedure;
        
        procedure configure_test3 is
        begin
            report "================================================";
            report "Configuring Test 3: Uniform 9x9, mode=1 (16-bit output)";
            report "================================================";
            
            -- REG_CTRL: border_value[11:4]=0xFF, bord[3:2]=11, bypass[1]=0, mode[0]=1
            axi_write(ADDR_REG_CTRL, x"00000FF1");  -- Set mode bit
            
            -- All coefficients = 1
            for i in 0 to 80 loop
                axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(i*4, 9)), 
                         x"00000001");
            end loop;
        end procedure;
        
        procedure configure_test4 is
        begin
            report "================================================";
            report "Configuring Test 4: Gaussian 7x7 blur, bord=00";
            report "================================================";
            
            -- REG_CTRL: border_value[11:4]=0x00, bord[3:2]=00, bypass[1]=0, mode[0]=0
            axi_write(ADDR_REG_CTRL, x"00000000");
            
            -- Gaussian kernel (7x7 centered in 9x9, scale 1/273)
            -- Row 0-1: all zeros
            for i in 0 to 17 loop
                axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(i*4, 9)), 
                         x"00000000");
            end loop;
            
            -- Row 2: 0,0,1,4,7,4,1,0,0
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(18*4, 9)), x"00000000");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(19*4, 9)), x"00000000");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(20*4, 9)), x"00000001");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(21*4, 9)), x"00000004");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(22*4, 9)), x"00000007");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(23*4, 9)), x"00000004");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(24*4, 9)), x"00000001");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(25*4, 9)), x"00000000");
            axi_write(std_logic_vector(unsigned(ADDR_REG_COEFF_START) + to_unsigned(26*4, 9)), x"00000000");
            
            -- Continue for rows 3-6...
            -- (Add similar writes for the rest of the Gaussian kernel)
        end procedure;
        
        procedure configure_test5 is
        begin
            report "================================================";
            report "Configuring Test 5: Laplacian edge detection";
            report "================================================";
            
            -- REG_CTRL: border_value[11:4]=0x00, bord[3:2]=00, bypass[1]=0, mode[0]=0
            axi_write(ADDR_REG_CTRL, x"00000000");
            
            -- Laplacian kernel (9x9)
            -- Center value = 16, nearby = 5, further = -3, etc.
            -- (You'll need to write all 81 coefficients as signed values)
        end procedure;
        
        procedure send_image(test_name : string) is
        begin
            report "================================================";
            report "START: " & test_name;
            report "================================================";
            
            pixel_val := to_unsigned(1, 8);
            
            for r in 0 to IMG_H - 1 loop
                for c in 0 to IMG_W - 1 loop
                    s_axis_in_tdata <= std_logic_vector(pixel_val);
                    s_axis_in_tvalid <= '1';
                    
                    if (r = IMG_H - 1) and (c = IMG_W - 1) then
                        s_axis_in_tlast <= '1';
                    else
                        s_axis_in_tlast <= '0';
                    end if;
                    
                    wait until rising_edge(clk);
                    while s_axis_in_tready = '0' loop
                        wait until rising_edge(clk);
                    end loop;
                    
                    -- Increment with overflow: 1→255→1
                    if pixel_val = 255 then
                        pixel_val := to_unsigned(1, 8);
                    else
                        pixel_val := pixel_val + 1;
                    end if;
                end loop;
            end loop;
            
            s_axis_in_tvalid <= '0';
            s_axis_in_tlast <= '0';
            wait for 500 * CLK_PERIOD;
            report "END: " & test_name;
        end procedure;
        
    begin
        s_axis_in_tvalid <= '0';
        s_axis_in_tlast <= '0';
        m_axis_out_tready <= '1';
        do_reset;
        
        ----------------------------------------------------------------
        -- Test 1: Box filter
        ----------------------------------------------------------------
        configure_test1;
        send_image("Test 1: Box filter 3x3");
        
        ----------------------------------------------------------------
        -- Test 2: Bypass mode
        ----------------------------------------------------------------
        configure_test2;
        send_image("Test 2: Bypass mode");
        
        ----------------------------------------------------------------
        -- Test 3: Uniform filter
        ----------------------------------------------------------------
        configure_test3;
        send_image("Test 3: Uniform 9x9");
        
        ----------------------------------------------------------------
        -- Test 4: Gaussian blur
        ----------------------------------------------------------------
        configure_test4;
        send_image("Test 4: Gaussian blur");
        
        ----------------------------------------------------------------
        -- Test 5: Laplacian edge detection
        ----------------------------------------------------------------
        configure_test5;
        send_image("Test 5: Laplacian edge");
        
        ----------------------------------------------------------------
        report "================================================";
        report "ALL TESTS COMPLETED";
        report "================================================";
        test_done <= true;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Monitor process
    ----------------------------------------------------------------------------
    monitor_proc : process
        variable pix_cnt : integer := 0;
    begin
        loop
            wait until rising_edge(clk);
            exit when test_done;
            
            if m_axis_out_tvalid = '1' and m_axis_out_tready = '1' then
                pix_cnt := pix_cnt + 1;
                
                if (pix_cnt mod 1000 = 0) or (m_axis_out_tlast = '1') then
                    report "Output pixel #" & integer'image(pix_cnt) & 
                           " = " & integer'image(to_integer(unsigned(m_axis_out_tdata))) &
                           " last=" & std_logic'image(m_axis_out_tlast);
                end if;
                
                if m_axis_out_tlast = '1' then
                    report ">>> IMAGE COMPLETE - Total pixels: " & integer'image(pix_cnt);
                    pix_cnt := 0;
                end if;
            end if;
        end loop;
        wait;
    end process;

end Behavioral;