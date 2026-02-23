library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

package axi_registers_pkg is
    type t_coeff_array is array (0 to 80) of std_logic_vector(15 downto 0);
    type t_w_array is array (0 to 80) of std_logic_vector(7 downto 0);
    constant REG_COEFF_0  : std_logic_vector(6 downto 0) := "0010000"; -- 0x10
    constant REG_COEFF_1  : std_logic_vector(6 downto 0) := "0010001"; -- 0x11
    constant REG_COEFF_2  : std_logic_vector(6 downto 0) := "0010010"; -- 0x12
    constant REG_COEFF_3  : std_logic_vector(6 downto 0) := "0010011"; -- 0x13
    constant REG_COEFF_4  : std_logic_vector(6 downto 0) := "0010100"; -- 0x14
    constant REG_COEFF_5  : std_logic_vector(6 downto 0) := "0010101"; -- 0x15
    constant REG_COEFF_6  : std_logic_vector(6 downto 0) := "0010110"; -- 0x16
    constant REG_COEFF_7  : std_logic_vector(6 downto 0) := "0010111"; -- 0x17
    constant REG_COEFF_8  : std_logic_vector(6 downto 0) := "0011000"; -- 0x18
    constant REG_COEFF_9  : std_logic_vector(6 downto 0) := "0011001"; -- 0x19
    constant REG_COEFF_10 : std_logic_vector(6 downto 0) := "0011010"; -- 0x1A
    constant REG_COEFF_11 : std_logic_vector(6 downto 0) := "0011011"; -- 0x1B
    constant REG_COEFF_12 : std_logic_vector(6 downto 0) := "0011100"; -- 0x1C
    constant REG_COEFF_13 : std_logic_vector(6 downto 0) := "0011101"; -- 0x1D
    constant REG_COEFF_14 : std_logic_vector(6 downto 0) := "0011110"; -- 0x1E
    constant REG_COEFF_15 : std_logic_vector(6 downto 0) := "0011111"; -- 0x1F
    constant REG_COEFF_16 : std_logic_vector(6 downto 0) := "0100000"; -- 0x20
    constant REG_COEFF_17 : std_logic_vector(6 downto 0) := "0100001"; -- 0x21
    constant REG_COEFF_18 : std_logic_vector(6 downto 0) := "0100010"; -- 0x22
    constant REG_COEFF_19 : std_logic_vector(6 downto 0) := "0100011"; -- 0x23
    constant REG_COEFF_20 : std_logic_vector(6 downto 0) := "0100100"; -- 0x24
    constant REG_COEFF_21 : std_logic_vector(6 downto 0) := "0100101"; -- 0x25
    constant REG_COEFF_22 : std_logic_vector(6 downto 0) := "0100110"; -- 0x26
    constant REG_COEFF_23 : std_logic_vector(6 downto 0) := "0100111"; -- 0x27
    constant REG_COEFF_24 : std_logic_vector(6 downto 0) := "0101000"; -- 0x28
    constant REG_COEFF_25 : std_logic_vector(6 downto 0) := "0101001"; -- 0x29
    constant REG_COEFF_26 : std_logic_vector(6 downto 0) := "0101010"; -- 0x2A
    constant REG_COEFF_27 : std_logic_vector(6 downto 0) := "0101011"; -- 0x2B
    constant REG_COEFF_28 : std_logic_vector(6 downto 0) := "0101100"; -- 0x2C
    constant REG_COEFF_29 : std_logic_vector(6 downto 0) := "0101101"; -- 0x2D
    constant REG_COEFF_30 : std_logic_vector(6 downto 0) := "0101110"; -- 0x2E
    constant REG_COEFF_31 : std_logic_vector(6 downto 0) := "0101111"; -- 0x2F
    constant REG_COEFF_32 : std_logic_vector(6 downto 0) := "0110000"; -- 0x30
    constant REG_COEFF_33 : std_logic_vector(6 downto 0) := "0110001"; -- 0x31
    constant REG_COEFF_34 : std_logic_vector(6 downto 0) := "0110010"; -- 0x32
    constant REG_COEFF_35 : std_logic_vector(6 downto 0) := "0110011"; -- 0x33
    constant REG_COEFF_36 : std_logic_vector(6 downto 0) := "0110100"; -- 0x34
    constant REG_COEFF_37 : std_logic_vector(6 downto 0) := "0110101"; -- 0x35
    constant REG_COEFF_38 : std_logic_vector(6 downto 0) := "0110110"; -- 0x36
    constant REG_COEFF_39 : std_logic_vector(6 downto 0) := "0110111"; -- 0x37
    constant REG_COEFF_40 : std_logic_vector(6 downto 0) := "0111000"; -- 0x38
    constant REG_COEFF_41 : std_logic_vector(6 downto 0) := "0111001"; -- 0x39
    constant REG_COEFF_42 : std_logic_vector(6 downto 0) := "0111010"; -- 0x3A
    constant REG_COEFF_43 : std_logic_vector(6 downto 0) := "0111011"; -- 0x3B
    constant REG_COEFF_44 : std_logic_vector(6 downto 0) := "0111100"; -- 0x3C
    constant REG_COEFF_45 : std_logic_vector(6 downto 0) := "0111101"; -- 0x3D
    constant REG_COEFF_46 : std_logic_vector(6 downto 0) := "0111110"; -- 0x3E
    constant REG_COEFF_47 : std_logic_vector(6 downto 0) := "0111111"; -- 0x3F
    constant REG_COEFF_48 : std_logic_vector(6 downto 0) := "1000000"; -- 0x40
    constant REG_COEFF_49 : std_logic_vector(6 downto 0) := "1000001"; -- 0x41
    constant REG_COEFF_50 : std_logic_vector(6 downto 0) := "1000010"; -- 0x42
    constant REG_COEFF_51 : std_logic_vector(6 downto 0) := "1000011"; -- 0x43
    constant REG_COEFF_52 : std_logic_vector(6 downto 0) := "1000100"; -- 0x44
    constant REG_COEFF_53 : std_logic_vector(6 downto 0) := "1000101"; -- 0x45
    constant REG_COEFF_54 : std_logic_vector(6 downto 0) := "1000110"; -- 0x46
    constant REG_COEFF_55 : std_logic_vector(6 downto 0) := "1000111"; -- 0x47
    constant REG_COEFF_56 : std_logic_vector(6 downto 0) := "1001000"; -- 0x48
    constant REG_COEFF_57 : std_logic_vector(6 downto 0) := "1001001"; -- 0x49
    constant REG_COEFF_58 : std_logic_vector(6 downto 0) := "1001010"; -- 0x4A
    constant REG_COEFF_59 : std_logic_vector(6 downto 0) := "1001011"; -- 0x4B
    constant REG_COEFF_60 : std_logic_vector(6 downto 0) := "1001100"; -- 0x4C
    constant REG_COEFF_61 : std_logic_vector(6 downto 0) := "1001101"; -- 0x4D
    constant REG_COEFF_62 : std_logic_vector(6 downto 0) := "1001110"; -- 0x4E
    constant REG_COEFF_63 : std_logic_vector(6 downto 0) := "1001111"; -- 0x4F
    constant REG_COEFF_64 : std_logic_vector(6 downto 0) := "1010000"; -- 0x50
    constant REG_COEFF_65 : std_logic_vector(6 downto 0) := "1010001"; -- 0x51
    constant REG_COEFF_66 : std_logic_vector(6 downto 0) := "1010010"; -- 0x52
    constant REG_COEFF_67 : std_logic_vector(6 downto 0) := "1010011"; -- 0x53
    constant REG_COEFF_68 : std_logic_vector(6 downto 0) := "1010100"; -- 0x54
    constant REG_COEFF_69 : std_logic_vector(6 downto 0) := "1010101"; -- 0x55
    constant REG_COEFF_70 : std_logic_vector(6 downto 0) := "1010110"; -- 0x56
    constant REG_COEFF_71 : std_logic_vector(6 downto 0) := "1010111"; -- 0x57
    constant REG_COEFF_72 : std_logic_vector(6 downto 0) := "1011000"; -- 0x58
    constant REG_COEFF_73 : std_logic_vector(6 downto 0) := "1011001"; -- 0x59
    constant REG_COEFF_74 : std_logic_vector(6 downto 0) := "1011010"; -- 0x5A
    constant REG_COEFF_75 : std_logic_vector(6 downto 0) := "1011011"; -- 0x5B
    constant REG_COEFF_76 : std_logic_vector(6 downto 0) := "1011100"; -- 0x5C
    constant REG_COEFF_77 : std_logic_vector(6 downto 0) := "1011101"; -- 0x5D
    constant REG_COEFF_78 : std_logic_vector(6 downto 0) := "1011110"; -- 0x5E
    constant REG_COEFF_79 : std_logic_vector(6 downto 0) := "1011111"; -- 0x5F
    constant REG_COEFF_80 : std_logic_vector(6 downto 0) := "1100000"; -- 0x60
end package axi_registers_pkg;



