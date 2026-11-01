library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;
use work.ctrl_pkg.all;

entity cpu_sc is
  generic (
    IMEM_FILE  : string   := "";
    IMEM_WORDS : positive := 1024;
    DMEM_BYTES : positive := 4096
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;                       -- synchronous, active high
    -- observation ports (for testbenches)
    pc_out   : out std_logic_vector(31 downto 0);
    st_valid : out std_logic;                       -- a store happens this cycle
    st_addr  : out std_logic_vector(31 downto 0);
    st_data  : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of cpu_sc is
  signal mem_wdata : std_logic_vector(31 downto 0);
  signal pc, pc_plus4, pc_target, next_pc : std_logic_vector(31 downto 0) := (others => '0');
  signal instr, imm                       : std_logic_vector(31 downto 0);
  signal rs1_data, rs2_data               : std_logic_vector(31 downto 0);
  signal alu_a, alu_b, alu_result         : std_logic_vector(31 downto 0);
  signal mem_rdata, wb_data               : std_logic_vector(31 downto 0);
  signal zero, take_branch                : std_logic;

  signal reg_write, a_sel, b_sel, mem_read, mem_write : std_logic;
  signal branch, jal, jalr                            : std_logic;
  signal rf_we, dm_we                                 : std_logic;
  signal alu_op : alu_op_t;
  signal wb_sel : wb_sel_t;
begin
  -- Program counter
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pc <= (others => '0');
      else
        pc <= next_pc;
      end if;
    end if;
  end process;

  pc_plus4  <= std_logic_vector(unsigned(pc) + 4);
  pc_target <= std_logic_vector(unsigned(pc) + unsigned(imm));

  next_pc <= (alu_result(31 downto 1) & '0') when jalr = '1' else
             pc_target                       when (jal = '1' or take_branch = '1') else
             pc_plus4;

  -- Fetch and decode
  u_imem : entity work.imem
    generic map (INIT_FILE => IMEM_FILE, DEPTH => IMEM_WORDS)
    port map (addr => pc, instr => instr);

  u_ctrl : entity work.control
    port map (opcode => instr(6 downto 0), funct3 => instr(14 downto 12),
              funct7b5 => instr(30),
              reg_write => reg_write, a_sel => a_sel, b_sel => b_sel,
              alu_op => alu_op, mem_read => mem_read, mem_write => mem_write,
              wb_sel => wb_sel, branch => branch, jal => jal, jalr => jalr);

  u_imm : entity work.immgen
    port map (instr => instr, imm => imm);

  -- Writes are blocked while in reset
  rf_we <= reg_write and not rst;
  dm_we <= mem_write and not rst;

  u_rf : entity work.regfile
    port map (clk => clk, we => rf_we,
              waddr => instr(11 downto 7), wdata => wb_data,
              raddr1 => instr(19 downto 15), raddr2 => instr(24 downto 20),
              rdata1 => rs1_data, rdata2 => rs2_data);

  -- Execute
  alu_a <= pc  when a_sel = '1' else rs1_data;
  alu_b <= imm when b_sel = '1' else rs2_data;

  u_alu : entity work.alu
    port map (a => alu_a, b => alu_b, op => alu_op, result => alu_result, zero => zero);

  u_br : entity work.branch_unit
    port map (branch => branch, funct3 => instr(14 downto 12),
              zero => zero, lt => alu_result(0), take_branch => take_branch);

  -- Memory
  u_dmem : entity work.dmem
    generic map (DEPTH => DMEM_BYTES)
    port map (clk => clk, mem_write => dm_we, mem_read => mem_read,
              funct3 => instr(14 downto 12), addr => alu_result,
              wdata => mem_wdata, rdata => mem_rdata);

  -- Write-back
  with wb_sel select
    wb_data <= alu_result when WB_ALU,
               mem_rdata  when WB_MEM,
               pc_plus4   when WB_PC4;

  -- Observation
  pc_out   <= pc;
  mem_wdata <= rs2_data;
  st_valid <= dm_we;
  st_addr  <= alu_result;
  st_data  <= mem_wdata;
end architecture;