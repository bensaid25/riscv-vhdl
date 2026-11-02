library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.alu_pkg.all;
use work.ctrl_pkg.all;

-- Five-stage pipeline: forwarding and load-use stall; no branch flush yet.
-- Same ports as cpu_core.
entity cpu_pipe is
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;                       -- synchronous, active high
    imem_addr   : out std_logic_vector(31 downto 0);
    imem_instr  : in  std_logic_vector(31 downto 0);
    dmem_we     : out std_logic;
    dmem_re     : out std_logic;
    dmem_funct3 : out std_logic_vector(2 downto 0);
    dmem_addr   : out std_logic_vector(31 downto 0);
    dmem_wdata  : out std_logic_vector(31 downto 0);
    dmem_rdata  : in  std_logic_vector(31 downto 0);
    dbg_raddr   : in  std_logic_vector(4 downto 0) := (others => '0');
    dbg_rdata   : out std_logic_vector(31 downto 0)
  );
end entity;

architecture rtl of cpu_pipe is
  subtype word is std_logic_vector(31 downto 0);
  subtype reg_t is std_logic_vector(4 downto 0);

  type id_ex_t is record
    pc, rs1_data, rs2_data, imm : word;
    rs1, rs2, rd                : reg_t;
    funct3                      : std_logic_vector(2 downto 0);
    reg_write, a_sel, b_sel     : std_logic;
    mem_read, mem_write         : std_logic;
    branch, jal, jalr           : std_logic;
    alu_op                      : alu_op_t;
    wb_sel                      : wb_sel_t;
  end record;

  type ex_mem_t is record
    alu_result, rs2_data, pc4 : word;
    rd                        : reg_t;
    funct3                    : std_logic_vector(2 downto 0);
    reg_write                 : std_logic;
    mem_read, mem_write       : std_logic;
    wb_sel                    : wb_sel_t;
  end record;

  type mem_wb_t is record
    alu_result, mem_rdata, pc4 : word;
    rd                         : reg_t;
    reg_write                  : std_logic;
    wb_sel                     : wb_sel_t;
  end record;

  constant NOP : word  := x"00000013";            -- addi x0,x0,0
  constant Z32 : word  := (others => '0');
  constant Z5  : reg_t := (others => '0');

  constant ID_EX_BUBBLE : id_ex_t := (
    pc => Z32, rs1_data => Z32, rs2_data => Z32, imm => Z32,
    rs1 => Z5, rs2 => Z5, rd => Z5, funct3 => "000",
    reg_write => '0', a_sel => '0', b_sel => '0', mem_read => '0', mem_write => '0',
    branch => '0', jal => '0', jalr => '0', alu_op => ALU_ADD, wb_sel => WB_ALU);
  constant EX_MEM_BUBBLE : ex_mem_t := (
    alu_result => Z32, rs2_data => Z32, pc4 => Z32, rd => Z5, funct3 => "000",
    reg_write => '0', mem_read => '0', mem_write => '0', wb_sel => WB_ALU);
  constant MEM_WB_BUBBLE : mem_wb_t := (
    alu_result => Z32, mem_rdata => Z32, pc4 => Z32, rd => Z5,
    reg_write => '0', wb_sel => WB_ALU);

  -- IF
  signal pc, pc_plus4_if, next_pc : word := (others => '0');
  -- IF/ID
  signal ifid_pc    : word := (others => '0');
  signal ifid_instr : word := NOP;
  -- ID
  signal imm_id, rs1_id, rs2_id : word;
  signal c_reg_write, c_a_sel, c_b_sel, c_mem_read, c_mem_write : std_logic;
  signal c_branch, c_jal, c_jalr : std_logic;
  signal c_alu_op : alu_op_t;
  signal c_wb_sel : wb_sel_t;
  -- pipeline registers
  signal idex  : id_ex_t  := ID_EX_BUBBLE;
  signal exmem : ex_mem_t := EX_MEM_BUBBLE;
  signal memwb : mem_wb_t := MEM_WB_BUBBLE;
  -- EX
  signal alu_a, alu_b, alu_result, pc_target, pc4_ex, redirect_target : word;
  signal zero, take_branch, ex_redirect : std_logic;
  signal stall, uses_rs1, uses_rs2      : std_logic;
  signal fwd_a, fwd_b              : std_logic_vector(1 downto 0);
  signal exmem_val, rs1_ex, rs2_ex : word;
  -- WB
  signal wb_data : word;
  signal rf_we   : std_logic;
begin
  ------------------------------------------------------------------ IF
  pc_plus4_if <= std_logic_vector(unsigned(pc) + 4);
  next_pc     <= redirect_target when ex_redirect = '1' else pc_plus4_if;
  imem_addr   <= pc;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        pc <= (others => '0');
      elsif stall = '0' then
        pc <= next_pc;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ifid_pc    <= (others => '0');
        ifid_instr <= NOP;
      elsif stall = '0' then
        ifid_pc    <= pc;
        ifid_instr <= imem_instr;
      end if;
    end if;
  end process;

  ------------------------------------------------------------------ ID
  u_ctrl : entity work.control
    port map (opcode => ifid_instr(6 downto 0), funct3 => ifid_instr(14 downto 12),
              funct7b5 => ifid_instr(30),
              reg_write => c_reg_write, a_sel => c_a_sel, b_sel => c_b_sel,
              alu_op => c_alu_op, mem_read => c_mem_read, mem_write => c_mem_write,
              wb_sel => c_wb_sel, branch => c_branch, jal => c_jal, jalr => c_jalr);

  u_imm : entity work.immgen
    port map (instr => ifid_instr, imm => imm_id);

  -- Load-use hazard: the load in EX has no data yet, so a consumer in ID waits one cycle
  -- (PC and IF/ID hold, ID/EX gets a bubble); forwarding then supplies the value.
  uses_rs1 <= '0' when ifid_instr(6 downto 0) = "0110111"      -- lui
                    or ifid_instr(6 downto 0) = "0010111"      -- auipc
                    or ifid_instr(6 downto 0) = "1101111"      -- jal
              else '1';
  uses_rs2 <= '1' when ifid_instr(6 downto 0) = "0110011"      -- register-register
                    or ifid_instr(6 downto 0) = "0100011"      -- store
                    or ifid_instr(6 downto 0) = "1100011"      -- branch
              else '0';
  stall <= '1' when idex.mem_read = '1' and idex.rd /= "00000" and
                    ((uses_rs1 = '1' and idex.rd = ifid_instr(19 downto 15)) or
                     (uses_rs2 = '1' and idex.rd = ifid_instr(24 downto 20)))
           else '0';

  rf_we <= memwb.reg_write and not rst;

  u_rf : entity work.regfile
    generic map (BYPASS => true)
    port map (clk => clk, we => rf_we,
              waddr => memwb.rd, wdata => wb_data,
              raddr1 => ifid_instr(19 downto 15), raddr2 => ifid_instr(24 downto 20),
              rdata1 => rs1_id, rdata2 => rs2_id,
              dbg_addr => dbg_raddr, dbg_data => dbg_rdata);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        idex <= ID_EX_BUBBLE;
      elsif stall = '1' then
        idex <= ID_EX_BUBBLE;
      else
        idex <= (pc => ifid_pc, rs1_data => rs1_id, rs2_data => rs2_id, imm => imm_id,
                 rs1 => ifid_instr(19 downto 15), rs2 => ifid_instr(24 downto 20),
                 rd => ifid_instr(11 downto 7), funct3 => ifid_instr(14 downto 12),
                 reg_write => c_reg_write, a_sel => c_a_sel, b_sel => c_b_sel,
                 mem_read => c_mem_read, mem_write => c_mem_write,
                 branch => c_branch, jal => c_jal, jalr => c_jalr,
                 alu_op => c_alu_op, wb_sel => c_wb_sel);
      end if;
    end if;
  end process;

  ------------------------------------------------------------------ EX
  u_fwd : entity work.forward_unit
    port map (rs1 => idex.rs1, rs2 => idex.rs2,
              exmem_rd => exmem.rd, exmem_reg_write => exmem.reg_write,
              memwb_rd => memwb.rd, memwb_reg_write => memwb.reg_write,
              fwd_a => fwd_a, fwd_b => fwd_b);

  -- value an instruction in MEM will write back. A load's data is not available
  -- here: the load-use stall keeps a consumer from needing it.
  exmem_val <= exmem.pc4 when exmem.wb_sel = WB_PC4 else exmem.alu_result;

  with fwd_a select
    rs1_ex <= exmem_val     when "01",
              wb_data       when "10",
              idex.rs1_data when others;
  with fwd_b select
    rs2_ex <= exmem_val     when "01",
              wb_data       when "10",
              idex.rs2_data when others;

  alu_a <= idex.pc  when idex.a_sel = '1' else rs1_ex;
  alu_b <= idex.imm when idex.b_sel = '1' else rs2_ex;

  u_alu : entity work.alu
    port map (a => alu_a, b => alu_b, op => idex.alu_op, result => alu_result, zero => zero);

  u_br : entity work.branch_unit
    port map (branch => idex.branch, funct3 => idex.funct3,
              zero => zero, lt => alu_result(0), take_branch => take_branch);

  pc_target <= std_logic_vector(unsigned(idex.pc) + unsigned(idex.imm));
  pc4_ex    <= std_logic_vector(unsigned(idex.pc) + 4);

  ex_redirect     <= idex.jalr or idex.jal or take_branch;
  redirect_target <= (alu_result(31 downto 1) & '0') when idex.jalr = '1' else pc_target;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        exmem <= EX_MEM_BUBBLE;
      else
        exmem <= (alu_result => alu_result, rs2_data => rs2_ex, pc4 => pc4_ex,
                  rd => idex.rd, funct3 => idex.funct3, reg_write => idex.reg_write,
                  mem_read => idex.mem_read, mem_write => idex.mem_write,
                  wb_sel => idex.wb_sel);
      end if;
    end if;
  end process;

  ------------------------------------------------------------------ MEM
  dmem_we     <= exmem.mem_write and not rst;
  dmem_re     <= exmem.mem_read;
  dmem_funct3 <= exmem.funct3;
  dmem_addr   <= exmem.alu_result;
  dmem_wdata  <= exmem.rs2_data;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        memwb <= MEM_WB_BUBBLE;
      else
        memwb <= (alu_result => exmem.alu_result, mem_rdata => dmem_rdata, pc4 => exmem.pc4,
                  rd => exmem.rd, reg_write => exmem.reg_write, wb_sel => exmem.wb_sel);
      end if;
    end if;
  end process;

  ------------------------------------------------------------------ WB
  with memwb.wb_sel select
    wb_data <= memwb.alu_result when WB_ALU,
               memwb.mem_rdata  when WB_MEM,
               memwb.pc4        when WB_PC4;
end architecture;
