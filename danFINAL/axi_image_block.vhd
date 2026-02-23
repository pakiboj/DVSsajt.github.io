----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.02.2026 09:11:59
-- Design Name: 
-- Module Name: axi_image_block - Behavioral
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
use IEEE.NUMERIC_STD.ALL;
use work.axi_registers_pkg.all;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity axi_image_block is    
    Generic (
        C_MAX_IMG_WIDTH : integer := 512;
        C_MAX_RADIOUS : integer := 4;
        C_RADIUS : integer := 1;
        C_IMG_SIZE : integer := 128
    );
  port ( 
    clk : in std_logic;
    
    -- Synchronous active high reset
    reset : in std_logic;
    
    -- Config parameters
    border_value : in std_logic_vector(7 downto 0);
    bord : in std_logic_vector(1 downto 0);
    radius : in std_logic_vector(2 downto 0);
    img_width : in std_logic_vector(15 downto 0);
    img_height : in std_logic_vector (15 downto 0);
    
    -- Signal that indicates if the pipeline stages are active --
    ready : in std_logic;
    
    -- AXI Stream input interface --
    s_axis_tdata : in std_logic_vector (7 downto 0);
    s_axis_tlast : in std_logic;
    s_axis_tvalid : in std_logic;
    s_axis_tready : out std_logic;
    
    -- Accepted pixel at input, can be used for bypass mode --
    bypass_pixel : out std_logic_vector (7 downto 0);
    bypass_pixel_valid : out std_logic;
    bypass_pixel_last : out std_logic;
    
    --output of all windows
    w_k : out t_w_array;
    w_k_valid : out std_logic;
    w_k_last : out std_logic
    
  );
end axi_image_block;

architecture Behavioral of axi_image_block is

    constant C_ZERO_10b : std_logic_vector (9 downto 0) := "0000000000";
    constant C_ZERO_8b : std_logic_vector (7 downto 0) := "00000000";
    constant BRAM_WIDTH  : integer := 8 * C_RADIUS * 2; 
    constant BRAM_DEPTH  : integer := C_IMG_SIZE; 
    
    -- BRAM --
    component BRAM is
            Generic (
            C_MAX_IMG_WIDTH : integer := 512;
            C_MAX_RADIOUS : integer := 4;
            C_RADIUS : integer := 1;
            C_IMG_SIZE : integer := 9
        );
        Port ( 
            clk : in STD_LOGIC;
            reset : in STD_LOGIC;
            enable : in std_logic;
            data_in : in STD_LOGIC_VECTOR (7 downto 0);
            data_out_1 : out STD_LOGIC_VECTOR (7 downto 0);
            data_out_2 : out STD_LOGIC_VECTOR (7 downto 0)
        );
    end component;
    
    -- Ready of the input AXI stream interface --
    signal axis_tready : std_logic;
    signal input_pixel_stream_done : std_logic;
    
    -- Counters for coordinates of current central pixel after the first line buffer is filled--
    -- While the buffer is being filled they hold the coordinates of the last accepted valid input pixel
    signal pixel_row_cnt : std_logic_vector (9 downto 0);
    signal pixel_col_cnt : std_logic_vector (9 downto 0);
    
    -- img_w-1 and img_h-1 --
    signal last_col_index : std_logic_vector (9 downto 0);
    signal last_row_index : std_logic_vector (9 downto 0);
    
    signal first_col_index : std_logic_vector (9 downto 0);
    signal first_row_index : std_logic_vector (9 downto 0);
     
    -- BRAM internal signals
    signal line_buff_clk_en : std_logic;
    signal BRAM1_out1 : std_logic_vector (7 downto 0);
    signal BRAM1_out2 : std_logic_vector (7 downto 0);
    signal BRAM2_out1 : std_logic_vector (7 downto 0);
    signal BRAM2_out2 : std_logic_vector (7 downto 0);
    signal BRAM1_row1_filled : std_logic;
    signal BRAM1_row2_filled : std_logic;
    signal BRAM2_row1_filled : std_logic;
    signal BRAM2_row2_filled : std_logic;
    
    signal BRAM3_out1 : std_logic_vector (7 downto 0);
    signal BRAM3_out2 : std_logic_vector (7 downto 0);
    signal BRAM4_out1 : std_logic_vector (7 downto 0);
    signal BRAM4_out2 : std_logic_vector (7 downto 0);
    signal BRAM3_row1_filled : std_logic;
    signal BRAM3_row2_filled : std_logic;
    signal BRAM4_row1_filled : std_logic;
    signal BRAM4_row2_filled : std_logic;
    
    signal window_k : t_w_array;
    
    -- Value passed to gradient calculation component for edge cases
    signal bord_fill : std_logic_vector (7 downto 0);
    
    -- Input data signal, used for resizing
    signal input_data : std_logic_vector (7 downto 0);
    -- Last input switch, used for resizing
	signal tlast_switch : std_logic := '0';
	
	--signals used for resizing of nearest values
	signal pixel_addition_1 : std_logic_vector (7 downto 0);
    signal pixel_addition_2 : std_logic_vector (7 downto 0);
    signal pixel_addition_3 : std_logic_vector (7 downto 0);
    signal pixel_addition_4 : std_logic_vector (7 downto 0);
    signal pixel_addition_in : std_logic_vector (7 downto 0);
    
    -- Skid buffer at input AXIS interface used for enhanced proccessing--
    signal pixel : std_logic_vector (7 downto 0);
    signal pixel_valid : std_logic;
    signal pixel_last : std_logic;
    signal pixel_skid_buff : std_logic_vector (7 downto 0);
    signal pixel_skid_buff_valid : std_logic;
    signal pixel_skid_buff_last : std_logic;
    signal pixel_skid_buff_full : std_logic;

begin

    -----------------------------------------------------------------------------------------------------------------------
    -------------------------------------------- Initializing BRAMS -------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    BRAM1 : entity work.BRAM
    generic map (
        C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
        C_MAX_RADIOUS   => C_MAX_RADIOUS,
        C_RADIUS        => C_RADIUS,
        C_IMG_SIZE      => C_IMG_SIZE
    )
    port map (
        clk      => clk,
        reset    => reset,
        enable => line_buff_clk_en,
        data_in  => pixel,
        data_out_1 => BRAM1_out1,
        data_out_2 => BRAM1_out2
    );
    BRAM2 : entity work.BRAM
    generic map (
        C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
        C_MAX_RADIOUS   => C_MAX_RADIOUS,
        C_RADIUS        => C_RADIUS,
        C_IMG_SIZE      => C_IMG_SIZE
    )
    port map (
        clk      => clk,
        reset    => reset,
        enable => line_buff_clk_en,
        data_in  => BRAM1_out2,
        data_out_1 => BRAM2_out1,
        data_out_2 => BRAM2_out2
    );
    BRAM3 : entity work.BRAM
    generic map (
        C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
        C_MAX_RADIOUS   => C_MAX_RADIOUS,
        C_RADIUS        => C_RADIUS,
        C_IMG_SIZE      => C_IMG_SIZE
    )
    port map (
        clk      => clk,
        reset    => reset,
        enable => line_buff_clk_en,
        data_in  => BRAM2_out2,
        data_out_1 => BRAM3_out1,
        data_out_2 => BRAM3_out2
    );
    BRAM4 : entity work.BRAM
    generic map (
        C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
        C_MAX_RADIOUS   => C_MAX_RADIOUS,
        C_RADIUS        => C_RADIUS,
        C_IMG_SIZE      => C_IMG_SIZE
    )
    port map (
        clk      => clk,
        reset    => reset,
        enable => line_buff_clk_en,
        data_in  => BRAM3_out2,
        data_out_1 => BRAM4_out1,
        data_out_2 => BRAM4_out2
    );

    last_col_index <= std_logic_vector(to_unsigned(to_integer(unsigned(img_width)) - 1 , 10));
    last_row_index <= std_logic_vector(to_unsigned(to_integer(unsigned(img_height)) - 1 , 10));
    first_row_index <= (others => '0');
    first_col_index <= (others => '0');
    -----------------------------------------------------------------------------------------------------------------------
    --------- Logic for making sure valid pixels are being processed and for indicating when to give output ---------------
    -----------------------------------------------------------------------------------------------------------------------
    process (clk) is
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
            -- singalsed used for signaling us when borders are reached, better than making counters, even tho i used counters in BRAM
                
                input_pixel_stream_done <= '0';
            else
                if (input_pixel_stream_done = '0') then
                    if (pixel_last = '1' and pixel_valid = '1' and ready = '1') then
                        input_pixel_stream_done <= '1';
                    end if; 
                else
                    if (pixel_row_cnt = last_row_index and pixel_col_cnt = last_col_index) then
                        input_pixel_stream_done <= '0';
                    end if;
                end if;
            end if;
        end if;
    end process;
    
    -- Until last pixel is accepted at input, we will store on each handshake, but after that we need to empty out all the values stored in line buffer --
    line_buff_clk_en <= (pixel_valid and ready) when (input_pixel_stream_done = '0') else ready;

    -----------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------- s_axis_tlast switch ----------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------

	process (clk) is 
	begin
		if (rising_edge(clk)) then
            if (reset = '1') then
				tlast_switch <= '0';
            else
				if(s_axis_tlast = '1')then
					tlast_switch <= '1';
				end if;
			end if;
		end if;
	end process;
	
	-----------------------------------------------------------------------------------------------------------------------
    ----------------------------------------------- LAST WiNDOW LOGIC -----------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    -- pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))
    process(pixel_row_cnt,pixel_col_cnt, last_row_index, last_col_index ) is
    begin
        if(pixel_row_cnt = last_row_index and pixel_col_cnt = last_col_index ) then
            w_k_last <= '1';
        else
            w_k_last <= '0';
        end if;
    end process;

	-----------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------- NEAERST VALUES LOGIC ---------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
	 process(pixel_row_cnt, bord, radius, tlast_switch, pixel, border_value, first_row_index, 
			BRAM1_out1, BRAM1_out2,
			BRAM2_out1, BRAM2_out2,
			BRAM3_out1, BRAM3_out2,
			BRAM4_out1, BRAM4_out2
			)is
	 begin
	    pixel_addition_1  <= (others => '0');
        pixel_addition_2  <= (others => '0');
        pixel_addition_3  <= (others => '0');
        pixel_addition_4  <= (others => '0');
        pixel_addition_in <= (others => '0');
		case(radius)is
			when "001" =>
				if(bord = "10" )then
					if(pixel_row_cnt = first_row_index) then    
					--elsif(pixel_row_cnt = last_row_index) then
						pixel_addition_1 <= BRAM1_out1;
					else
						pixel_addition_1 <= BRAM1_out2;
					end if;
					
					if(tlast_switch = '1')then 
                        pixel_addition_in <= BRAM1_out1;
                    else
                        pixel_addition_in <= pixel;
                    end if;
				else
					pixel_addition_1 <= BRAM1_out2;
					pixel_addition_in <= pixel;
				end if;
			when "010" =>
				if(bord = "10" )then
					if(pixel_row_cnt = first_row_index) then
						pixel_addition_1 <= BRAM1_out2;
						pixel_addition_2 <= BRAM1_out2;
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
						pixel_addition_1 <= BRAM2_out1;
						pixel_addition_2 <= BRAM2_out1;
					else
						pixel_addition_1 <= BRAM2_out1;
						pixel_addition_2 <= BRAM2_out2;
					end if;
					
					if(tlast_switch = '1')then 
                        pixel_addition_in <= BRAM1_out1;
                    else
                        pixel_addition_in <= pixel;
                    end if;
				else
					pixel_addition_1 <= BRAM2_out1;
					pixel_addition_2 <= BRAM2_out2;
					pixel_addition_in <= pixel;
				end if;
			when "011" =>
				if(bord = "10" )then
					if(pixel_row_cnt = first_row_index) then
						pixel_addition_1 <= BRAM2_out1;
						pixel_addition_2 <= BRAM2_out1;
						pixel_addition_3 <= BRAM2_out1;
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
						pixel_addition_1 <= BRAM2_out2;
						pixel_addition_2 <= BRAM2_out2;
						pixel_addition_3 <= BRAM2_out2;
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(2,first_row_index'length))) then
						pixel_addition_1 <= BRAM2_out2;
						pixel_addition_2 <= BRAM3_out1;
						pixel_addition_3 <= BRAM3_out1;
					else
						pixel_addition_1 <= BRAM2_out2;
						pixel_addition_2 <= BRAM3_out1;
						pixel_addition_3 <= BRAM3_out2; 
					end if;
					
					if(tlast_switch = '1')then 
                        pixel_addition_in <= BRAM1_out1;
                    else
                        pixel_addition_in <= pixel;
                    end if;
				else
					pixel_addition_1 <= BRAM2_out2;
					pixel_addition_2 <= BRAM3_out1;
					pixel_addition_3 <= BRAM3_out2;
					pixel_addition_in <= pixel;
				end if;
			when "100" =>
				if(bord = "10" )then
					if(pixel_row_cnt = first_row_index) then
						pixel_addition_1 <= BRAM2_out2;
						pixel_addition_2 <= BRAM2_out2;
						pixel_addition_3 <= BRAM2_out2;
						pixel_addition_4 <= BRAM2_out2;
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
						pixel_addition_1 <= BRAM3_out1;
						pixel_addition_2 <= BRAM3_out1;
						pixel_addition_3 <= BRAM3_out1;
						pixel_addition_4 <= BRAM3_out1;
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(2,first_row_index'length))) then
						pixel_addition_1 <= BRAM3_out1;
						pixel_addition_2 <= BRAM3_out2;
						pixel_addition_3 <= BRAM3_out2;
						pixel_addition_4 <= BRAM3_out2;
						
					elsif(pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(3,first_row_index'length))) then
						pixel_addition_1 <= BRAM3_out1;
						pixel_addition_2 <= BRAM3_out2;
						pixel_addition_3 <= BRAM4_out1;
						pixel_addition_4 <= BRAM4_out1;
					else
						pixel_addition_1 <= BRAM3_out1;
						pixel_addition_2 <= BRAM3_out2;
						pixel_addition_3 <= BRAM4_out1;
						pixel_addition_4 <= BRAM4_out2;
					end if;
					
					if(tlast_switch = '1')then 
                        pixel_addition_in <= BRAM1_out1;
                    else
                        pixel_addition_in <= pixel;
                    end if;
				else
					pixel_addition_1 <= BRAM3_out1;
					pixel_addition_2 <= BRAM3_out2;
					pixel_addition_3 <= BRAM4_out1;
					pixel_addition_4 <= BRAM4_out2;
					pixel_addition_in <= pixel;
				end if;
			when others =>
                pixel_addition_1 <= (others => '0');
                pixel_addition_2 <= (others => '0');
                pixel_addition_3 <= (others => '0');
                pixel_addition_4 <= (others => '0');
                pixel_addition_in <= (others => '0');
		end case;

	 end process;   


 
    -----------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------- WINDOW SHIFTING LOGIC --------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    process (clk) is
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                window_k <= (others => (others => '0'));
            else
                if (line_buff_clk_en = '1') then
                    case(radius) is
                        when "001" =>  -- 3x3 window
                            -- Row 0 (current row with center pixel)
                            window_k(0) <= pixel_addition_in;
                            window_k(1) <= window_k(0);
                            window_k(2) <= window_k(1);
                            
                            -- Row 1 (one row above from BRAM1_out1)
                            window_k(3) <= BRAM1_out1;
                            window_k(4) <= window_k(3);
                            window_k(5) <= window_k(4);
                            
                            -- Row 2 (two rows above from BRAM1_out2)
                            window_k(6) <= pixel_addition_1;
                            window_k(7) <= window_k(6);
                            window_k(8) <= window_k(7);
                            
                        when "010" =>  -- 5x5 window
                            -- Row 0 (current row with center pixel)
							
							window_k(0) <= pixel_addition_in;
                            window_k(1) <= window_k(0);
                            window_k(2) <= window_k(1);
                            window_k(3) <= window_k(2);
                            window_k(4) <= window_k(3);
                            
                            -- Row 1 (one row above from BRAM1_out1)
                            window_k(5) <= BRAM1_out1;
                            window_k(6) <= window_k(5);
                            window_k(7) <= window_k(6);
                            window_k(8) <= window_k(7);
                            window_k(9) <= window_k(8);
                            
                            -- Row 2 (two rows above from BRAM1_out2)
                            window_k(10) <= BRAM1_out2;
                            window_k(11) <= window_k(10);
                            window_k(12) <= window_k(11);
                            window_k(13) <= window_k(12);
                            window_k(14) <= window_k(13);
                            
                            -- Row 3 (three rows above from BRAM2_out1)
                            window_k(15) <= pixel_addition_1;
                            window_k(16) <= window_k(15);
                            window_k(17) <= window_k(16);
                            window_k(18) <= window_k(17);
                            window_k(19) <= window_k(18);
                            
                            -- Row 4 (four rows above from BRAM2_out2)
                            window_k(20) <= pixel_addition_2;
                            window_k(21) <= window_k(20);
                            window_k(22) <= window_k(21);
                            window_k(23) <= window_k(22);
                            window_k(24) <= window_k(23);
                            
                        when "011" =>  -- 7x7 window
                            -- Row 0 (current row with center pixel)
							
							window_k(0) <= pixel_addition_in;
                            window_k(1) <= window_k(0);
                            window_k(2) <= window_k(1);
                            window_k(3) <= window_k(2);
                            window_k(4) <= window_k(3);
                            window_k(5) <= window_k(4);
                            window_k(6) <= window_k(5);
                            
                            -- Row 1 (one row above from BRAM1_out1)
                            window_k(7) <= BRAM1_out1;
                            window_k(8) <= window_k(7);
                            window_k(9) <= window_k(8);
                            window_k(10) <= window_k(9);
                            window_k(11) <= window_k(10);
                            window_k(12) <= window_k(11);
                            window_k(13) <= window_k(12);
                            
                            -- Row 2 (two rows above from BRAM1_out2)
                            window_k(14) <= BRAM1_out2;
                            window_k(15) <= window_k(14);
                            window_k(16) <= window_k(15);
                            window_k(17) <= window_k(16);
                            window_k(18) <= window_k(17);
                            window_k(19) <= window_k(18);
                            window_k(20) <= window_k(19);
                            
                            -- Row 3 (three rows above from BRAM2_out1)
                            window_k(21) <= BRAM2_out1;
                            window_k(22) <= window_k(21);
                            window_k(23) <= window_k(22);
                            window_k(24) <= window_k(23);
                            window_k(25) <= window_k(24);
                            window_k(26) <= window_k(25);
                            window_k(27) <= window_k(26);
                            
                            -- Row 4 (four rows above from BRAM2_out2)
                            window_k(28) <= pixel_addition_1;  -- BRAM2_out2
                            window_k(29) <= window_k(28);
                            window_k(30) <= window_k(29);
                            window_k(31) <= window_k(30);
                            window_k(32) <= window_k(31);
                            window_k(33) <= window_k(32);
                            window_k(34) <= window_k(33);
                            
                            -- Row 5 (five rows above - needs another BRAM level or hold previous values)
                            window_k(35) <= pixel_addition_2;  -- Hold or feed from additional BRAM -- BRAM3_out1
                            window_k(36) <= window_k(35);
                            window_k(37) <= window_k(36);
                            window_k(38) <= window_k(37);
                            window_k(39) <= window_k(38);
                            window_k(40) <= window_k(39);
                            window_k(41) <= window_k(40);
                            
                            -- Row 6 (six rows above - needs another BRAM level or hold previous values)
                            window_k(42) <= pixel_addition_3;  -- Hold or feed from additional BRAM -- BRAM3_out2
                            window_k(43) <= window_k(42);
                            window_k(44) <= window_k(43);
                            window_k(45) <= window_k(44);
                            window_k(46) <= window_k(45);
                            window_k(47) <= window_k(46);
                            window_k(48) <= window_k(47);
                            
                        when "100" =>  -- 9x9 window
                            -- Row 0 (current row with center pixel)
							window_k(0) <= pixel_addition_in;
                            window_k(1) <= window_k(0);
                            window_k(2) <= window_k(1);
                            window_k(3) <= window_k(2);
                            window_k(4) <= window_k(3);
                            window_k(5) <= window_k(4);
                            window_k(6) <= window_k(5);
                            window_k(7) <= window_k(6);
                            window_k(8) <= window_k(7);
                            
                            -- Row 1 (one row above from BRAM1_out1)
                            window_k(9) <= BRAM1_out1;
                            window_k(10) <= window_k(9);
                            window_k(11) <= window_k(10);
                            window_k(12) <= window_k(11);
                            window_k(13) <= window_k(12);
                            window_k(14) <= window_k(13);
                            window_k(15) <= window_k(14);
                            window_k(16) <= window_k(15);
                            window_k(17) <= window_k(16);
                            
                            -- Row 2 (two rows above from BRAM1_out2)
                            window_k(18) <= BRAM1_out2;
                            window_k(19) <= window_k(18);
                            window_k(20) <= window_k(19);
                            window_k(21) <= window_k(20);
                            window_k(22) <= window_k(21);
                            window_k(23) <= window_k(22);
                            window_k(24) <= window_k(23);
                            window_k(25) <= window_k(24);
                            window_k(26) <= window_k(25);
                            
                            -- Row 3 (three rows above from BRAM2_out1)
                            window_k(27) <= BRAM2_out1;
                            window_k(28) <= window_k(27);
                            window_k(29) <= window_k(28);
                            window_k(30) <= window_k(29);
                            window_k(31) <= window_k(30);
                            window_k(32) <= window_k(31);
                            window_k(33) <= window_k(32);
                            window_k(34) <= window_k(33);
                            window_k(35) <= window_k(34);
                            
                            -- Row 4 (four rows above from BRAM2_out2)
                            window_k(36) <= BRAM2_out2;
                            window_k(37) <= window_k(36);
                            window_k(38) <= window_k(37);
                            window_k(39) <= window_k(38);
                            window_k(40) <= window_k(39);
                            window_k(41) <= window_k(40);
                            window_k(42) <= window_k(41);
                            window_k(43) <= window_k(42);
                            window_k(44) <= window_k(43);
                            
                            -- Row 5 (five rows above - needs additional BRAM or storage)
                            window_k(45) <= pixel_addition_1;  -- Hold previous values
                            window_k(46) <= window_k(45);
                            window_k(47) <= window_k(46);
                            window_k(48) <= window_k(47);
                            window_k(49) <= window_k(48);
                            window_k(50) <= window_k(49);
                            window_k(51) <= window_k(50);
                            window_k(52) <= window_k(51);
                            window_k(53) <= window_k(52);
                            
                            -- Row 6 (six rows above)
                            window_k(54) <= pixel_addition_2;
                            window_k(55) <= window_k(54);
                            window_k(56) <= window_k(55);
                            window_k(57) <= window_k(56);
                            window_k(58) <= window_k(57);
                            window_k(59) <= window_k(58);
                            window_k(60) <= window_k(59);
                            window_k(61) <= window_k(60);
                            window_k(62) <= window_k(61);
                            
                            -- Row 7 (seven rows above)
                            window_k(63) <= pixel_addition_3;
                            window_k(64) <= window_k(63);
                            window_k(65) <= window_k(64);
                            window_k(66) <= window_k(65);
                            window_k(67) <= window_k(66);
                            window_k(68) <= window_k(67);
                            window_k(69) <= window_k(68);
                            window_k(70) <= window_k(69);
                            window_k(71) <= window_k(70);
                            
                            -- Row 8 (eight rows above)
                            window_k(72) <= pixel_addition_4;
                            window_k(73) <= window_k(72);
                            window_k(74) <= window_k(73);
                            window_k(75) <= window_k(74);
                            window_k(76) <= window_k(75);
                            window_k(77) <= window_k(76);
                            window_k(78) <= window_k(77);
                            window_k(79) <= window_k(78);
                            window_k(80) <= window_k(79);
                            
                        when others =>
                            window_k <= (others => (others => '0'));
                    end case;
                end if;
            end if;
        end if;
    end process;
    
-----------------------------------------------------------------------------------------------------------------------
    ---------------------------------------- Proccessed pixel coordinate counter ------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    
    process(clk) is
    begin
        if rising_edge(clk) then
            if (reset = '1') then
                pixel_row_cnt <= (others => '0');
                pixel_col_cnt <= (others => '0');
                BRAM1_row1_filled <= '0';
				BRAM1_row2_filled <= '0';
				BRAM2_row1_filled <= '0';
				BRAM2_row2_filled <= '0';
				BRAM3_row1_filled <= '0';
				BRAM3_row2_filled <= '0';
				BRAM4_row1_filled <= '0';
				BRAM4_row2_filled <= '0';
            else
                if (line_buff_clk_en = '1') then
                    case (radius) is
                        when "001" =>  -- 3x3 
                            if (BRAM1_row1_filled = '1') then
                                if (BRAM1_row2_filled = '1') then
                                    
                                    --pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) - to_unsigned(2,pixel_col_cnt'length));
                                    if (pixel_col_cnt = last_col_index) then
                                        if (pixel_row_cnt = last_row_index) then -- End of image
                                            pixel_row_cnt <= (others => '0');
                                            pixel_col_cnt <= (others => '0');
                                            BRAM1_row1_filled <= '0';
                                            BRAM1_row2_filled <= '0';
                                        else
                                            pixel_row_cnt <= std_logic_vector(unsigned(pixel_row_cnt) + to_unsigned(1,pixel_row_cnt'length));
                                            pixel_col_cnt <= (others => '0');
                                        end if;
                                    else
                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                    end if;
                                else
                                    -- BRAM1_row1 filled, now filling BRAM1_row2
                                    if (pixel_col_cnt = last_col_index) then
                                        pixel_col_cnt <= "1111111101"; 
                                        BRAM1_row2_filled <= '1';
                                    else
                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(+1,pixel_col_cnt'length));
                                    end if;
                                end if;
                            else
                                -- Filling BRAM1_row1
                                if (pixel_col_cnt = last_col_index) then
                                    pixel_col_cnt <= (others => '0');
                                    BRAM1_row1_filled <= '1';
                                else
                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                end if;
                            end if; 
                        when "010" =>  -- 5x5 window
                            if (BRAM1_row1_filled = '1') then
                                if (BRAM1_row2_filled = '1') then
                                    if (BRAM2_row1_filled = '1') then
                                        if (BRAM2_row2_filled = '1') then
                                            if (pixel_col_cnt = last_col_index) then
                                                if (pixel_row_cnt = last_row_index) then -- End of image
                                                    pixel_row_cnt <= (others => '0');
                                                    pixel_col_cnt <= (others => '0');
                                                    BRAM1_row1_filled <= '0';
                                                    BRAM1_row2_filled <= '0';
                                                    BRAM2_row1_filled <= '0';
                                                    BRAM2_row2_filled <= '0';
                                                else
                                                    pixel_row_cnt <= std_logic_vector(unsigned(pixel_row_cnt) + to_unsigned(1,pixel_row_cnt'length));
                                                    pixel_col_cnt <= (others => '0');
                                                end if;
                                            else
                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                            end if;
                                        else
                                            -- BRAM2_row1 filled, now filling BRAM2_row2
                                            if (pixel_col_cnt = last_col_index) then
                                                pixel_col_cnt <= "1111111100";
                                                BRAM2_row2_filled <= '1';
                                            else
                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                            end if;
                                        end if;
                                    else
                                        -- BRAM1 rows filled, now filling BRAM2_row1
                                        if (pixel_col_cnt = last_col_index) then
                                            pixel_col_cnt <= (others => '0');
                                            BRAM2_row1_filled <= '1';
                                        else
                                            pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                        end if;
                                    end if;
                                else
                                    -- BRAM1_row1 filled, now filling BRAM1_row2
                                    if (pixel_col_cnt = last_col_index) then
                                        pixel_col_cnt <= (others => '0');
                                        BRAM1_row2_filled <= '1';
                                    else
                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                    end if;
                                end if;
                            else
                                -- Filling BRAM1_row1 (first row)
                                if (pixel_col_cnt = last_col_index) then
                                    pixel_col_cnt <= (others => '0');
                                    BRAM1_row1_filled <= '1';
                                else
                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                end if;
                            end if;
                        when "011" =>  -- 7x7 window (needs 3 BRAMs = 6 rows)
                            if (BRAM1_row1_filled = '1') then
                                if (BRAM1_row2_filled = '1') then
                                    if (BRAM2_row1_filled = '1') then
                                        if (BRAM2_row2_filled = '1') then
                                            if (BRAM3_row1_filled = '1') then
                                                if (BRAM3_row2_filled = '1') then
                                                    -- All 6 rows filled, now processing actual image pixels
                                                    if (pixel_col_cnt = last_col_index) then
                                                        if (pixel_row_cnt = last_row_index) then -- End of image
                                                            pixel_row_cnt <= (others => '0');
                                                            pixel_col_cnt <= (others => '0');
                                                            BRAM1_row1_filled <= '0';
                                                            BRAM1_row2_filled <= '0';
                                                            BRAM2_row1_filled <= '0';
                                                            BRAM2_row2_filled <= '0';
                                                            BRAM3_row1_filled <= '0';
                                                            BRAM3_row2_filled <= '0';
                                                        else
                                                            pixel_row_cnt <= std_logic_vector(unsigned(pixel_row_cnt) + to_unsigned(1,pixel_row_cnt'length));
                                                            pixel_col_cnt <= (others => '0');
                                                        end if;
                                                    else
                                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                    end if;
                                                else
                                                    -- BRAM3_row1 filled, now filling BRAM3_row2
                                                    if (pixel_col_cnt = last_col_index) then
                                                        pixel_col_cnt <= "1111111011";
                                                        BRAM3_row2_filled <= '1';
                                                    else
                                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                    end if;
                                                end if;
                                            else
                                                -- BRAM2 rows filled, now filling BRAM3_row1
                                                if (pixel_col_cnt = last_col_index) then
                                                    pixel_col_cnt <= (others => '0');
                                                    BRAM3_row1_filled <= '1';
                                                else
                                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                end if;
                                            end if;
                                        else
                                            -- BRAM2_row1 filled, now filling BRAM2_row2
                                            if (pixel_col_cnt = last_col_index) then
                                                pixel_col_cnt <= (others => '0');
                                                BRAM2_row2_filled <= '1';
                                            else
                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                            end if;
                                        end if;
                                    else
                                        -- BRAM1 rows filled, now filling BRAM2_row1
                                        if (pixel_col_cnt = last_col_index) then
                                            pixel_col_cnt <= (others => '0');
                                            BRAM2_row1_filled <= '1';
                                        else
                                            pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                        end if;
                                    end if;
                                else
                                    -- BRAM1_row1 filled, now filling BRAM1_row2
                                    if (pixel_col_cnt = last_col_index) then
                                        pixel_col_cnt <= (others => '0');
                                        BRAM1_row2_filled <= '1';
                                    else
                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                    end if;
                                end if;
                            else
                                -- Filling BRAM1_row1 (first row)
                                if (pixel_col_cnt = last_col_index) then
                                    pixel_col_cnt <= (others => '0');
                                    BRAM1_row1_filled <= '1';
                                else
                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                end if;
                            end if;
                        when "100" =>  -- 9x9 window (needs 4 BRAMs = 8 rows)
                            if (BRAM1_row1_filled = '1') then
                                if (BRAM1_row2_filled = '1') then
                                    if (BRAM2_row1_filled = '1') then
                                        if (BRAM2_row2_filled = '1') then
                                            if (BRAM3_row1_filled = '1') then
                                                if (BRAM3_row2_filled = '1') then
                                                    if (BRAM4_row1_filled = '1') then
                                                        if (BRAM4_row2_filled = '1') then
                                                            -- All 8 rows filled, now processing actual image pixels
                                                            if (pixel_col_cnt = last_col_index) then
                                                                if (pixel_row_cnt = last_row_index) then -- End of image
                                                                    pixel_row_cnt <= (others => '0');
                                                                    pixel_col_cnt <= (others => '0');
                                                                    BRAM1_row1_filled <= '0';
                                                                    BRAM1_row2_filled <= '0';
                                                                    BRAM2_row1_filled <= '0';
                                                                    BRAM2_row2_filled <= '0';
                                                                    BRAM3_row1_filled <= '0';
                                                                    BRAM3_row2_filled <= '0';
                                                                    BRAM4_row1_filled <= '0';
                                                                    BRAM4_row2_filled <= '0';
                                                                else
                                                                    pixel_row_cnt <= std_logic_vector(unsigned(pixel_row_cnt) + to_unsigned(1,pixel_row_cnt'length));
                                                                    pixel_col_cnt <= (others => '0');
                                                                end if;
                                                            else
                                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                            end if;
                                                        else
                                                            -- BRAM4_row1 filled, now filling BRAM4_row2
                                                            if (pixel_col_cnt = last_col_index) then
                                                                pixel_col_cnt <= "1111111010";
                                                                BRAM4_row2_filled <= '1';
                                                            else
                                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                            end if;
                                                        end if;
                                                    else
                                                        -- BRAM3 rows filled, now filling BRAM4_row1
                                                        if (pixel_col_cnt = last_col_index) then
                                                            pixel_col_cnt <= (others => '0');
                                                            BRAM4_row1_filled <= '1';
                                                        else
                                                            pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                        end if;
                                                    end if;
                                                else
                                                    -- BRAM3_row1 filled, now filling BRAM3_row2
                                                    if (pixel_col_cnt = last_col_index) then
                                                        pixel_col_cnt <= (others => '0');
                                                        BRAM3_row2_filled <= '1';
                                                    else
                                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                    end if;
                                                end if;
                                            else
                                                -- BRAM2 rows filled, now filling BRAM3_row1
                                                if (pixel_col_cnt = last_col_index) then
                                                    pixel_col_cnt <= (others => '0');
                                                    BRAM3_row1_filled <= '1';
                                                else
                                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                                end if;
                                            end if;
                                        else
                                            -- BRAM2_row1 filled, now filling BRAM2_row2
                                            if (pixel_col_cnt = last_col_index) then
                                                pixel_col_cnt <= (others => '0');
                                                BRAM2_row2_filled <= '1';
                                            else
                                                pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                            end if;
                                        end if;
                                    else
                                        -- BRAM1 rows filled, now filling BRAM2_row1
                                        if (pixel_col_cnt = last_col_index) then
                                            pixel_col_cnt <= (others => '0');
                                            BRAM2_row1_filled <= '1';
                                        else
                                            pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                        end if;
                                    end if;
                                else
                                    -- BRAM1_row1 filled, now filling BRAM1_row2
                                    if (pixel_col_cnt = last_col_index) then
                                        pixel_col_cnt <= (others => '0');
                                        BRAM1_row2_filled <= '1';
                                    else
                                        pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                    end if;
                                end if;
                            else
                                -- Filling BRAM1_row1 (first row)
                                if (pixel_col_cnt = last_col_index) then
                                    pixel_col_cnt <= (others => '0');
                                    BRAM1_row1_filled <= '1';
                                else
                                    pixel_col_cnt <= std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length));
                                end if;
                            end if;
                            
                        when others =>
                            null;
                    end case;
                end if;   
            end if;
         end if;
    end process;
	
-----------------------------------------------------------------------------------------------------------------------
    ---------------------------------------------- IMAGE RESIZE LOGIC -----------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------		
	
    process (bord, radius, tlast_switch, s_axis_tdata, border_value, first_col_index, last_col_index, first_row_index, last_row_index, 
             BRAM1_row1_filled, BRAM1_row2_filled,
             BRAM2_row1_filled, BRAM2_row2_filled,
             BRAM3_row1_filled, BRAM3_row2_filled,
             BRAM4_row1_filled, BRAM4_row2_filled,
             BRAM1_out1
    ) is 
    begin
		case (bord) is
			when "11" =>
				case(radius)is
					when "001" => 
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1' and tlast_switch = '1')then
								input_data <= BRAM1_out1;
							else
								input_data  <= s_axis_tdata;
							end if;
						else
							input_data <= border_value;
						end if;
					when "010" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row2_filled = '1' and tlast_switch = '1')then
										input_data <= border_value;
									else
										input_data  <= s_axis_tdata;
									end if;
								else
									input_data <= s_axis_tdata;
								end if;
						    else
						    input_data <= border_value;
							end if;
						else
							input_data <= border_value;
						end if;
					when "011" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1' and tlast_switch = '1')then
											    input_data <= border_value;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= s_axis_tdata;
									end if;
								else
									input_data <= border_value;
								end if;
							else
								input_data <= border_value;
							end if;
						else
							input_data <= border_value;
						end if;	
					when "100" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1')then
												if(BRAM4_row1_filled = '1')then
													if(BRAM4_row2_filled = '1' and tlast_switch = '1')then
													   input_data <= border_value;
													else
														input_data <= s_axis_tdata;
													end if;
												else
													input_data <= s_axis_tdata;
												end if;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= border_value;
									end if;
								else
									input_data <= border_value;
								end if;
							else
								input_data <= border_value;
							end if;
						else
							input_data <= border_value;
						end if;	
					when others =>
						input_data <= (others => '0');
				end case;
			when "10" =>
				case(radius)is
					when "001" => 
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1' and tlast_switch = '1')then
								input_data <= BRAM1_out1;
							else
								input_data  <= s_axis_tdata;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;
					when "010" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row2_filled = '1' and tlast_switch = '1')then
										input_data <= BRAM1_out1;
									else
										input_data  <= s_axis_tdata;
									end if;
								else
									input_data <= s_axis_tdata;
								end if;
						    else
						    input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;
					when "011" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1' and tlast_switch = '1')then
											     input_data <= BRAM1_out1;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= s_axis_tdata;
									end if;
								else
									input_data <= C_ZERO_8b;
								end if;
							else
								input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;	
					when "100" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1')then
												if(BRAM4_row1_filled = '1')then
													if(BRAM4_row2_filled = '1' and tlast_switch = '1')then
													   input_data <= BRAM1_out1;
													else
														input_data <= s_axis_tdata;
													end if;
												else
													input_data <= s_axis_tdata;
												end if;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= C_ZERO_8b;
									end if;
								else
									input_data <= C_ZERO_8b;
								end if;
							else
								input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;	
					when others =>
						input_data <= (others => '0');
				end case;
			when others =>
				case(radius)is
					when "001" => 
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1' and tlast_switch = '1')then
								input_data <= C_ZERO_8b;
							else
								input_data  <= s_axis_tdata;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;
					when "010" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row2_filled = '1' and tlast_switch = '1')then
										input_data <= C_ZERO_8b;
									else
										input_data  <= s_axis_tdata;
									end if;
								else
									input_data <= s_axis_tdata;
								end if;
						    else
						    input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;
					when "011" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1' and tlast_switch = '1')then
											     input_data <= C_ZERO_8b;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= s_axis_tdata;
									end if;
								else
									input_data <= C_ZERO_8b;
								end if;
							else
								input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;	
					when "100" =>
						if(BRAM1_row1_filled = '1')then  
							if(BRAM1_row2_filled = '1')then
								if(BRAM2_row1_filled = '1')then
									if(BRAM2_row1_filled = '1')then
										if(BRAM3_row1_filled = '1')then
											if(BRAM3_row2_filled = '1')then
												if(BRAM4_row1_filled = '1')then
													if(BRAM4_row2_filled = '1' and tlast_switch = '1')then
													   input_data <= C_ZERO_8b;
													else
														input_data <= s_axis_tdata;
													end if;
												else
													input_data <= s_axis_tdata;
												end if;
											else
												input_data <= s_axis_tdata;
											end if;
										else
											input_data <= s_axis_tdata;
										end if;
									else
										input_data <= C_ZERO_8b;
									end if;
								else
									input_data <= C_ZERO_8b;
								end if;
							else
								input_data <= C_ZERO_8b;
							end if;
						else
							input_data <= C_ZERO_8b;
						end if;	
					when others =>
                        input_data <= (others => '0');
				end case;
		end case;
    end process;
    

-----------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------- OUTPUT LOGIC --------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
	
	--std_logic_vector(unsigned(pixel_col_cnt) + to_unsigned(1,pixel_col_cnt'length))
	
	
    process(bord, radius, pixel_col_cnt, pixel_row_cnt, window_k,
    border_value, first_col_index, last_col_index, first_row_index, last_row_index) is
    begin
        w_k <= (others => (others => '0'));
		case (bord) is
			when "11" =>
				case(radius)is
					when "001" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 8 loop
								if (i mod 3 = 2) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 8 loop
								if (i mod 3 = 0) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "010" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 24 loop
								if (i mod 5 > 2) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 24 loop
								if (i mod 5 < 2) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 24 loop
								if (i mod 5 = 4 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 24 loop
								if (i mod 5 = 0 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "011" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 48 loop
								if (i mod 7 > 3) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 48 loop
								if (i mod 7 < 3) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 48 loop
								if (i mod 7 > 4 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 48 loop
								if (i mod 7 < 2 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then
							for i in 0 to 48 loop
								if (i mod 7 = 6 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
							for i in 0 to 48 loop
								if (i mod 7 = 0 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "100" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 80 loop
								if (i mod 9 > 4) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 80 loop
								if (i mod 9 < 4) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 80 loop
								if (i mod 9 > 5 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 80 loop
								if (i mod 9 < 3 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then
							for i in 0 to 80 loop
								if (i mod 9 > 6 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
							for i in 0 to 80 loop
								if (i mod 9 < 2 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(3,first_col_index'length))) then 
							for i in 0 to 80 loop
								if (i mod 9 = 8 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(3,last_col_index'length))) then 
							for i in 0 to 80 loop
								if (i mod 7 = 0 ) then
									w_k(i) <= border_value;
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						else
							w_k <= window_k;
						end if;
					when others =>
                        w_k <= (others => (others => '0'));
				end case;
			when "10" =>
				case(radius)is
					when "001" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 8 loop
								if (i mod 3 = 2) then
									w_k(i) <= window_k(i-1);
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 8 loop
								if (i mod 3 = 0) then
									w_k(i) <= window_k(i+1);
								else
									w_k(i) <= window_k(i);
								end if;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "010" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 24 loop
								case(i mod 5) is
									when 3 => w_k(i) <= window_k(i-1);
									when 4 => w_k(i) <= window_k(i-2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 24 loop
								case(i mod 5) is
									when 1 => w_k(i) <= window_k(i+1);
									when 0 => w_k(i) <= window_k(i+2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 24 loop
								case(i mod 5) is
									when 4 => w_k(i) <= window_k(i-1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 24 loop
								case(i mod 5) is
									when 0 => w_k(i) <= window_k(i+1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "011" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 4 => w_k(i) <= window_k(i-1);
									when 5 => w_k(i) <= window_k(i-2);
									when 6 => w_k(i) <= window_k(i-3);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 2 => w_k(i) <= window_k(i+1);
									when 1 => w_k(i) <= window_k(i+2);
									when 0 => w_k(i) <= window_k(i+3);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 5 => w_k(i) <= window_k(i-1);
									when 6 => w_k(i) <= window_k(i-2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 1 => w_k(i) <= window_k(i+1);
									when 0 => w_k(i) <= window_k(i+2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 6 => w_k(i) <= window_k(i-1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
							for i in 0 to 48 loop
								case (i mod 7) is 
									when 0 => w_k(i) <= window_k(i+1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						else
							w_k <= window_k;
						end if;
					when "100" =>
						if (pixel_col_cnt = first_col_index) then 
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 5 => w_k(i) <= window_k(i-1);
									when 6 => w_k(i) <= window_k(i-2);
									when 7 => w_k(i) <= window_k(i-3);
									when 8 => w_k(i) <= window_k(i-4);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = last_col_index) then
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 3 => w_k(i) <= window_k(i+1);
									when 2 => w_k(i) <= window_k(i+2);
									when 1 => w_k(i) <= window_k(i+3);
									when 0 => w_k(i) <= window_k(i+4);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 6 => w_k(i) <= window_k(i-1);
									when 7 => w_k(i) <= window_k(i-2);
									when 8 => w_k(i) <= window_k(i-3);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 2 => w_k(i) <= window_k(i+1);
									when 1 => w_k(i) <= window_k(i+2);
									when 0 => w_k(i) <= window_k(i+3);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 7 => w_k(i) <= window_k(i-1);
									when 8 => w_k(i) <= window_k(i-2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 1 => w_k(i) <= window_k(i+1);
									when 0 => w_k(i) <= window_k(i+2);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(3,first_col_index'length))) then 
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 8 => w_k(i) <= window_k(i-1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(3,last_col_index'length))) then 
							for i in 0 to 80 loop
								case (i mod 9) is 
									when 0 => w_k(i) <= window_k(i+1);
									when others => w_k(i) <= window_k(i);
								end case;
							end loop;
						else
							w_k <= window_k;
						end if;
					when others =>
                        w_k <= (others => (others => '0'));
				end case;
			when others =>
				case(radius)is
					when "001" =>
						if (pixel_row_cnt = first_row_index) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = last_row_index) then
							w_k <= (others => (others => '0'));
						else
							if (pixel_col_cnt = first_col_index) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = last_col_index) then
								w_k <= (others => (others => '0'));
							else
								w_k <= window_k;
							end if;
						end if;
						
					when "010" =>
						if (pixel_row_cnt = first_row_index) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = last_row_index) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(1,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						else
							if (pixel_col_cnt = first_col_index) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = last_col_index) then
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							else
								w_k <= window_k;
							end if;
						end if;
					when "011" =>
						if (pixel_row_cnt = first_row_index) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = last_row_index) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(1,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(2,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(2,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						else
							if (pixel_col_cnt = first_col_index) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = last_col_index) then
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							else
								w_k <= window_k;
							end if;
						end if;
					when "100" =>
						if (pixel_row_cnt = first_row_index) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = last_row_index) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(1,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(1,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(2,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(2,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(first_row_index) + to_unsigned(3,first_row_index'length))) then
							w_k <= (others => (others => '0'));
						elsif (pixel_row_cnt = std_logic_vector(unsigned(last_row_index) - to_unsigned(3,last_row_index'length))) then 
							w_k <= (others => (others => '0'));
						else
							if (pixel_col_cnt = first_col_index) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = last_col_index) then
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(1,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(1,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(2,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(2,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(first_col_index) + to_unsigned(3,first_col_index'length))) then 
								w_k <= (others => (others => '0'));
							elsif (pixel_col_cnt = std_logic_vector(unsigned(last_col_index) - to_unsigned(3,last_col_index'length))) then 
								w_k <= (others => (others => '0'));
							else
								w_k <= window_k;
							end if;
						end if;
					when others =>
                        w_k <= (others => (others => '0'));
				end case;
		end case;
        
    end process;
    
    -----------------------------------------------------------------------------------------------------------------------
    ------------------------------------ Process for generating VALID for component ---------------------------------------
    ------------------------------------- to know when to start generating outputs ----------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
    
    process(radius, input_pixel_stream_done, pixel_valid, pixel_col_cnt, 
            BRAM1_row1_filled, BRAM1_row2_filled,
            BRAM2_row1_filled, BRAM2_row2_filled,
            BRAM3_row1_filled, BRAM3_row2_filled,
            BRAM4_row1_filled, BRAM4_row2_filled
            ) is
    begin
		case(radius) is
			when "001" =>
			-- UKOLIKO BUDE IMALO PROBLEMA SA TAJMINGOM IZBACI JEDAN PIX_COL_CNT IZ IF
				if(input_pixel_stream_done = '0')then
				    if(pixel_col_cnt = "1111111101" or pixel_col_cnt = "1111111110" or pixel_col_cnt = "1111111111" ) then
				        w_k_valid <='0';
				    else
                        w_k_valid <=BRAM1_row1_filled and BRAM1_row2_filled
                                    and pixel_valid ;
                    end if;
				else
					w_k_valid <= '1';
				end if;
			when "010" =>
				if(input_pixel_stream_done = '0')then
					if(pixel_col_cnt = "1111111100" or pixel_col_cnt = "1111111101" or pixel_col_cnt = "1111111110" or pixel_col_cnt = "1111111111" ) then
						w_k_valid <='0';
					else
						w_k_valid <=BRAM2_row1_filled and BRAM2_row2_filled and
								BRAM1_row1_filled and BRAM1_row2_filled
								and pixel_valid;
					end if;
				else
					w_k_valid <= '1';
				end if;
			when "011" =>
				if(input_pixel_stream_done = '0')then
					if(pixel_col_cnt = "1111111011" or pixel_col_cnt = "1111111100" or pixel_col_cnt = "1111111101" or pixel_col_cnt = "1111111110" or pixel_col_cnt = "1111111111" ) then
						w_k_valid <='0';
					else
						w_k_valid <=BRAM3_row1_filled and BRAM3_row2_filled and 
									BRAM2_row1_filled and BRAM2_row2_filled and 
									BRAM1_row1_filled and BRAM1_row2_filled and 
									pixel_valid;
					end if;

				else
					w_k_valid <= '1';
				end if;
			when "100" =>
				if(input_pixel_stream_done = '0')then
					if(pixel_col_cnt = "1111111010" or pixel_col_cnt = "1111111011" or pixel_col_cnt = "1111111100" or pixel_col_cnt = "1111111101" or pixel_col_cnt = "1111111110" or pixel_col_cnt = "1111111111" ) then
						w_k_valid <='0';
					else
						w_k_valid <=BRAM4_row1_filled and BRAM4_row2_filled and 
									BRAM3_row1_filled and BRAM3_row2_filled and 
									BRAM2_row1_filled and BRAM2_row2_filled and 
									BRAM1_row1_filled and BRAM1_row2_filled and 
									pixel_valid;
					end if;
				else
					w_k_valid <= '1';
				end if;
			when others =>
                w_k_valid <= '0';
		end case;    
    end process;   
    
    
    -----------------------------------------------------------------------------------------------------------------------
    ------------------------------------------------- READY LOGIC ---------------------------------------------------------
    -----------------------------------------------------------------------------------------------------------------------
	--(BRAM1_row1_filled = '0' and pixel_col_cnt = last_col_index) or 
    process (radius, ready, BRAM1_row1_filled, BRAM1_row2_filled, BRAM2_row1_filled, BRAM2_row2_filled) is 
    begin
        case(radius)is
            when "001" =>
                if(BRAM1_row1_filled = '1')then
                    axis_tready <= ready or not BRAM1_row1_filled;
                else
                    axis_tready <= '0';
                end if;
            when "010" =>
				if(BRAM1_row1_filled = '1' and BRAM1_row2_filled = '1')then
                    axis_tready <= ready or not (BRAM1_row1_filled and BRAM1_row2_filled);
                else
                    axis_tready <= '0';
                end if;
            when "011" =>
				if(BRAM1_row1_filled = '1' and BRAM1_row2_filled = '1' and BRAM2_row1_filled = '1')then
                    axis_tready <= ready or not (BRAM1_row1_filled and BRAM1_row2_filled and BRAM2_row1_filled);
                else
                    axis_tready <= '0';
                end if;
            when "100" =>
				if(BRAM1_row1_filled = '1' and BRAM1_row2_filled = '1' and BRAM2_row1_filled = '1' and BRAM2_row2_filled = '1')then
                    axis_tready <= ready or not (BRAM1_row1_filled and BRAM1_row2_filled and BRAM2_row1_filled and BRAM2_row2_filled);
                else
                    axis_tready <= '0';
                end if;
            when others =>
                axis_tready <= '0';
        end case;
    end process;
    s_axis_tready <= axis_tready;

    -------------------------------------------------------------------------------------------------------------------------
    --------------------------------- Pixel assigment logic + SKID ----------------------------------------------------------
    -------------------------------------------------------------------------------------------------------------------------
    process (clk) is 
    begin
        if (rising_edge(clk)) then
            if (reset = '1') then
                pixel <= (others => '0');
                pixel_valid <= '0';
                pixel_last <= '0';
                pixel_skid_buff <= (others => '0');
                pixel_skid_buff_valid <= '0';
                pixel_skid_buff_last <= '0';
                pixel_skid_buff_full <= '0';
            else
                if (ready = '0') then
                    if (pixel_skid_buff_full = '0') then
                        pixel_skid_buff <= input_data;
                        pixel_skid_buff_valid <= s_axis_tvalid;
                        pixel_skid_buff_last <= s_axis_tlast;
                        pixel_skid_buff_full <= '1';
                    end if;
                else
                    if (pixel_skid_buff_full = '1') then
                        pixel <= pixel_skid_buff;
                        pixel_valid <= pixel_skid_buff_valid;
                        pixel_last <= pixel_skid_buff_last;
                        pixel_skid_buff_full <= '0'; 
                    else
                        pixel <= input_data;
                        pixel_valid <= s_axis_tvalid;
                        pixel_last <= s_axis_tlast;
                    end if;
                end if;
            end if;
        
        end if;
    end process;
    
    bypass_pixel <= pixel;
    bypass_pixel_valid <= pixel_valid;
    bypass_pixel_last <= pixel_last;

end Behavioral;
