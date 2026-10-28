library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter_tb is end entity;

architecture sim of counter_tb is
  constant WIDTH : positive := 4;
  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal en    : std_logic := '0';
  signal count : std_logic_vector(WIDTH-1 downto 0);
  signal done  : boolean := false;
begin
  dut: entity work.counter
    generic map (WIDTH => WIDTH)
    port map (clk => clk, rst => rst, en => en, count => count);

  clk <= not clk after 5 ns when not done;

  stim: process
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    rst <= '0';
    en  <= '1';

    for i in 1 to 20 loop
      wait until rising_edge(clk);
      wait for 1 ns;
      assert unsigned(count) = to_unsigned(i mod 2**WIDTH, WIDTH)
        report "Mismatch at step " & integer'image(i)
        severity error;
    end loop;

    en <= '0';  -- hold check
    wait until rising_edge(clk);
    wait for 1 ns;
    assert unsigned(count) = to_unsigned(20 mod 2**WIDTH, WIDTH)
      report "Counter changed while disabled" severity error;

    report "counter_tb finished";
    done <= true;
    wait;
  end process;
end architecture;