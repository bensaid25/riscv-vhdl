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
  function bit_reverse(x : std_logic_vector) return std_logic_vector is
    variable r : std_logic_vector(x'range);
  begin
    for i in x'range loop
      r(i) := x(x'left + x'right - i);
    end loop;
    return r;
  end function;
begin
  process(all)
    variable ua, ub, bx    : unsigned(31 downto 0);
    variable cin           : std_logic;
    variable a34, b34, s34 : unsigned(33 downto 0);
    variable sum           : std_logic_vector(31 downto 0);
    variable lt, ltu       : std_logic;
    variable shamt         : natural range 0 to 31;
    variable fill          : std_logic;
    variable sh_in         : unsigned(31 downto 0);
    variable ext           : unsigned(32 downto 0);
    variable sh_s          : signed(32 downto 0);
    variable shifted       : std_logic_vector(31 downto 0);
    variable r             : std_logic_vector(31 downto 0);
  begin
    ua := unsigned(a);  ub := unsigned(b);

    -- one adder/subtractor: a + b, or a + not b + 1 (carry-in rides in the extra low bit)
    if op = ALU_SUB or op = ALU_SLT or op = ALU_SLTU then
      bx := not ub;  cin := '1';
    else
      bx := ub;      cin := '0';
    end if;
    a34 := '0' & ua & '1';
    b34 := '0' & bx & cin;
    s34 := a34 + b34;
    sum := std_logic_vector(s34(32 downto 1));
    ltu := not s34(33);                                  -- borrow: a < b unsigned
    if a(31) /= b(31) then lt := a(31); else lt := sum(31); end if;   -- a < b signed

    -- one right shifter; left shift = reverse, shift right, reverse
    shamt := to_integer(ub(4 downto 0));
    if op = ALU_SLL then sh_in := unsigned(bit_reverse(a)); else sh_in := ua; end if;
    if op = ALU_SRA then fill := a(31); else fill := '0'; end if;
    ext     := fill & sh_in;
    sh_s    := signed(ext);
    sh_s    := shift_right(sh_s, shamt);
    shifted := std_logic_vector(sh_s(31 downto 0));

    r := (others => '0');
    case op is
      when ALU_ADD | ALU_SUB => r := sum;
      when ALU_AND   => r := a and b;
      when ALU_OR    => r := a or b;
      when ALU_XOR   => r := a xor b;
      when ALU_SLL   => r := bit_reverse(shifted);
      when ALU_SRL | ALU_SRA => r := shifted;
      when ALU_SLT   => r(0) := lt;
      when ALU_SLTU  => r(0) := ltu;
      when ALU_COPYB => r := b;
    end case;

    result <= r;
    if r = x"00000000" then zero <= '1'; else zero <= '0'; end if;
  end process;
end architecture;
