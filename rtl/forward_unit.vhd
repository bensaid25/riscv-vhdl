library ieee;
use ieee.std_logic_1164.all;

entity forward_unit is
  port (
    rs1             : in  std_logic_vector(4 downto 0);   -- sources of the instruction in EX
    rs2             : in  std_logic_vector(4 downto 0);
    exmem_rd        : in  std_logic_vector(4 downto 0);   -- one instruction ahead (in MEM)
    exmem_reg_write : in  std_logic;
    memwb_rd        : in  std_logic_vector(4 downto 0);   -- two instructions ahead (in WB)
    memwb_reg_write : in  std_logic;
    fwd_a           : out std_logic_vector(1 downto 0);   -- 00 register file, 01 EX/MEM, 10 MEM/WB
    fwd_b           : out std_logic_vector(1 downto 0)
  );
end entity;

architecture rtl of forward_unit is
  constant ZERO : std_logic_vector(4 downto 0) := (others => '0');
begin
  fwd_a <= "01" when exmem_reg_write = '1' and exmem_rd /= ZERO and exmem_rd = rs1 else
           "10" when memwb_reg_write = '1' and memwb_rd /= ZERO and memwb_rd = rs1 else
           "00";
  fwd_b <= "01" when exmem_reg_write = '1' and exmem_rd /= ZERO and exmem_rd = rs2 else
           "10" when memwb_reg_write = '1' and memwb_rd /= ZERO and memwb_rd = rs2 else
           "00";
end architecture;
