library ieee;
use ieee.std_logic_1164.all;
use work.alu_pkg.all;
use work.ctrl_pkg.all;

entity control_tb is end entity;

architecture sim of control_tb is
  signal opcode    : std_logic_vector(6 downto 0) := (others => '0');
  signal funct3    : std_logic_vector(2 downto 0) := (others => '0');
  signal funct7b5  : std_logic := '0';
  signal reg_write, a_sel, b_sel, mem_read, mem_write, branch, jal, jalr : std_logic;
  signal alu_op    : alu_op_t;
  signal wb_sel    : wb_sel_t;
begin
  dut: entity work.control
    port map (opcode => opcode, funct3 => funct3, funct7b5 => funct7b5,
              reg_write => reg_write, a_sel => a_sel, b_sel => b_sel,
              alu_op => alu_op, mem_read => mem_read, mem_write => mem_write,
              wb_sel => wb_sel, branch => branch, jal => jal, jalr => jalr);

  stim: process
    procedure check(constant name : in string;
                    constant opc  : in std_logic_vector(6 downto 0);
                    constant f3   : in std_logic_vector(2 downto 0);
                    constant f7b5 : in std_logic;
                    constant e_rw, e_a, e_b : in std_logic;
                    constant e_op : in alu_op_t;
                    constant e_mr, e_mw : in std_logic;
                    constant e_wb : in wb_sel_t;
                    constant e_br, e_jal, e_jalr : in std_logic) is
    begin
      opcode <= opc;  funct3 <= f3;  funct7b5 <= f7b5;
      wait for 1 ns;
      assert reg_write = e_rw  report name & ": reg_write"  severity error;
      assert a_sel     = e_a   report name & ": a_sel"      severity error;
      assert b_sel     = e_b   report name & ": b_sel"      severity error;
      assert alu_op    = e_op  report name & ": alu_op is " & alu_op_t'image(alu_op) severity error;
      assert mem_read  = e_mr  report name & ": mem_read"   severity error;
      assert mem_write = e_mw  report name & ": mem_write"  severity error;
      assert wb_sel    = e_wb  report name & ": wb_sel"     severity error;
      assert branch    = e_br  report name & ": branch"     severity error;
      assert jal       = e_jal report name & ": jal"        severity error;
      assert jalr      = e_jalr report name & ": jalr"      severity error;
    end procedure;
  begin
    --    name       opcode     f3     b30  rw  a   b   alu_op     mr  mw  wb      br  jal jalr
    check("add",     "0110011", "000", '0', '1','0','0', ALU_ADD,  '0','0', WB_ALU, '0','0','0');
    check("sub",     "0110011", "000", '1', '1','0','0', ALU_SUB,  '0','0', WB_ALU, '0','0','0');
    check("srl",     "0110011", "101", '0', '1','0','0', ALU_SRL,  '0','0', WB_ALU, '0','0','0');
    check("sra",     "0110011", "101", '1', '1','0','0', ALU_SRA,  '0','0', WB_ALU, '0','0','0');
    check("addi",    "0010011", "000", '0', '1','0','1', ALU_ADD,  '0','0', WB_ALU, '0','0','0');
    check("addi b30","0010011", "000", '1', '1','0','1', ALU_ADD,  '0','0', WB_ALU, '0','0','0'); -- must NOT become SUB
    check("srai",    "0010011", "101", '1', '1','0','1', ALU_SRA,  '0','0', WB_ALU, '0','0','0');
    check("lw",      "0000011", "010", '0', '1','0','1', ALU_ADD,  '1','0', WB_MEM, '0','0','0');
    check("sw",      "0100011", "010", '0', '0','0','1', ALU_ADD,  '0','1', WB_ALU, '0','0','0');
    check("beq",     "1100011", "000", '0', '0','0','0', ALU_SUB,  '0','0', WB_ALU, '1','0','0');
    check("blt",     "1100011", "100", '0', '0','0','0', ALU_SLT,  '0','0', WB_ALU, '1','0','0');
    check("bgeu",    "1100011", "111", '0', '0','0','0', ALU_SLTU, '0','0', WB_ALU, '1','0','0');
    check("lui",     "0110111", "000", '0', '1','0','1', ALU_COPYB,'0','0', WB_ALU, '0','0','0');
    check("auipc",   "0010111", "000", '0', '1','1','1', ALU_ADD,  '0','0', WB_ALU, '0','0','0');
    check("jal",     "1101111", "000", '0', '1','0','0', ALU_ADD,  '0','0', WB_PC4, '0','1','0');
    check("jalr",    "1100111", "000", '0', '1','0','1', ALU_ADD,  '0','0', WB_PC4, '0','0','1');
    check("illegal", "0000000", "000", '0', '0','0','0', ALU_ADD,  '0','0', WB_ALU, '0','0','0');

    report "control_tb finished";
    wait;
  end process;
end architecture;