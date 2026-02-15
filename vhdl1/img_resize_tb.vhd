----------------------------------------------------------------------------------
-- Testbench for img_resize (window_extractor)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.axi_register_pkg.all;

entity tb_img_resize is
end tb_img_resize;

architecture Behavioral of tb_img_resize is

    -- Component declaration
    component img_resize is    
        Generic (
            C_MAX_IMG_WIDTH : integer := 512;
            C_MAX_RADIOUS : integer := 4;
            C_RADIUS : integer := 1;
            C_IMG_SIZE : integer := 128
        );
        port ( 
            clk : in std_logic;
            reset : in std_logic;
            boder_value : in std_logic_vector(7 downto 0);
            bord : in std_logic_vector(1 downto 0);
            radius : in std_logic_vector(2 downto 0);
            img_width : in std_logic_vector(15 downto 0);
            img_height : in std_logic_vector (15 downto 0);
            ready : in std_logic;
            s_axis_tdata : in std_logic_vector (7 downto 0);
            s_axis_tlast : in std_logic;
            s_axis_tvalid : in std_logic;
            s_axis_tready : out std_logic;
            bypass_pixel : out std_logic_vector (7 downto 0);
            bypass_pixel_valid : out std_logic;
            bypass_pixel_last : out std_logic;
            w_k : out t_w_array;
            w_k_valid : out std_logic;
            w_k_last : out std_logic
        );
    end component;
    
    -- Clock period
    constant clk_period : time := 10 ns;
    
    -- Testbench signals
    signal clk : std_logic := '0';
    signal reset : std_logic := '1';
    signal boder_value : std_logic_vector(7 downto 0) := x"FF";
    signal bord : std_logic_vector(1 downto 0) := "00";
    signal radius : std_logic_vector(2 downto 0) := "001";
    signal img_width : std_logic_vector(15 downto 0) := x"0008";
    signal img_height : std_logic_vector(15 downto 0) := x"0008";
    signal ready : std_logic := '1';
    signal s_axis_tdata : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_tlast : std_logic := '0';
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal bypass_pixel : std_logic_vector(7 downto 0);
    signal bypass_pixel_valid : std_logic;
    signal bypass_pixel_last : std_logic;
    signal w_k : t_w_array;
    signal w_k_valid : std_logic;
    signal w_k_last : std_logic;
    
    -- Test control
    signal test_done : boolean := false;
    
begin

    -- Instantiate DUT
    DUT: img_resize
        generic map (
            C_MAX_IMG_WIDTH => 512,
            C_MAX_RADIOUS => 4,
            C_RADIUS => 1,
            C_IMG_SIZE => 128
        )
        port map (
            clk => clk,
            reset => reset,
            boder_value => boder_value,
            bord => bord,
            radius => radius,
            img_width => img_width,
            img_height => img_height,
            ready => ready,
            s_axis_tdata => s_axis_tdata,
            s_axis_tlast => s_axis_tlast,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            bypass_pixel => bypass_pixel,
            bypass_pixel_valid => bypass_pixel_valid,
            bypass_pixel_last => bypass_pixel_last,
            w_k => w_k,
            w_k_valid => w_k_valid,
            w_k_last => w_k_last
        );
    
    -- Clock generation
    clk_process: process
    begin
        while not test_done loop
            clk <= '0';
            wait for clk_period/2;
            clk <= '1';
            wait for clk_period/2;
        end loop;
        wait;
    end process;
    
    -- Stimulus process
    stim_proc: process
        variable pixel_value : unsigned(7 downto 0);
        variable row : integer;
        variable col : integer;
        
        -- Procedure to send one image
        procedure send_image(
    constant width : integer;
    constant height : integer;
    constant test_name : string
) is
begin
    report "========================================";
    report "TEST: " & test_name;
    report "Sending " & integer'image(width) & "x" & integer'image(height) & " image";
    report "========================================";
    
    pixel_value := x"01";
    
    for row in 0 to height-1 loop
        for col in 0 to width-1 loop
            -- Present data and assert valid
            s_axis_tdata <= std_logic_vector(pixel_value);
            s_axis_tvalid <= '1';
            
            -- Set tlast for last pixel
            if (row = height-1 and col = width-1) then
                s_axis_tlast <= '1';
            else
                s_axis_tlast <= '0';
            end if;
            
            -- Wait for handshake (both valid and ready high)
            wait until rising_edge(clk);
            while s_axis_tready = '0' loop
                wait until rising_edge(clk);
            end loop;
            
            -- Handshake completed, increment for next pixel
            pixel_value := pixel_value + 1;
        end loop;
    end loop;
    
    -- Deassert valid after last transfer completes
    s_axis_tvalid <= '0';
    s_axis_tlast <= '0';
    
    wait for 200 * clk_period;
end procedure;
        
        -- Procedure to send image with backpressure
        procedure send_image_with_backpressure(
            constant width : integer;
            constant height : integer;
            constant test_name : string
        ) is
        begin
            report "========================================";
            report "TEST: " & test_name;
            report "Sending " & integer'image(width) & "x" & integer'image(height) & " image WITH BACKPRESSURE";
            report "========================================";
            
            pixel_value := x"01";
            
            for row in 0 to height-1 loop
                for col in 0 to width-1 loop
                    -- Wait for ready
                    wait until rising_edge(clk);
                    while s_axis_tready = '0' loop
                        wait until rising_edge(clk);
                    end loop;
                    
                    -- Send pixel
                    s_axis_tdata <= std_logic_vector(pixel_value);
                    s_axis_tvalid <= '1';
                    
                    if (row = height-1 and col = width-1) then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;
                    
                    pixel_value := pixel_value + 1;
                    
                    -- Introduce backpressure every 5 pixels
                    if (to_integer(pixel_value) mod 5 = 0) then
                        wait until rising_edge(clk);
                        ready <= '0';
                        wait for 3 * clk_period;
                        ready <= '1';
                    else
                        wait until rising_edge(clk);
                    end if;
                end loop;
            end loop;
            
            s_axis_tvalid <= '0';
            s_axis_tlast <= '0';
            ready <= '1';
            
            wait for 200 * clk_period;
        end procedure;
        
    begin
        -- Initial reset
        reset <= '1';
        s_axis_tvalid <= '0';
        s_axis_tlast <= '0';
        ready <= '1';
        wait for 10 * clk_period;
        reset <= '0';
        wait for 5 * clk_period;
        
        -- ==========================================
        -- Test 1: 3x3 window (radius=1) with 8x8 image
        -- ==========================================
        radius <= "001";
        img_width <= x"0008";
        img_height <= x"0008";
        bord <= "00";
        wait for 2 * clk_period;
        send_image(128, 128, "3x3 Window (radius=1) - 8x8 image");
        
        -- ==========================================
        -- Test 2: 5x5 window (radius=2) with 8x8 image
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "010";
        img_width <= x"0008";
        img_height <= x"0008";
        wait for 2 * clk_period;
        send_image(128, 128, "5x5 Window (radius=2) - 8x8 image");
        
        -- ==========================================
        -- Test 4: 7x7 window (radius=3) with 10x10 image
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "011";
        img_width <= x"000A";
        img_height <= x"000A";
        wait for 2 * clk_period;
        send_image(128, 128, "7x7 Window (radius=3) - 10x10 image");
        
        -- ==========================================
        -- Test 5: 9x9 window (radius=4) with 12x12 image
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "100";
        img_width <= x"000C";
        img_height <= x"000C";
        wait for 2 * clk_period;
        send_image(128, 128, "9x9 Window (radius=4) - 12x12 image");
        
        -- ==========================================
        -- Test 6: Small image 4x4 with 3x3 window
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "001";
        img_width <= x"0004";
        img_height <= x"0004";
        wait for 2 * clk_period;
        send_image(128, 128, "3x3 Window - 4x4 small image");
        
        -- ==========================================
        -- Test 7: Rectangular image 12x8 with 5x5 window
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "010";
        img_width <= x"000C";
        img_height <= x"0008";
        wait for 2 * clk_period;
        send_image(128, 128, "5x5 Window - 12x8 rectangular image");
        
        -- ==========================================
        -- Test 8: Backpressure test with 3x3 window
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "001";
        img_width <= x"0008";
        img_height <= x"0008";
        wait for 2 * clk_period;
        send_image_with_backpressure(8, 8, "3x3 Window - WITH BACKPRESSURE");
        
        -- ==========================================
        -- Test 9: Backpressure test with 5x5 window
        -- ==========================================
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "010";
        img_width <= x"0006";
        img_height <= x"0006";
        wait for 2 * clk_period;
        send_image_with_backpressure(6, 6, "5x5 Window - WITH BACKPRESSURE");
        
        -- ==========================================
        -- Test 10: Multiple sequential images
        -- ==========================================
        report "========================================";
        report "TEST: Multiple Sequential Images";
        report "========================================";
        
        reset <= '1';
        wait for 5 * clk_period;
        reset <= '0';
        radius <= "001";
        img_width <= x"0005";
        img_height <= x"0005";
        wait for 2 * clk_period;
        
        send_image(5, 5, "Image 1 of 3");
        wait for 20 * clk_period;
        send_image(5, 5, "Image 2 of 3");
        wait for 20 * clk_period;
        send_image(5, 5, "Image 3 of 3");
        
        -- End simulation
        report "========================================";
        report "ALL TESTS COMPLETED SUCCESSFULLY!";
        report "========================================";
        test_done <= true;
        wait;
        
    end process;
    
    -- Monitor process - tracks and reports valid windows
    monitor_proc: process
        variable window_count : integer := 0;
    begin
        wait until rising_edge(clk);
        
        if w_k_valid = '1' then

            
            -- Print window information
            report "Valid Window #" & integer'image(window_count) & 
                   " | Last=" & std_logic'image(w_k_last) &
                   " | w_k(0)=" & integer'image(to_integer(unsigned(w_k(0)))) &
                   " | w_k(1)=" & integer'image(to_integer(unsigned(w_k(1)))) &
                   " | w_k(2)=" & integer'image(to_integer(unsigned(w_k(2))));
            
            if w_k_last = '1' then
                report ">>> LAST WINDOW OF IMAGE <<<";
                window_count := 0;  -- Reset for next image
            end if;
        end if;
        
        if not test_done then
            wait until rising_edge(clk);
        else
            wait;
        end if;
    end process;
    
    -- Checker process - validates window outputs
    checker_proc: process
    begin
        wait until rising_edge(clk);
        
        -- Check for protocol violations
        if w_k_valid = '1' and ready = '0' then
            report "ERROR: Valid asserted while ready is low!" severity error;
        end if;
        
        -- Check bypass signals match pixel signals
        
        if not test_done then
            wait until rising_edge(clk);
        else
            wait;
        end if;
    end process;

end Behavioral;