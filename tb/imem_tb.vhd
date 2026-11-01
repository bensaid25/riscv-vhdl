library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity imem_tb is end entity;

architecture sim of imem_tb is
  signal addr  : std_logic_vector(31 downto 0) := (others => '0');
  signal instr : std_logic_vector(31 downto 0);
begin
  dut: entity work.imem
    generic map (INIT_FILE => "tb/data/imem_test.hex", DEPTH => 16)
    port map (addr => addr, instr => instr);

  stim: process
    procedure check(constant a : in natural;
                    constant e : in std_logic_vector(31 downto 0);
                    constant name : in string) is
    begin
      addr <= std_logic_vector(to_unsigned(a, 32));
      wait for 1 ns;
      assert instr = e
        report name & ": expected " & to_hstring(e) & " got " & to_hstring(instr)
        severity error;
    end procedure;
  begin
    check(0,  x"00500113", "word 0");
    check(4,  x"00A00193", "word 1");
    check(8,  x"003100B3", "word 2");
    check(12, x"00000013", "past the program = NOP");
    check(7,  x"00A00193", "low 2 address bits ignored");
    report "imem_tb finished";
    wait;
  end process;
end architecture;