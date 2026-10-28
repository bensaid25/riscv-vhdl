library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity regfile is
  port (
    clk    : in  std_logic;
    we     : in  std_logic;
    waddr  : in  std_logic_vector(4 downto 0);
    wdata  : in  std_logic_vector(31 downto 0);
    raddr1 : in  std_logic_vector(4 downto 0);
    raddr2 : in  std_logic_vector(4 downto 0);
    rdata1 : out std_logic_vector(31 downto 0);
    rdata2 : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of regfile is
  type reg_array_t is array (0 to 31) of std_logic_vector(31 downto 0);
  signal regs : reg_array_t := (others => (others => '0'));
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if we = '1' and waddr /= "00000" then   -- x0 is never written
        regs(to_integer(unsigned(waddr))) <= wdata;
      end if;
    end if;
  end process;

  rdata1 <= regs(to_integer(unsigned(raddr1)));  -- asynchronous reads
  rdata2 <= regs(to_integer(unsigned(raddr2)));
end architecture;