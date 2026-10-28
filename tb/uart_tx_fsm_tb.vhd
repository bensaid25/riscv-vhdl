library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_fsm_tb is end entity;

architecture sim of uart_tx_fsm_tb is
  signal clk, rst : std_logic := '0';
  signal start, bit_done, last_bit : std_logic := '0';
  signal busy, in_start, in_data, in_stop : std_logic;
  signal done : boolean := false;
begin
  rst <= '1', '0' after 22 ns;
  clk <= not clk after 5 ns when not done;

  dut: entity work.uart_tx_fsm
    port map (clk => clk, rst => rst, start => start, bit_done => bit_done,
              last_bit => last_bit, busy => busy, in_start => in_start,
              in_data => in_data, in_stop => in_stop);

  stim: process
    procedure step(s, d, l : std_logic) is
    begin
      start <= s; bit_done <= d; last_bit <= l;
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    wait until rst = '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert busy = '0' report "not idle after reset" severity error;

    step('0','1','0');   -- bit_done in IDLE must be ignored
    assert busy = '0' report "left IDLE without start" severity error;

    step('1','0','0');   -- start
    assert in_start = '1' and busy = '1' report "expected START_BIT" severity error;

    step('1','0','0');   -- start while busy, no bit_done: stay
    assert in_start = '1' report "START_BIT should hold" severity error;

    step('0','1','0');   -- bit_done: go to DATA_BITS
    assert in_data = '1' report "expected DATA_BITS" severity error;

    step('0','0','0');   -- no bit_done: stay
    assert in_data = '1' report "DATA_BITS should hold" severity error;

    step('0','1','0');   -- bit_done, not last: stay in DATA_BITS
    assert in_data = '1' report "left DATA_BITS too early" severity error;

    step('0','1','1');   -- bit_done and last_bit: go to STOP_BIT
    assert in_stop = '1' report "expected STOP_BIT" severity error;

    step('0','0','1');   -- no bit_done: stay
    assert in_stop = '1' report "STOP_BIT should hold" severity error;

    step('0','1','0');   -- bit_done: back to IDLE
    assert busy = '0' report "expected IDLE" severity error;

    report "uart_tx_fsm_tb finished";
    done <= true;
    wait;
  end process;
end architecture;
