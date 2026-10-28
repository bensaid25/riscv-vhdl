library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_tb is end entity;

architecture sim of uart_tx_tb is
  constant CLKS_PER_BIT : positive := 4;
  constant CLK_T : time := 10 ns;
  constant BIT_T : time := CLKS_PER_BIT * CLK_T;

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal tx_start : std_logic := '0';
  signal tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal tx, busy : std_logic;
  signal expected : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_count : natural := 0;
  signal done     : boolean := false;
begin
  clk <= not clk after CLK_T / 2 when not done;

  dut: entity work.uart_tx
    generic map (CLKS_PER_BIT => CLKS_PER_BIT)
    port map (clk => clk, rst => rst, tx_start => tx_start,
              tx_data => tx_data, tx => tx, busy => busy);

  -- UART receiver: sample each bit in the middle of its period
  receiver: process
    variable got : std_logic_vector(7 downto 0);
  begin
    wait until falling_edge(tx);
    wait for BIT_T / 2;
    assert tx = '0' report "start bit not low at its midpoint" severity error;
    for i in 0 to 7 loop
      wait for BIT_T;
      got(i) := tx;                         -- LSB first
    end loop;
    wait for BIT_T;
    assert tx = '1' report "stop bit not high" severity error;
    assert got = expected
      report "received " & to_hstring(got) & ", expected " & to_hstring(expected)
      severity error;
    rx_count <= rx_count + 1;
  end process;

  stim: process
    procedure send(b : std_logic_vector(7 downto 0)) is
    begin
      expected <= b;
      tx_data  <= b;
      tx_start <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      tx_start <= '0';
    end procedure;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    assert tx = '1' and busy = '0' report "line must idle high" severity error;

    -- Test 1: one byte, with a start pulse (different data) while busy
    send(x"A5");
    assert busy = '1' report "busy should be high after start" severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    tx_data  <= x"FF";
    tx_start <= '1';                        -- must be ignored
    wait until rising_edge(clk);
    wait for 1 ns;
    tx_start <= '0';
    wait until busy = '0';
    wait for 2 * BIT_T;
    assert rx_count = 1 report "start while busy was not ignored" severity error;

    -- Test 2: back-to-back bytes, including all-zeros and all-ones
    send(x"00"); wait until busy = '0';
    send(x"FF"); wait until busy = '0';
    send(x"3C"); wait until busy = '0';
    wait for 2 * BIT_T;
    assert rx_count = 4 report "wrong number of bytes received" severity error;
    assert tx = '1' report "line must return to idle high" severity error;

    report "uart_tx_tb finished";
    done <= true;
    wait;
  end process;
end architecture;
