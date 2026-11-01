library ieee;
use ieee.std_logic_1164.all;

entity regfile_bypass_tb is end entity;

architecture sim of regfile_bypass_tb is
  signal clk : std_logic := '0';
  signal we  : std_logic := '0';
  signal waddr, raddr1, raddr2 : std_logic_vector(4 downto 0) := (others => '0');
  signal wdata : std_logic_vector(31 downto 0) := (others => '0');
  signal b1, b2, n1, n2 : std_logic_vector(31 downto 0);
  signal done : boolean := false;
begin
  clk <= not clk after 5 ns when not done;

  with_bypass : entity work.regfile
    generic map (BYPASS => true)
    port map (clk => clk, we => we, waddr => waddr, wdata => wdata,
              raddr1 => raddr1, raddr2 => raddr2, rdata1 => b1, rdata2 => b2);

  without_bypass : entity work.regfile
    generic map (BYPASS => false)
    port map (clk => clk, we => we, waddr => waddr, wdata => wdata,
              raddr1 => raddr1, raddr2 => raddr2, rdata1 => n1, rdata2 => n2);

  stim : process
    procedure write_reg(a : std_logic_vector(4 downto 0); d : std_logic_vector(31 downto 0)) is
    begin
      waddr <= a; wdata <= d; we <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      we <= '0';
    end procedure;
  begin
    wait for 1 ns;
    write_reg("00101", x"11111111");              -- x5
    write_reg("00110", x"22222222");              -- x6
    -- now 1 ns after a clock edge: the checks below stay inside one cycle

    -- x5 is being written; read x5 and x6 in the same cycle
    waddr <= "00101"; wdata <= x"DEADBEEF"; we <= '1';
    raddr1 <= "00101"; raddr2 <= "00110";
    wait for 1 ns;
    assert b1 = x"DEADBEEF" report "bypass: read of the written register on port 1" severity error;
    assert b2 = x"22222222" report "bypass: unrelated register on port 2 changed" severity error;
    assert n1 = x"11111111" report "no bypass: must read the old value" severity error;
    assert n2 = x"22222222" report "no bypass: unrelated register changed" severity error;

    -- same read on port 2
    raddr1 <= "00110"; raddr2 <= "00101";
    wait for 1 ns;
    assert b1 = x"22222222" report "bypass: unrelated register on port 1 changed" severity error;
    assert b2 = x"DEADBEEF" report "bypass: read of the written register on port 2" severity error;

    -- write enable low: no bypass, old value
    we <= '0';
    wait for 1 ns;
    assert b2 = x"11111111" report "bypass applied while we = 0" severity error;

    -- x0 is never bypassed
    we <= '1'; waddr <= "00000"; wdata <= x"FFFFFFFF"; raddr1 <= "00000";
    wait for 1 ns;
    assert b1 = x"00000000" report "bypass returned data for x0" severity error;

    -- after the clock edge the new value is stored, with or without bypass
    waddr <= "00101"; wdata <= x"DEADBEEF"; we <= '1'; raddr1 <= "00101";
    wait until rising_edge(clk);
    wait for 1 ns;
    we <= '0';
    wait for 1 ns;
    assert b1 = x"DEADBEEF" report "bypass: value not stored" severity error;
    assert n1 = x"DEADBEEF" report "no bypass: value not stored" severity error;

    report "regfile_bypass_tb finished";
    done <= true;
    wait;
  end process;
end architecture;
