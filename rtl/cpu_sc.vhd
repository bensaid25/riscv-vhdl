library ieee;
use ieee.std_logic_1164.all;

entity cpu_sc is
  generic (
    IMEM_FILE  : string   := "";
    IMEM_WORDS : positive := 1024;
    DMEM_BYTES : positive := 4096;
    PIPELINED  : boolean  := false        -- false: single-cycle cpu_core, true: cpu_pipe
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                       -- synchronous, active high
    -- observation ports (for testbenches)
    pc_out   : out std_logic_vector(31 downto 0);
    st_valid : out std_logic;                       -- a store happens this cycle
    st_addr  : out std_logic_vector(31 downto 0);
    st_data  : out std_logic_vector(31 downto 0);
    -- optional ports for cocotb (unused by cpu_tb)
    load_we   : in  std_logic := '0';          -- write one instruction word
    load_addr : in  std_logic_vector(31 downto 0) := (others => '0');  -- byte address
    load_data : in  std_logic_vector(31 downto 0) := (others => '0');
    dload_we   : in  std_logic := '0';          -- write one data-memory word (initial data)
    dload_addr : in  std_logic_vector(31 downto 0) := (others => '0');  -- byte address
    dload_data : in  std_logic_vector(31 downto 0) := (others => '0');
    dbg_raddr : in  std_logic_vector(4 downto 0) := (others => '0');
    dbg_rdata : out std_logic_vector(31 downto 0);
    dbg_maddr : in  std_logic_vector(31 downto 0) := (others => '0');  -- data memory byte address
    dbg_mdata : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of cpu_sc is
  signal pc, instr                : std_logic_vector(31 downto 0);
  signal d_we, d_re               : std_logic;
  signal d_funct3                 : std_logic_vector(2 downto 0);
  signal d_addr, d_wdata, d_rdata : std_logic_vector(31 downto 0);
begin
  gen_single : if not PIPELINED generate
    u_core : entity work.cpu_core
      port map (clk => clk, rst => rst,
                imem_addr => pc, imem_instr => instr,
                dmem_we => d_we, dmem_re => d_re, dmem_funct3 => d_funct3,
                dmem_addr => d_addr, dmem_wdata => d_wdata, dmem_rdata => d_rdata,
                dbg_raddr => dbg_raddr, dbg_rdata => dbg_rdata);
  end generate;

  gen_pipe : if PIPELINED generate
    u_core : entity work.cpu_pipe
      port map (clk => clk, rst => rst,
                imem_addr => pc, imem_instr => instr,
                dmem_we => d_we, dmem_re => d_re, dmem_funct3 => d_funct3,
                dmem_addr => d_addr, dmem_wdata => d_wdata, dmem_rdata => d_rdata,
                dbg_raddr => dbg_raddr, dbg_rdata => dbg_rdata);
  end generate;

  u_imem : entity work.imem
    generic map (INIT_FILE => IMEM_FILE, DEPTH => IMEM_WORDS)
    port map (addr => pc, instr => instr, clk => clk,
              load_we => load_we, load_addr => load_addr, load_data => load_data);

  u_dmem : entity work.dmem
    generic map (DEPTH => DMEM_BYTES)
    port map (clk => clk, mem_write => d_we, mem_read => d_re,
              funct3 => d_funct3, addr => d_addr,
              wdata => d_wdata, rdata => d_rdata,
              dbg_addr => dbg_maddr, dbg_data => dbg_mdata,
              load_we => dload_we, load_addr => dload_addr, load_data => dload_data);

  -- Observation: the very signals wired into the data memory
  pc_out   <= pc;
  st_valid <= d_we;
  st_addr  <= d_addr;
  st_data  <= d_wdata;
end architecture;
