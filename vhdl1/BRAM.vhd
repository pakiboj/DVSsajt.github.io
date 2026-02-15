----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 02/10/2026 01:08:42 PM
-- Design Name: 
-- Module Name: BRAM - Behavioral
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

entity BRAM is
    Generic (
        C_MAX_IMG_WIDTH : integer := 512;
        C_MAX_RADIOUS : integer := 4;
        C_RADIUS : integer := 1;
        C_IMG_SIZE : integer := 128
    );
    Port ( 
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        enable : in std_logic;
        data_in : in STD_LOGIC_VECTOR (7 downto 0);
        data_out_1 : out STD_LOGIC_VECTOR (7 downto 0);
        data_out_2 : out STD_LOGIC_VECTOR (7 downto 0)
    );
end BRAM;

architecture Behavioral of BRAM is
    constant BRAM_WIDTH  : integer := 8 * C_RADIUS * 2; 
    constant BRAM_DEPTH  : integer := C_IMG_SIZE; 
    type ram_t is array (0 to BRAM_DEPTH-1) of std_logic_vector(BRAM_WIDTH-1 downto 0);
    signal ram : ram_t;
    
    signal counter : integer := 0;
    
begin
    
    BRAM_LOGIC: process(clk) 
        variable ram_temp : std_logic_vector(BRAM_WIDTH-1 downto 0);
    begin
        if rising_edge(clk) then
            if reset = '1' then
            --init posle restarta
                ram <= (others => (others => '0'));
            else
                if enable = '1' then
                    for i in BRAM_DEPTH-1 downto 1 loop
                        ram(i) <= ram(i-1);
                    end loop;
                    --dodaj data_in na ram(0)
                    ram_temp := ram(0);
                    ram_temp(7 downto 0) := data_in;
                    ram(0) <= ram_temp ;
                    ram(0)(15 downto 8) <= ram(BRAM_DEPTH-1)(7 downto 0);
                end if;
            end if;
        end if;
    end process;
    
    --Output
    data_out_1 <= ram(BRAM_DEPTH-1)(7 downto 0);
    data_out_2 <= ram(BRAM_DEPTH-1)(15 downto 8);
    
end Behavioral;