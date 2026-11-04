library ieee;
use ieee.std_logic_1164.all;

entity synth_top is
  generic (
    PIPELINED  : boolean  := false;
    IMEM_FILE  : string   := "sim/c/sort.hex";
    IMEM_WORDS : positive := 256;
    DMEM_BYTES : positive := 1024
  );
  port (
    clk : in  std_logic;
    rst : in  std_logic;
    led : out std_logic
  );
end entity;

architecture rtl of synth_top is
  signal pc, st_addr, st_data : std_logic_vector(31 downto 0);
  signal st_valid             : std_logic;
begin
  u_cpu : entity work.cpu_sc
    generic map (IMEM_FILE => IMEM_FILE, IMEM_WORDS => IMEM_WORDS,
                 DMEM_BYTES => DMEM_BYTES, PIPELINED => PIPELINED)
    port map (clk => clk, rst => rst, pc_out => pc, st_valid => st_valid,
              st_addr => st_addr, st_data => st_data,
              dbg_rdata => open, dbg_mdata => open);

  -- one registered bit that depends on every observation signal
  process(clk)
  begin
    if rising_edge(clk) then
      led <= (xor (pc & st_addr & st_data)) xor st_valid;
    end if;
  end process;
end architecture;