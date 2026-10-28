library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity counter is
  generic (WIDTH : positive := 4);
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;  -- synchronous, active high
    en    : in  std_logic;
    count : out std_logic_vector(WIDTH-1 downto 0)
  );
end entity;

architecture rtl of counter is
  signal cnt : unsigned(WIDTH-1 downto 0) := (others => '0');
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cnt <= (others => '0');
      elsif en = '1' then
        cnt <= cnt + 1;
      end if;
    end if;
  end process;

  count <= std_logic_vector(cnt);
end architecture;