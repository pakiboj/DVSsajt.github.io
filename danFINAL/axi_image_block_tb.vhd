----------------------------------------------------------------------------------
-- Testbench for axi_image_block
-- All images are 128x128.
-- Pixel pattern : every row is  0, 1, 2, ... , 127  (col index, 8-bit)
--
-- Internal signal:
--   row_last_pixel : pulses HIGH for one clock when the last pixel of a row
--                    (value = 127) is accepted on the AXI-Stream handshake
--
-- Test order:
--   bord = "00"  ->  r=001, r=010, r=011, r=100
--   bord = "10"  ->  r=001, r=010, r=011, r=100
--   bord = "11"  ->  r=001, r=010, r=011, r=100   (border_value = 0xAA)
--   Backpressure    (bord=11, all radius values)
--   Sequential      (bord=11, r=001, 3 images)
----------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.axi_registers_pkg.all;

entity axi_image_block_tb is
end axi_image_block_tb;

architecture Behavioral of axi_image_block_tb is

    ----------------------------------------------------------------------------
    -- Component declaration
    ----------------------------------------------------------------------------
    component axi_image_block is
        Generic (
            C_MAX_IMG_WIDTH : integer := 512;
            C_MAX_RADIOUS   : integer := 4;
            C_RADIUS        : integer := 1;
            C_IMG_SIZE      : integer := 9
        );
        port (
            clk                : in  std_logic;
            reset              : in  std_logic;
            border_value       : in  std_logic_vector(7 downto 0);
            bord               : in  std_logic_vector(1 downto 0);
            radius             : in  std_logic_vector(2 downto 0);
            img_width          : in  std_logic_vector(15 downto 0);
            img_height         : in  std_logic_vector(15 downto 0);
            ready              : in  std_logic;
            s_axis_tdata       : in  std_logic_vector(7 downto 0);
            s_axis_tlast       : in  std_logic;
            s_axis_tvalid      : in  std_logic;
            s_axis_tready      : out std_logic;
            bypass_pixel       : out std_logic_vector(7 downto 0);
            bypass_pixel_valid : out std_logic;
            bypass_pixel_last  : out std_logic;
            w_k                : out t_w_array;
            w_k_valid          : out std_logic;
            w_k_last           : out std_logic
        );
    end component;

    ----------------------------------------------------------------------------
    -- Constants
    ----------------------------------------------------------------------------
    constant CLK_PERIOD  : time    := 10 ns;
    constant IMG_W       : integer := 9;           -- columns : 0 .. 127
    constant IMG_H       : integer := 9;           -- rows
    constant BORDER_FILL : std_logic_vector(7 downto 0) := x"AA";

    ----------------------------------------------------------------------------
    -- DUT signals
    ----------------------------------------------------------------------------
    signal clk                : std_logic := '0';
    signal reset              : std_logic := '1';
    signal border_value       : std_logic_vector(7 downto 0) := BORDER_FILL;
    signal bord               : std_logic_vector(1 downto 0) := "00";
    signal radius             : std_logic_vector(2 downto 0) := "001";
    signal img_width          : std_logic_vector(15 downto 0) :=
                                    std_logic_vector(to_unsigned(IMG_W, 16));
    signal img_height         : std_logic_vector(15 downto 0) :=
                                    std_logic_vector(to_unsigned(IMG_H, 16));
    signal ready              : std_logic := '1';
    signal s_axis_tdata       : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_tlast       : std_logic := '0';
    signal s_axis_tvalid      : std_logic := '0';
    signal s_axis_tready      : std_logic;
    signal bypass_pixel       : std_logic_vector(7 downto 0);
    signal bypass_pixel_valid : std_logic;
    signal bypass_pixel_last  : std_logic;
    signal w_k                : t_w_array;
    signal w_k_valid          : std_logic;
    signal w_k_last           : std_logic;

    ----------------------------------------------------------------------------
    -- Internal testbench signals
    ----------------------------------------------------------------------------

    -- Pulses HIGH for exactly one clock cycle when the last pixel of a row
    -- (column index 127, value = 127) is accepted on the AXI-Stream interface.
    -- "Accepted" means: s_axis_tvalid = '1' AND s_axis_tready = '1'
    --                   AND s_axis_tdata = x"7F"  (127)
    signal row_last_pixel : std_logic := '0';

    signal test_done : boolean := false;

begin

    ----------------------------------------------------------------------------
    -- DUT instantiation
    ----------------------------------------------------------------------------
    DUT : axi_image_block
        generic map (
            C_MAX_IMG_WIDTH => 512,
            C_MAX_RADIOUS   => 4,
            C_RADIUS        => 1,
            C_IMG_SIZE      => 9
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
            s_axis_tdata       => s_axis_tdata,
            s_axis_tlast       => s_axis_tlast,
            s_axis_tvalid      => s_axis_tvalid,
            s_axis_tready      => s_axis_tready,
            bypass_pixel       => bypass_pixel,
            bypass_pixel_valid => bypass_pixel_valid,
            bypass_pixel_last  => bypass_pixel_last,
            w_k                => w_k,
            w_k_valid          => w_k_valid,
            w_k_last           => w_k_last
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
    -- row_last_pixel generation
    -- Combinatorial: high whenever a handshake carries the value 127 (0x7F).
    -- Because the pattern resets to 0 every row, value 127 only ever appears
    -- as the last column of a row.
    ----------------------------------------------------------------------------
    row_last_pixel <= '1' when (s_axis_tvalid  = '1' and
                                s_axis_tready  = '1' and
                                s_axis_tdata   = std_logic_vector(to_unsigned(IMG_W - 1, 8)))
                          else '0';

    ----------------------------------------------------------------------------
    -- Stimulus process
    ----------------------------------------------------------------------------
    stim_proc : process

        -- col_val drives s_axis_tdata; declared as variable inside process
        variable col_val : unsigned(7 downto 0);

        procedure do_reset is
        begin
            reset <= '1';
            wait for 10 * CLK_PERIOD;
            reset <= '0';
            wait for 5 * CLK_PERIOD;
        end procedure;

        procedure configure (
            constant rad  : std_logic_vector(2 downto 0);
            constant bd   : std_logic_vector(1 downto 0);
            constant bval : std_logic_vector(7 downto 0)
        ) is
        begin
            radius       <= rad;
            bord         <= bd;
            border_value <= bval;
            img_width    <= std_logic_vector(to_unsigned(IMG_W, 16));
            img_height   <= std_logic_vector(to_unsigned(IMG_H, 16));
            wait for 2 * CLK_PERIOD;
        end procedure;
		
		procedure wait_clocks (constant cycles : integer) is
        begin
            s_axis_tvalid <= '0';
            for i in 1 to cycles loop
                wait until rising_edge(clk);
            end loop;
        end procedure;

        -- Send 128x128 image; each row counts 0, 1, 2, ... , 127 then stops
        procedure send_image (constant test_name : string) is
        begin
            report "================================================";
            report "START: " & test_name;
            report "  radius=" & integer'image(to_integer(unsigned(radius))) &
                   "  bord="   & std_logic'image(bord(1)) & std_logic'image(bord(0)) &
                   "  border_value=" & integer'image(to_integer(unsigned(border_value)));
            report "================================================";

            for r in 0 to IMG_H - 1 loop
                col_val := (others => '0');              -- row starts at 0
                for c in 0 to IMG_W - 1 loop             -- c goes 0 .. 127
                    s_axis_tdata  <= std_logic_vector(col_val);
                    s_axis_tvalid <= '1';

                    -- tlast only on the very last pixel of the whole image
                    if (r = IMG_H - 1) and (c = IMG_W - 1) then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    wait until rising_edge(clk);
                    while s_axis_tready = '0' loop
                        wait until rising_edge(clk);
                    end loop;

                    -- col_val reaches 127 on the last column, then we move
                    -- to the next row and reset it to 0 via the outer loop
                    col_val := col_val + 1;
                end loop;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
            wait for 200 * CLK_PERIOD;
            report "END: " & test_name;
        end procedure;
        
        -- Send IMG_H x IMG_W image with wraparound pixel values:
        -- 0,1,2,...254,255,0,1,2...
        procedure send_image_seq (constant test_name : string) is
            variable pix_val : unsigned(7 downto 0);
        begin
            report "================================================";
            report "START: " & test_name;
            report "  radius=" & integer'image(to_integer(unsigned(radius))) &
                   "  bord="   & std_logic'image(bord(1)) & std_logic'image(bord(0)) &
                   "  border_value=" & integer'image(to_integer(unsigned(border_value)));
            report "================================================";
        
            pix_val := (others => '0');  -- start from 0
        
            for r in 0 to IMG_H - 1 loop
                for c in 0 to IMG_W - 1 loop
        
                    s_axis_tdata  <= std_logic_vector(pix_val);
                    s_axis_tvalid <= '1';
        
                    -- tlast only on final pixel
                    if (r = IMG_H - 1) and (c = IMG_W - 1) then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;
        
                    wait until rising_edge(clk);
                    while s_axis_tready = '0' loop
                        wait until rising_edge(clk);
                    end loop;
        
                    pix_val := pix_val + 1;  -- automatic wraparound
        
                end loop;
            end loop;
        
            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
        
            wait for 200 * CLK_PERIOD;
            report "END: " & test_name;
        end procedure;
        

        procedure send_image_bp (constant test_name : string) is
            variable pix_cnt : integer := 0;
        begin
            report "================================================";
            report "START (BP): " & test_name;
            report "  radius=" & integer'image(to_integer(unsigned(radius))) &
                   "  bord="   & std_logic'image(bord(1)) & std_logic'image(bord(0)) &
                   "  border_value=" & integer'image(to_integer(unsigned(border_value)));
            report "================================================";

            pix_cnt := 0;
            for r in 0 to IMG_H - 1 loop
                col_val := (others => '0');
                for c in 0 to IMG_W - 1 loop
                    wait until rising_edge(clk);
                    while s_axis_tready = '0' loop
                        wait until rising_edge(clk);
                    end loop;

                    s_axis_tdata  <= std_logic_vector(col_val);
                    s_axis_tvalid <= '1';

                    if (r = IMG_H - 1) and (c = IMG_W - 1) then
                        s_axis_tlast <= '1';
                    else
                        s_axis_tlast <= '0';
                    end if;

                    col_val  := col_val + 1;
                    pix_cnt  := pix_cnt + 1;

                    if pix_cnt mod 4 = 0 then
                        wait until rising_edge(clk);
                        ready <= '0';
                        wait for 3 * CLK_PERIOD;
                        ready <= '1';
                    else
                        wait until rising_edge(clk);
                    end if;
                end loop;
            end loop;

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
            ready         <= '1';
            wait for 200 * CLK_PERIOD;
            report "END (BP): " & test_name;
        end procedure;

    begin
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';
        ready         <= '1';
        do_reset;

        ----------------------------------------------------------------
        -- bord = "11"  ->  r=001, r=010, r=011, r=100
        ----------------------------------------------------------------
        report "################################################";
        report "BORD = 11  (zero padding)";
        report "################################################";
        
        -- wait_clocks(6);
        do_reset; configure("001", "11", x"ff");  send_image_seq("bord=11  r=001  3x3");
        do_reset; configure("010", "11", x"ff");  send_image_seq("bord=11  r=010  5x5");
        do_reset; configure("011", "11", x"ff");  send_image_seq("bord=11  r=011  7x7");
        do_reset; configure("100", "11", x"ff");  send_image_seq("bord=11  r=100  9x9");

        ----------------------------------------------------------------
        -- bord = "00"  ->  r=001, r=010, r=011, r=100
        ----------------------------------------------------------------
        report "################################################";
        report "BORD = 00  (fixed value = 0xAA)";
        report "################################################";

        do_reset; configure("001", "00", BORDER_FILL); send_image_seq("bord=00  r=001  3x3");
        do_reset; configure("010", "00", BORDER_FILL); send_image_seq("bord=00  r=010  5x5");
        do_reset; configure("011", "00", BORDER_FILL); send_image_seq("bord=00  r=011  7x7");
        do_reset; configure("100", "00", BORDER_FILL); send_image_seq("bord=00  r=100  9x9");
        
        ----------------------------------------------------------------
        -- bord = "10"  ->  r=001, r=010, r=011, r=100
        
        ----------------------------------------------------------------
        report "################################################";
        report "BORD = 10  (nearest neighbour)";
        report "################################################";

        do_reset; configure("001", "10", x"00"); send_image_seq("bord=10  r=001  3x3");
        do_reset; configure("010", "10", x"00"); send_image_seq("bord=10  r=010  5x5");
        do_reset; configure("011", "10", x"00"); send_image_seq("bord=10  r=011  7x7");
        do_reset; configure("100", "10", x"00"); send_image_seq("bord=10  r=100  9x9");

        ----------------------------------------------------------------
        -- Backpressure  (bord=11, all radius values)
        ----------------------------------------------------------------
        report "################################################";
        report "BACKPRESSURE  (bord=11, fixed=0xAA)";
        report "################################################";

        --do_reset; configure("001", "11", BORDER_FILL); send_image_bp("bord=11  r=001  BP");
        --do_reset; configure("010", "11", BORDER_FILL); send_image_bp("bord=11  r=010  BP");
        --do_reset; configure("011", "11", BORDER_FILL); send_image_bp("bord=11  r=011  BP");
        --do_reset; configure("100", "11", BORDER_FILL); send_image_bp("bord=11  r=100  BP");

        ----------------------------------------------------------------
        -- Sequential images  (bord=11, r=001, no reset between images)
        ----------------------------------------------------------------
        report "################################################";
        report "SEQUENTIAL IMAGES  (bord=11, r=001)";
        report "################################################";

        --do_reset;
        --configure("001", "11", BORDER_FILL);
        --send_image("bord=11  r=001  Seq 1/3");
        --wait for 20 * CLK_PERIOD;
        --send_image("bord=11  r=001  Seq 2/3");
        --wait for 20 * CLK_PERIOD;
        --send_image("bord=11  r=001  Seq 3/3");

        ----------------------------------------------------------------
        report "################################################";
        report "ALL TESTS COMPLETED";
        report "################################################";
        test_done <= true;
        wait;

    end process;

    ----------------------------------------------------------------------------
    -- Monitor process
    ----------------------------------------------------------------------------
    monitor_proc : process
        variable win_cnt : integer := 0;
        variable img_cnt : integer := 0;
    begin
        loop
            wait until rising_edge(clk);
            exit when test_done;

            if w_k_valid = '1' then
                win_cnt := win_cnt + 1;
                if (win_cnt = 1) or (win_cnt mod 500 = 0) or (w_k_last = '1') then
                    report "  WIN#"    & integer'image(win_cnt)  &
                           "  last="   & std_logic'image(w_k_last) &
                           "  w_k[0]=" & integer'image(to_integer(unsigned(w_k(0)))) &
                           "  w_k[1]=" & integer'image(to_integer(unsigned(w_k(1)))) &
                           "  w_k[2]=" & integer'image(to_integer(unsigned(w_k(2))));
                end if;
                if w_k_last = '1' then
                    img_cnt := img_cnt + 1;
                    report "  >>> IMAGE #" & integer'image(img_cnt) &
                           " done - total windows = " & integer'image(win_cnt);
                    win_cnt := 0;
                end if;
            end if;
        end loop;
        wait;
    end process;

    ----------------------------------------------------------------------------
    -- Checker process
    ----------------------------------------------------------------------------
    checker_proc : process
    begin
        loop
            wait until rising_edge(clk);
            exit when test_done;

            if w_k_valid = '1' and ready = '0' then
                report "PROTOCOL ERROR: w_k_valid high while ready low"
                    severity error;
            end if;
        end loop;
        wait;
    end process;

end Behavioral;