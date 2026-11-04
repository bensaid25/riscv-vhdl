library ieee;
use ieee.std_logic_1164.all;
use work.alu_pkg.all;

entity alu_tb is end entity;

architecture sim of alu_tb is
  signal a, b, result : std_logic_vector(31 downto 0) := (others => '0');
  signal op   : alu_op_t := ALU_ADD;
  signal zero : std_logic;
begin
  dut: entity work.alu
    port map (a => a, b => b, op => op, result => result, zero => zero);

  stim: process
    procedure check(
      constant ia, ib  : in std_logic_vector(31 downto 0);
      constant iop     : in alu_op_t;
      constant expect  : in std_logic_vector(31 downto 0)) is
    begin
      a <= ia; b <= ib; op <= iop;
      wait for 1 ns;
      assert result = expect
        report alu_op_t'image(iop) & ": expected " & to_hstring(expect)
               & " got " & to_hstring(result)
        severity error;
      assert (zero = '1') = (expect = x"00000000")
        report alu_op_t'image(iop) & ": wrong zero flag" severity error;
    end procedure;
  begin
    check(x"12345678", x"9ABCDEF0", ALU_COPYB, x"9ABCDEF0");
    check(x"12345678", x"00000000", ALU_COPYB, x"00000000");
    check(x"00000001", x"00000001", ALU_ADD,  x"00000002");
    check(x"FFFFFFFF", x"00000001", ALU_ADD,  x"00000000");  -- wraparound
    check(x"00000000", x"00000001", ALU_SUB,  x"FFFFFFFF");
    check(x"F0F0F0F0", x"0FF00FF0", ALU_AND,  x"00F000F0");
    check(x"F0F0F0F0", x"0FF00FF0", ALU_OR,   x"FFF0FFF0");
    check(x"F0F0F0F0", x"0FF00FF0", ALU_XOR,  x"FF00FF00");
    check(x"00000001", x"0000001F", ALU_SLL,  x"80000000");
    check(x"80000000", x"0000001F", ALU_SRL,  x"00000001");
    check(x"80000000", x"00000004", ALU_SRA,  x"F8000000");  -- sign kept
    check(x"FFFFFFFF", x"00000001", ALU_SLT,  x"00000001");  -- -1 < 1
    check(x"FFFFFFFF", x"00000001", ALU_SLTU, x"00000000");  -- 0xFFFFFFFF > 1

    -- compares: equal operands, signed/unsigned disagreement, extremes
    check(x"00000005", x"00000005", ALU_SLT,  x"00000000");
    check(x"00000005", x"00000005", ALU_SLTU, x"00000000");
    check(x"80000000", x"00000001", ALU_SLT,  x"00000001");  -- -2^31 < 1
    check(x"00000001", x"80000000", ALU_SLT,  x"00000000");
    check(x"7FFFFFFF", x"80000000", ALU_SLT,  x"00000000");
    check(x"80000000", x"7FFFFFFF", ALU_SLT,  x"00000001");
    check(x"00000000", x"FFFFFFFF", ALU_SLTU, x"00000001");
    check(x"80000000", x"7FFFFFFF", ALU_SLTU, x"00000000");
    check(x"7FFFFFFF", x"80000000", ALU_SLTU, x"00000001");
    -- add/sub extremes
    check(x"7FFFFFFF", x"00000001", ALU_ADD,  x"80000000");
    check(x"80000000", x"00000001", ALU_SUB,  x"7FFFFFFF");
    check(x"00000000", x"80000000", ALU_SUB,  x"80000000");
    check(x"00000005", x"00000005", ALU_SUB,  x"00000000");
    -- shifts: amount 0, amount from b[4:0] only, positive SRA
    check(x"12345678", x"00000000", ALU_SLL,  x"12345678");
    check(x"12345678", x"00000004", ALU_SLL,  x"23456780");
    check(x"00000001", x"FFFFFFE1", ALU_SLL,  x"00000002");  -- b[31:5] ignored
    check(x"80000000", x"00000000", ALU_SRL,  x"80000000");
    check(x"FFFFFFFF", x"00000008", ALU_SRL,  x"00FFFFFF");
    check(x"FFFFFFFF", x"00000020", ALU_SRL,  x"FFFFFFFF");  -- 32 -> amount 0
    check(x"80000000", x"00000000", ALU_SRA,  x"80000000");
    check(x"80000000", x"0000001F", ALU_SRA,  x"FFFFFFFF");
    check(x"40000000", x"00000004", ALU_SRA,  x"04000000");
    check(x"80000000", x"00000024", ALU_SRA,  x"F8000000");  -- amount 4 via b[4:0]
    -- zero flag from a non-trivial result
    check(x"F0F0F0F0", x"0F0F0F0F", ALU_AND,  x"00000000");

    report "alu_tb finished";
    wait;
  end process;
end architecture;