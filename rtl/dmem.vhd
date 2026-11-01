library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem is
  generic (DEPTH : positive := 4096);          -- size in bytes
  port (
    clk       : in  std_logic;
    mem_write : in  std_logic;
    mem_read  : in  std_logic;
    funct3    : in  std_logic_vector(2 downto 0);
    addr      : in  std_logic_vector(31 downto 0);
    wdata     : in  std_logic_vector(31 downto 0);
    rdata     : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of dmem is
  type mem_t is array (0 to DEPTH-1) of std_logic_vector(7 downto 0);
  signal mem : mem_t := (others => (others => '0'));
begin
  -- Synchronous write (little-endian)
  process(clk)
    variable a : natural;
  begin
    if rising_edge(clk) then
      if mem_write = '1' then
        a := to_integer(unsigned(addr(30 downto 0))) mod DEPTH;
        mem(a) <= wdata(7 downto 0);                          -- SB, SH, SW
        if funct3(1 downto 0) /= "00" then                    -- SH, SW
          mem((a + 1) mod DEPTH) <= wdata(15 downto 8);
        end if;
        if funct3(1) = '1' then                               -- SW
          mem((a + 2) mod DEPTH) <= wdata(23 downto 16);
          mem((a + 3) mod DEPTH) <= wdata(31 downto 24);
        end if;
      end if;
    end if;
  end process;

   -- Asynchronous read with sign/zero extension
  process(all)
    variable a  : natural;
    variable b0, b1, b2, b3 : std_logic_vector(7 downto 0);
    variable h  : std_logic_vector(15 downto 0);
    variable w  : std_logic_vector(31 downto 0);
  begin
    a  := to_integer(unsigned(addr(30 downto 0))) mod DEPTH;
    b0 := mem(a);
    b1 := mem((a + 1) mod DEPTH);
    b2 := mem((a + 2) mod DEPTH);
    b3 := mem((a + 3) mod DEPTH);
    h  := b1 & b0;
    w  := b3 & b2 & b1 & b0;

    rdata <= (others => '0');
    if mem_read = '1' then
      case funct3 is
        when "000"  => rdata <= std_logic_vector(resize(signed(b0), 32));   -- LB
        when "001"  => rdata <= std_logic_vector(resize(signed(h), 32));    -- LH
        when "010"  => rdata <= w;                                          -- LW
        when "100"  => rdata <= x"000000" & b0;                             -- LBU
        when "101"  => rdata <= x"0000" & h;                                -- LHU
        when others => null;
      end case;
    end if;
  end process;
end architecture;