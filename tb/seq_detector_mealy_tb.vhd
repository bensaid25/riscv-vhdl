library ieee;
use ieee.std_logic_1164.all;

entity seq_detector_mealy_tb is end entity;

architecture sim of seq_detector_mealy_tb is
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal din      : std_logic := '0';
  signal detected : std_logic;
  signal done     : boolean := false;
begin
  dut: entity work.seq_detector_mealy
    port map (clk => clk, rst => rst, din => din, detected => detected);

  clk <= not clk after 5 ns when not done;

  stim: process
    constant STREAM : string := "00101101110110101100111011011";
    variable hist : std_logic_vector(3 downto 0) := "0000";
    variable b    : std_logic;
    variable hits : natural := 0;
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    -- Test 1: golden model. Mealy: drive din, let the output settle,
    -- check BEFORE the edge that consumes the bit.
    for i in STREAM'range loop
      if STREAM(i) = '1' then b := '1'; else b := '0'; end if;
      din <= b;
      wait for 1 ns;
      hist := hist(2 downto 0) & b;
      if hist = "1011" then
        hits := hits + 1;
        assert detected = '1'
          report "Missed pattern at index " & integer'image(i) severity error;
      else
        assert detected = '0'
          report "False detection at index " & integer'image(i) severity error;
      end if;
      wait until rising_edge(clk);
      wait for 1 ns;
    end loop;
    assert hits = 6
      report "Golden model counted " & integer'image(hits) & " hits, expected 6"
      severity error;

    -- Test 2: reset must win over the transition at the same edge.
    -- "101" leaves the FSM in S101 whatever state it started in.
    din <= '1'; wait until rising_edge(clk); wait for 1 ns;
    din <= '0'; wait until rising_edge(clk); wait for 1 ns;
    din <= '1'; wait until rising_edge(clk); wait for 1 ns;
    rst <= '1'; din <= '1';                  -- without reset this would go to S1
    wait until rising_edge(clk); wait for 1 ns;
    rst <= '0';
    -- From S0, "011" never matches; from S1 it would
    din <= '0'; wait until rising_edge(clk); wait for 1 ns;
    din <= '1'; wait until rising_edge(clk); wait for 1 ns;
    din <= '1'; wait for 1 ns;
    assert detected = '0' report "Reset did not clear the FSM" severity error;

    report "seq_detector_mealy_tb finished";
    done <= true;
    wait;
  end process;
end architecture;
