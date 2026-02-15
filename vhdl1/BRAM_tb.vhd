library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity BRAM_tb is
end entity;

architecture sim of BRAM_tb is

    -- Generic values
    constant C_MAX_IMG_WIDTH : integer := 512;
    constant C_MAX_RADIOUS   : integer := 1;  -- adjust if needed
    constant C_RADIUS        : integer := 1;
    constant C_IMG_SIZE      : integer := 128;

    -- Signals
    signal clk      : std_logic := '0';
    signal reset    : std_logic := '0';
    signal enable : std_logic := '0';
    signal data_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal data_out_1 : std_logic_vector(7 downto 0);
    signal data_out_2 : std_logic_vector(7 downto 0);

    constant CLK_PERIOD : time := 10 ns;

begin

    --------------------------------------------------------------------
    -- DUT instance
    --------------------------------------------------------------------
    uut : entity work.BRAM
        generic map (
            C_MAX_IMG_WIDTH => C_MAX_IMG_WIDTH,
            C_MAX_RADIOUS   => C_MAX_RADIOUS,
            C_RADIUS        => C_RADIUS,
            C_IMG_SIZE      => C_IMG_SIZE
        )
        port map (
            clk      => clk,
            reset    => reset,
            enable  => enable,
            data_in  => data_in,
            data_out_1 => data_out_1,
            data_out_2 => data_out_2
        );

    --------------------------------------------------------------------
    -- Clock generation
    --------------------------------------------------------------------
    clk_process : process
    begin
        while true loop
            clk <= '0';
            wait for CLK_PERIOD/2;
            clk <= '1';
            wait for CLK_PERIOD/2;
        end loop;
    end process;

    --------------------------------------------------------------------
    -- Stimulus process
    --------------------------------------------------------------------
    stim_proc : process
    begin
        -- optional reset pulse
        reset <= '1';
        wait for 2 * CLK_PERIOD;
        enable <= '1';
        reset <= '0';

        -- Feed data_in for 130 cycles
        for i in 0 to 400 loop
            data_in <= std_logic_vector(to_unsigned(i, 8));
            wait for CLK_PERIOD;
        end loop;

        -- Hold a value to see final effect
        data_in <= x"AA";
        wait for 20 * CLK_PERIOD;

    end process;

end architecture;
