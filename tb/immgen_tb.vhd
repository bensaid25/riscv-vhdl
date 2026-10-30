library ieee;
use ieee.std_logic_1164.all;

entity immgen_tb is end entity;

architecture sim of immgen_tb is
  signal instr : std_logic_vector(31 downto 0) := (others => '0');
  signal imm   : std_logic_vector(31 downto 0);
begin
  dut: entity work.immgen port map (instr => instr, imm => imm);

  stim: process
    procedure check(constant i    : in std_logic_vector(31 downto 0);
                    constant e    : in std_logic_vector(31 downto 0);
                    constant name : in string) is
    begin
      instr <= i;
      wait for 1 ns;
      assert imm = e
        report name & ": expected " & to_hstring(e) & " got " & to_hstring(imm)
        severity error;
    end procedure;
  begin
    check(x"FFF00093", x"FFFFFFFF", "addi x1,x0,-1    (I)");
    check(x"00500113", x"00000005", "addi x2,x0,5     (I)");
    check(x"FF80A183", x"FFFFFFF8", "lw x3,-8(x1)     (I)");
    check(x"0020A423", x"00000008", "sw x2,8(x1)      (S)");
    check(x"FE20AE23", x"FFFFFFFC", "sw x2,-4(x1)     (S)");
    check(x"00208463", x"00000008", "beq x1,x2,+8     (B)");
    check(x"FE000EE3", x"FFFFFFFC", "beq x0,x0,-4     (B)");
    check(x"123450B7", x"12345000", "lui x1,0x12345   (U)");
    check(x"FFFFF097", x"FFFFF000", "auipc x1,0xFFFFF (U)");
    check(x"0080006F", x"00000008", "jal x0,+8        (J)");
    check(x"FFDFF06F", x"FFFFFFFC", "jal x0,-4        (J)");

    report "immgen_tb finished";
    wait;
  end process;
end architecture;