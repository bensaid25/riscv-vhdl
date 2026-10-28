library ieee;
use ieee.std_logic_1164.all;

entity seq_detector_mealy is
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;   -- synchronous, active high
    din      : in  std_logic;
    detected : out std_logic
  );
end entity;

architecture rtl of seq_detector_mealy is
  type state_t is (S0, S1, S10, S101);
  signal state, next_state : state_t := S0;
begin
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

  process(all)
  begin
    next_state <= state;
    case state is
      when S0   => if din = '1' then next_state <= S1; end if;
      when S1   => if din = '0' then next_state <= S10; end if;
      when S10  => if din = '1' then next_state <= S101; else next_state <= S0; end if;
      -- 1011 completed: its last '1' can start the next pattern, so go to S1
      when S101 => if din = '1' then next_state <= S1; else next_state <= S10; end if;
    end case;
  end process;

  -- Mealy output: state AND input
  detected <= '1' when (state = S101 and din = '1') else '0';
end architecture;
