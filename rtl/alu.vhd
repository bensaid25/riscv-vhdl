library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;

entity alu is
  port (
    a, b   : in  std_logic_vector(31 downto 0);
    op     : in  alu_op_t;
    result : out std_logic_vector(31 downto 0);
    zero   : out std_logic
  );
end entity;

architecture rtl of alu is
begin
  process(all)
    variable ua, ub : unsigned(31 downto 0);
    variable sa, sb : signed(31 downto 0);
    variable shamt  : natural range 0 to 31;
    variable r      : std_logic_vector(31 downto 0);
  begin
    ua := unsigned(a);  ub := unsigned(b);
    sa := signed(a);    sb := signed(b);
    shamt := to_integer(ub(4 downto 0));
    r := (others => '0');

    case op is
      when ALU_ADD  => r := std_logic_vector(ua + ub);
      when ALU_SUB  => r := std_logic_vector(ua - ub);
      when ALU_AND  => r := a and b;
      when ALU_OR   => r := a or b;
      when ALU_XOR  => r := a xor b;
      when ALU_SLL  => r := std_logic_vector(shift_left(ua, shamt));
      when ALU_SRL  => r := std_logic_vector(shift_right(ua, shamt));
      when ALU_SRA  => r := std_logic_vector(shift_right(sa, shamt));
      when ALU_SLT  => if sa < sb then r(0) := '1'; end if;
      when ALU_SLTU => if ua < ub then r(0) := '1'; end if;
    end case;

    result <= r;
    if r = x"00000000" then zero <= '1'; else zero <= '0'; end if;
  end process;
end architecture;