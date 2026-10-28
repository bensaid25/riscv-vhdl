library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile_tb is end entity;

architecture sim of regfile_tb is
  signal clk    : std_logic := '0';
  signal we     : std_logic := '0';
  signal waddr  : std_logic_vector(4 downto 0)  := (others => '0');
  signal wdata  : std_logic_vector(31 downto 0) := (others => '0');
  signal raddr1 : std_logic_vector(4 downto 0)  := (others => '0');
  signal raddr2 : std_logic_vector(4 downto 0)  := (others => '0');
  signal rdata1 : std_logic_vector(31 downto 0);
  signal rdata2 : std_logic_vector(31 downto 0);
  signal done   : boolean := false;

  constant ZERO : std_logic_vector(31 downto 0) := (others => '0');

  function reg(n : natural) return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(n, 5));
  end function;
begin
  dut: entity work.regfile
    port map (clk => clk, we => we, waddr => waddr, wdata => wdata,
              raddr1 => raddr1, raddr2 => raddr2,
              rdata1 => rdata1, rdata2 => rdata2);

  clk <= not clk after 5 ns when not done;

  stim: process
    -- write one register on the next rising edge, then drop we
    procedure write_reg(constant addr : in natural;
                        constant data : in std_logic_vector(31 downto 0)) is
    begin
      waddr <= reg(addr);
      wdata <= data;
      we    <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      we    <= '0';
    end procedure;

    -- read two registers (asynchronous) and compare
    procedure check(constant a1, a2 : in natural;
                    constant e1, e2 : in std_logic_vector(31 downto 0);
                    constant msg    : in string) is
    begin
      raddr1 <= reg(a1);
      raddr2 <= reg(a2);
      wait for 1 ns;
      assert rdata1 = e1
        report msg & ": port 1 expected " & to_hstring(e1)
               & " got " & to_hstring(rdata1)
        severity error;
      assert rdata2 = e2
        report msg & ": port 2 expected " & to_hstring(e2)
               & " got " & to_hstring(rdata2)
        severity error;
    end procedure;
  begin
    wait until rising_edge(clk);
    wait for 1 ns;

    -- Test 1: two writes, read both back on both ports
    write_reg(5, x"DEADBEEF");
    write_reg(6, x"12345678");
    check(5, 6, x"DEADBEEF", x"12345678", "T1 read x5,x6");
    check(6, 5, x"12345678", x"DEADBEEF", "T1 ports swapped");

    -- Test 2: x0 is hardwired to zero
    write_reg(0, x"FFFFFFFF");
    check(0, 0, ZERO, ZERO, "T2 x0 must stay zero");

    -- Test 3: no write when we = '0'
    waddr <= reg(7);
    wdata <= x"AAAAAAAA";
    we    <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    check(7, 5, ZERO, x"DEADBEEF", "T3 write blocked when we=0");

    -- Test 4: read and write the same register in the same cycle
    wait until rising_edge(clk);
    wait for 1 ns;
    waddr  <= reg(5);
    wdata  <= x"CAFEBABE";
    we     <= '1';
    raddr1 <= reg(5);
    wait for 2 ns;                        -- still before the next clock edge
    assert rdata1 = x"DEADBEEF"
      report "T4 before edge: expected OLD value DEADBEEF got " & to_hstring(rdata1)
      severity error;
    wait until rising_edge(clk);
    wait for 1 ns;
    we <= '0';
    assert rdata1 = x"CAFEBABE"
      report "T4 after edge: expected NEW value CAFEBABE got " & to_hstring(rdata1)
      severity error;

    -- Test 5: fill x1..x31 with distinct values, then verify all of them
    for i in 1 to 31 loop
      write_reg(i, std_logic_vector(to_unsigned(i * 1000, 32)));
    end loop;
    for i in 1 to 31 loop
      check(i, 0, std_logic_vector(to_unsigned(i * 1000, 32)), ZERO,
            "T5 readback x" & integer'image(i));
    end loop;

    report "regfile_tb finished";
    done <= true;
    wait;
  end process;
end architecture;