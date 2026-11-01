library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity cpu_tb is end entity;

architecture sim of cpu_tb is
  signal clk  : std_logic := '0';
  signal rst  : std_logic := '1';
  signal done : boolean   := false;

  signal a_pc, a_st_addr, a_st_data : std_logic_vector(31 downto 0);
  signal b_pc, b_st_addr, b_st_data : std_logic_vector(31 downto 0);
  signal a_st_valid, b_st_valid     : std_logic;

  signal a_cnt, b_cnt : natural := 0;
  signal a_addr_seen, a_data_seen : std_logic_vector(31 downto 0) := (others => 'U');
  signal b_addr_seen, b_data_seen : std_logic_vector(31 downto 0) := (others => 'U');
begin
  clk <= not clk after 5 ns when not done;

  dut_a : entity work.cpu_sc
    generic map (IMEM_FILE => "tb/data/prog_add.hex", IMEM_WORDS => 64, DMEM_BYTES => 256)
    port map (clk => clk, rst => rst, pc_out => a_pc,
              st_valid => a_st_valid, st_addr => a_st_addr, st_data => a_st_data);

  dut_b : entity work.cpu_sc
    generic map (IMEM_FILE => "tb/data/prog_loop.hex", IMEM_WORDS => 64, DMEM_BYTES => 256)
    port map (clk => clk, rst => rst, pc_out => b_pc,
              st_valid => b_st_valid, st_addr => b_st_addr, st_data => b_st_data);

  -- Store monitors: sample on the clock edge, as the data memory does
  monitor : process(clk)
  begin
    if rising_edge(clk) then
      if a_st_valid = '1' then
        a_cnt <= a_cnt + 1;  a_addr_seen <= a_st_addr;  a_data_seen <= a_st_data;
      end if;
      if b_st_valid = '1' then
        b_cnt <= b_cnt + 1;  b_addr_seen <= b_st_addr;  b_data_seen <= b_st_data;
      end if;
    end if;
  end process;

  stim : process
  begin
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    rst <= '0';

    for i in 1 to 60 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;

    -- Program A: 5 + 10 stored at address 0
    assert a_cnt = 1 report "A: expected exactly 1 store, saw " & integer'image(a_cnt) severity error;
    assert a_addr_seen = x"00000000" report "A: wrong store address " & to_hstring(a_addr_seen) severity error;
    assert a_data_seen = x"0000000F" report "A: wrong store data " & to_hstring(a_data_seen) severity error;
    assert a_pc = x"00000010" report "A: CPU not parked at the halt loop, pc=" & to_hstring(a_pc) severity error;

    -- Program B: loop sum stored at address 4
    assert b_cnt = 1 report "B: expected exactly 1 store, saw " & integer'image(b_cnt) severity error;
    assert b_addr_seen = x"00000004" report "B: wrong store address " & to_hstring(b_addr_seen) severity error;
    assert b_data_seen = x"0000000F" report "B: wrong store data " & to_hstring(b_data_seen) severity error;
    assert b_pc = x"00000018" report "B: CPU not parked at the halt loop, pc=" & to_hstring(b_pc) severity error;

    report "cpu_tb finished";
    done <= true;
    wait;
  end process;
end architecture;