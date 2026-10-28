library ieee;
use ieee.std_logic_1164.all;

entity uart_tx_fsm is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;   -- synchronous, active high
    start    : in  std_logic;   -- request to send
    bit_done : in  std_logic;   -- current bit period has ended
    last_bit : in  std_logic;   -- the data bit being sent is bit 7
    busy     : out std_logic;
    in_start : out std_logic;
    in_data  : out std_logic;
    in_stop  : out std_logic
  );
end entity;

architecture rtl of uart_tx_fsm is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
  signal state, next_state : state_t := IDLE;
begin
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
      else
        state <= next_state;
      end if;
    end if;
  end process;

  process(all)
  begin
    next_state <= state;          -- default: stay
    case state is
      when IDLE      => if start = '1' then next_state <= START_BIT; end if;
      when START_BIT => if bit_done = '1' then next_state <= DATA_BITS; end if;
      when DATA_BITS => if bit_done = '1' and last_bit = '1' then next_state <= STOP_BIT; end if;
      when STOP_BIT  => if bit_done = '1' then next_state <= IDLE; end if;
    end case;
  end process;

  -- Moore outputs
  busy     <= '0' when state = IDLE      else '1';
  in_start <= '1' when state = START_BIT else '0';
  in_data  <= '1' when state = DATA_BITS else '0';
  in_stop  <= '1' when state = STOP_BIT  else '0';
end architecture;
