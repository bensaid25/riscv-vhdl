library ieee;
use ieee.std_logic_1164.all;

entity uart_tx is
  generic (
    CLKS_PER_BIT : positive := 434   -- e.g. 50 MHz / 115200 baud
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                       -- synchronous, active high
    tx_start : in  std_logic;                       -- one-cycle pulse
    tx_data  : in  std_logic_vector(7 downto 0);
    tx       : out std_logic;
    busy     : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  signal baud_cnt : natural range 0 to CLKS_PER_BIT - 1 := 0;
  signal bit_idx  : natural range 0 to 7 := 0;
  signal data_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal busy_i, in_start, in_data, in_stop : std_logic;
  signal bit_done, last_bit : std_logic;
begin
  fsm: entity work.uart_tx_fsm
    port map (clk => clk, rst => rst, start => tx_start,
              bit_done => bit_done, last_bit => last_bit,
              busy => busy_i, in_start => in_start,
              in_data => in_data, in_stop => in_stop);

  bit_done <= '1' when busy_i = '1' and baud_cnt = CLKS_PER_BIT - 1 else '0';
  last_bit <= '1' when bit_idx = 7 else '0';
  busy     <= busy_i;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        baud_cnt <= 0;
        bit_idx  <= 0;
      elsif busy_i = '0' then                -- idle: hold counters, grab data
        baud_cnt <= 0;
        bit_idx  <= 0;
        if tx_start = '1' then
          data_reg <= tx_data;
        end if;
      elsif bit_done = '1' then              -- end of a bit period
        baud_cnt <= 0;
        if in_data = '1' then
          if last_bit = '1' then bit_idx <= 0; else bit_idx <= bit_idx + 1; end if;
        end if;
      else
        baud_cnt <= baud_cnt + 1;
      end if;
    end if;
  end process;

  tx <= '0'                when in_start = '1' else
        data_reg(bit_idx)  when in_data  = '1' else
        '1';
end architecture;
