library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;
use work.ctrl_pkg.all;

entity cpu_core is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;                       -- synchronous, active high
    -- instruction port
    imem_addr   : out std_logic_vector(31 downto 0);
    imem_instr  : in  std_logic_vector(31 downto 0);
    -- data port
    dmem_we     : out std_logic;
    dmem_re     : out std_logic;
    dmem_funct3 : out std_logic_vector(2 downto 0);
    dmem_addr   : out std_logic_vector(31 downto 0);
    dmem_wdata  : out std_logic_vector(31 downto 0);
    dmem_rdata  : in  std_logic_vector(31 downto 0);
    -- debug register read port (used by cocotb)
    dbg_raddr   : in  std_logic_vector(4 downto 0) := (others => '0');
    dbg_rdata   : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of cpu_core is
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

  -- Fetch (the memory lives outside the core)
  imem_addr <= pc;
  instr     <= imem_instr;

  -- Decode
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
              rdata1 => rs1_data, rdata2 => rs2_data,
              dbg_addr => dbg_raddr, dbg_data => dbg_rdata);

  -- Execute
  alu_a <= pc  when a_sel = '1' else rs1_data;
  alu_b <= imm when b_sel = '1' else rs2_data;

  u_alu : entity work.alu
    port map (a => alu_a, b => alu_b, op => alu_op, result => alu_result, zero => zero);

  u_br : entity work.branch_unit
    port map (branch => branch, funct3 => instr(14 downto 12),
              zero => zero, lt => alu_result(0), take_branch => take_branch);

  -- Data port (the memory lives outside the core)
  dmem_we     <= dm_we;
  dmem_re     <= mem_read;
  dmem_funct3 <= instr(14 downto 12);
  dmem_addr   <= alu_result;
  dmem_wdata  <= rs2_data;
  mem_rdata   <= dmem_rdata;

  -- Write-back
  with wb_sel select
    wb_data <= alu_result when WB_ALU,
               mem_rdata  when WB_MEM,
               pc_plus4   when WB_PC4;
end architecture;
