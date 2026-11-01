library ieee;
use ieee.std_logic_1164.all;

entity branch_unit is
  port (
    branch      : in  std_logic;
    funct3      : in  std_logic_vector(2 downto 0);
    zero        : in  std_logic;   -- ALU result = 0 (after SUB)
    lt          : in  std_logic;   -- ALU result bit 0 (after SLT / SLTU)
    take_branch : out std_logic
  );
end entity;

architecture rtl of branch_unit is
begin
  process(all)
  begin
    take_branch <= '0';
    if branch = '1' then
      case funct3 is
        when "000"  => take_branch <= zero;       -- BEQ
        when "001"  => take_branch <= not zero;   -- BNE
        when "100"  => take_branch <= lt;         -- BLT
        when "101"  => take_branch <= not lt;     -- BGE
        when "110"  => take_branch <= lt;         -- BLTU
        when "111"  => take_branch <= not lt;     -- BGEU
        when others => null;
      end case;
    end if;
  end process;
end architecture;
