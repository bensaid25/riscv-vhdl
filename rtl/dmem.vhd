library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dmem is
  generic (DEPTH : positive := 4096);          -- size in bytes, a multiple of 4
  port (
    clk       : in  std_logic;
    mem_write : in  std_logic;
    mem_read  : in  std_logic;
    funct3    : in  std_logic_vector(2 downto 0);
    addr      : in  std_logic_vector(31 downto 0);
    wdata     : in  std_logic_vector(31 downto 0);
    rdata     : out std_logic_vector(31 downto 0);
    -- test-bench initial data: write one word, little-endian (byte address, word aligned)
    load_we   : in  std_logic := '0';
    load_addr : in  std_logic_vector(31 downto 0) := (others => '0');
    load_data : in  std_logic_vector(31 downto 0) := (others => '0');
    -- debug word read (used by cocotb), little-endian
    dbg_addr  : in  std_logic_vector(31 downto 0) := (others => '0');
    dbg_data  : out std_logic_vector(31 downto 0)
  );
end entity;

-- Four byte lanes, so that each lane is a plain RAM (one write enable, one asynchronous read).
-- Accesses must be naturally aligned (word at a multiple of 4, half-word at a multiple of 2).
architecture rtl of dmem is
  constant WORDS : positive := DEPTH / 4;
  type lane_t is array (0 to WORDS - 1) of std_logic_vector(7 downto 0);
  signal lane0, lane1, lane2, lane3 : lane_t := (others => (others => '0'));

  signal widx, ridx, didx : natural range 0 to WORDS - 1;
  signal we               : std_logic_vector(3 downto 0);
  signal din              : std_logic_vector(31 downto 0);
  signal l0, l1, l2, l3   : std_logic_vector(7 downto 0);
begin
  assert DEPTH mod 4 = 0 report "dmem: DEPTH must be a multiple of 4" severity failure;

  -- Which word and which byte lanes are written, and with what data
  process(all)
    variable off : std_logic_vector(1 downto 0);
  begin
    we   <= "0000";
    din  <= wdata;
    widx <= to_integer(unsigned(addr(30 downto 2))) mod WORDS;
    off  := addr(1 downto 0);
    if load_we = '1' then                         -- test-bench load: a whole word
      widx <= to_integer(unsigned(load_addr(30 downto 2))) mod WORDS;
      din  <= load_data;
      we   <= "1111";
    elsif mem_write = '1' then
      case funct3(1 downto 0) is
        when "00" =>                              -- SB: the byte goes to every lane, one lane is enabled
          din <= wdata(7 downto 0) & wdata(7 downto 0) & wdata(7 downto 0) & wdata(7 downto 0);
          case off is
            when "00"   => we <= "0001";
            when "01"   => we <= "0010";
            when "10"   => we <= "0100";
            when others => we <= "1000";
          end case;
        when "01" =>                              -- SH: low half goes to the lower or upper two lanes
          din <= wdata(15 downto 0) & wdata(15 downto 0);
          if off(1) = '0' then we <= "0011"; else we <= "1100"; end if;
        when others =>                            -- SW
          we <= "1111";
      end case;
    end if;
  end process;

  -- Synchronous write, one process per lane
  process(clk)
  begin
    if rising_edge(clk) then
      if we(0) = '1' then lane0(widx) <= din(7 downto 0); end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if we(1) = '1' then lane1(widx) <= din(15 downto 8); end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if we(2) = '1' then lane2(widx) <= din(23 downto 16); end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if we(3) = '1' then lane3(widx) <= din(31 downto 24); end if;
    end if;
  end process;

  -- Asynchronous read of the four lanes of the addressed word
  ridx <= to_integer(unsigned(addr(30 downto 2))) mod WORDS;
  l0 <= lane0(ridx);
  l1 <= lane1(ridx);
  l2 <= lane2(ridx);
  l3 <= lane3(ridx);

  -- Byte / half-word selection with sign or zero extension
  process(all)
    variable b : std_logic_vector(7 downto 0);
    variable h : std_logic_vector(15 downto 0);
  begin
    case addr(1 downto 0) is
      when "00"   => b := l0;
      when "01"   => b := l1;
      when "10"   => b := l2;
      when others => b := l3;
    end case;
    if addr(1) = '0' then h := l1 & l0; else h := l3 & l2; end if;

    rdata <= (others => '0');
    if mem_read = '1' then
      case funct3 is
        when "000"  => rdata <= std_logic_vector(resize(signed(b), 32));   -- LB
        when "001"  => rdata <= std_logic_vector(resize(signed(h), 32));   -- LH
        when "010"  => rdata <= l3 & l2 & l1 & l0;                         -- LW
        when "100"  => rdata <= x"000000" & b;                             -- LBU
        when "101"  => rdata <= x"0000" & h;                               -- LHU
        when others => null;
      end case;
    end if;
  end process;

  -- Debug word read
  didx     <= to_integer(unsigned(dbg_addr(30 downto 2))) mod WORDS;
  dbg_data <= lane3(didx) & lane2(didx) & lane1(didx) & lane0(didx);
end architecture;
