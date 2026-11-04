library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem_tb is end entity;

architecture sim of dmem_tb is
  signal clk       : std_logic := '0';
  signal mem_write : std_logic := '0';
  signal mem_read  : std_logic := '0';
  signal funct3    : std_logic_vector(2 downto 0) := "010";
  signal addr      : std_logic_vector(31 downto 0) := (others => '0');
  signal wdata     : std_logic_vector(31 downto 0) := (others => '0');
  signal rdata     : std_logic_vector(31 downto 0);
  signal done      : boolean := false;
  signal load_we   : std_logic := '0';
  signal load_addr : std_logic_vector(31 downto 0) := (others => '0');
  signal load_data : std_logic_vector(31 downto 0) := (others => '0');

  constant F_B  : std_logic_vector(2 downto 0) := "000";
  constant F_H  : std_logic_vector(2 downto 0) := "001";
  constant F_W  : std_logic_vector(2 downto 0) := "010";
  constant F_BU : std_logic_vector(2 downto 0) := "100";
  constant F_HU : std_logic_vector(2 downto 0) := "101";
begin
  dut: entity work.dmem
    port map (clk => clk, mem_write => mem_write, mem_read => mem_read,
              funct3 => funct3, addr => addr, wdata => wdata, rdata => rdata,
              load_we => load_we, load_addr => load_addr, load_data => load_data);

  clk <= not clk after 5 ns when not done;

  stim: process
    procedure store(constant a : in natural;
                    constant d : in std_logic_vector(31 downto 0);
                    constant f3 : in std_logic_vector(2 downto 0)) is
    begin
      addr <= std_logic_vector(to_unsigned(a, 32));
      wdata <= d;  funct3 <= f3;  mem_write <= '1';
      wait until rising_edge(clk);
      wait for 1 ns;
      mem_write <= '0';
    end procedure;

    procedure load(constant name : in string;
                   constant a : in natural;
                   constant f3 : in std_logic_vector(2 downto 0);
                   constant e : in std_logic_vector(31 downto 0)) is
    begin
      addr <= std_logic_vector(to_unsigned(a, 32));
      funct3 <= f3;  mem_read <= '1';
      wait for 1 ns;
      assert rdata = e
        report name & ": expected " & to_hstring(e) & " got " & to_hstring(rdata)
        severity error;
      mem_read <= '0';
    end procedure;
  begin
    wait until rising_edge(clk);
    wait for 1 ns;

    store(16, x"80FF7F01", F_W);
    load("LW",          16, F_W,  x"80FF7F01");
    load("LB  @16",     16, F_B,  x"00000001");
    load("LB  @17",     17, F_B,  x"0000007F");
    load("LB  @18 sign",18, F_B,  x"FFFFFFFF");
    load("LBU @18",     18, F_BU, x"000000FF");
    load("LB  @19 sign",19, F_B,  x"FFFFFF80");
    load("LH  @16",     16, F_H,  x"00007F01");
    load("LH  @18 sign",18, F_H,  x"FFFF80FF");
    load("LHU @18",     18, F_HU, x"000080FF");

    store(17, x"000000AA", F_B);                       -- SB must touch one byte only
    load("LW after SB", 16, F_W,  x"80FFAA01");

    store(18, x"00001234", F_H);                       -- SH must touch two bytes only
    load("LW after SH", 16, F_W,  x"1234AA01");

    -- every byte lane and both half-word positions, on a word of known content
    store(32, x"11223344", F_W);  load("LW @32 init",  32, F_W, x"11223344");
    store(32, x"FFFFFFAA", F_B);  load("LW after SB@32", 32, F_W, x"112233AA");
    store(33, x"FFFFFFBB", F_B);  load("LW after SB@33", 32, F_W, x"1122BBAA");
    store(34, x"FFFFFFCC", F_B);  load("LW after SB@34", 32, F_W, x"11CCBBAA");
    store(35, x"FFFFFFDD", F_B);  load("LW after SB@35", 32, F_W, x"DDCCBBAA");
    store(32, x"ABCD5566", F_H);  load("LW after SH@32", 32, F_W, x"DDCC5566");
    store(34, x"EF017788", F_H);  load("LW after SH@34", 32, F_W, x"77885566");

    -- write enable low: nothing may change
    addr <= std_logic_vector(to_unsigned(16, 32));
    wdata <= x"FFFFFFFF";  funct3 <= F_W;  mem_write <= '0';
    wait until rising_edge(clk);
    wait for 1 ns;
    load("LW, we=0",    16, F_W,  x"1234AA01");

    -- read enable low: output must be zero
    mem_read <= '0';
    wait for 1 ns;
    assert rdata = x"00000000" report "rdata not zero when mem_read=0" severity error;

    -- initial-data load port: a little-endian word, readable with every load width
    load_addr <= std_logic_vector(to_unsigned(64, 32));
    load_data <= x"11223344";
    load_we   <= '1';
    wait until rising_edge(clk);
    wait for 1 ns;
    load_we   <= '0';
    load("load port LW",  64, F_W,  x"11223344");
    load("load port LB",  65, F_B,  x"00000033");
    load("load port LH",  66, F_H,  x"00001122");
    load("load port LBU", 67, F_BU, x"00000011");

    report "dmem_tb finished";
    done <= true;
    wait;
  end process;
end architecture;