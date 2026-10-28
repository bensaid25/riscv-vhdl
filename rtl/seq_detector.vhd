library ieee;
use ieee.std_logic_1164.all;

entity seq_detector is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;   -- synchronous, active high
    din      : in  std_logic;
    detected : out std_logic
  );
end entity;

architecture rtl of seq_detector is
  type state_t is (S0, S1, S10, S101, S1011);
  signal state, next_state : state_t := S0;
begin
  -- Process 1: state register
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= S0;
      else
        state <= next_state;
      end if;
    end if;
  end process;

  -- Process 2: next-state logic
  process(all)
  begin
    next_state <= state;          -- default: stay (avoids latches)
    case state is
      when S0    => if din = '1' then next_state <= S1; end if;
      when S1    => if din = '0' then next_state <= S10; end if;
      when S10   => if din = '1' then next_state <= S101; else next_state <= S0; end if;
      when S101  => if din = '1' then next_state <= S1011; else next_state <= S10; end if;
      when S1011 => if din = '1' then next_state <= S1; else next_state <= S10; end if;
    end case;
  end process;

  -- Moore output: depends on the state only
  detected <= '1' when state = S1011 else '0';
end architecture;