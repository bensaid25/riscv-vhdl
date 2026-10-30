library ieee;
use ieee.std_logic_1164.all;
use work.alu_pkg.all;
use work.ctrl_pkg.all;

entity control is
  port (
    opcode    : in  std_logic_vector(6 downto 0);
    funct3    : in  std_logic_vector(2 downto 0);
    funct7b5  : in  std_logic;                 -- instr(30)
    reg_write : out std_logic;
    a_sel     : out std_logic;                 -- 0 = rs1, 1 = pc
    b_sel     : out std_logic;                 -- 0 = rs2, 1 = imm
    alu_op    : out alu_op_t;
    mem_read  : out std_logic;
    mem_write : out std_logic;
    wb_sel    : out wb_sel_t;
    branch    : out std_logic;
    jal       : out std_logic;
    jalr      : out std_logic
  );
end entity;

architecture rtl of control is
  -- ALU operation for OP and OP-IMM instructions
  function arith_op(f3   : std_logic_vector(2 downto 0);
                    alt  : std_logic;          -- instr(30)
                    is_r : boolean) return alu_op_t is
  begin
    case f3 is
      when "000" =>
        if is_r and alt = '1' then return ALU_SUB; else return ALU_ADD; end if;
      when "001" => return ALU_SLL;
      when "010" => return ALU_SLT;
      when "011" => return ALU_SLTU;
      when "100" => return ALU_XOR;
      when "101" =>
        if alt = '1' then return ALU_SRA; else return ALU_SRL; end if;
      when "110" => return ALU_OR;
      when others => return ALU_AND;           -- "111"
    end case;
  end function;
begin
  process(all)
  begin
    -- safe defaults: nothing is written, nothing is taken
    reg_write <= '0';  a_sel <= '0';  b_sel <= '0';  alu_op <= ALU_ADD;
    mem_read  <= '0';  mem_write <= '0';  wb_sel <= WB_ALU;
    branch    <= '0';  jal <= '0';  jalr <= '0';

    case opcode is
      when "0110011" =>                        -- OP
        reg_write <= '1';
        alu_op    <= arith_op(funct3, funct7b5, true);
      when "0010011" =>                        -- OP-IMM
        reg_write <= '1';  b_sel <= '1';
        alu_op    <= arith_op(funct3, funct7b5, false);
      when "0000011" =>                        -- LOAD
        reg_write <= '1';  b_sel <= '1';
        mem_read  <= '1';  wb_sel <= WB_MEM;
      when "0100011" =>                        -- STORE
        b_sel <= '1';  mem_write <= '1';
      when "1100011" =>                        -- BRANCH
        branch <= '1';
        case funct3 is
          when "000" | "001" => alu_op <= ALU_SUB;    -- BEQ, BNE
          when "100" | "101" => alu_op <= ALU_SLT;    -- BLT, BGE
          when others        => alu_op <= ALU_SLTU;   -- BLTU, BGEU
        end case;
      when "0110111" =>                        -- LUI
        reg_write <= '1';  b_sel <= '1';  alu_op <= ALU_COPYB;
      when "0010111" =>                        -- AUIPC
        reg_write <= '1';  a_sel <= '1';  b_sel <= '1';
      when "1101111" =>                        -- JAL
        reg_write <= '1';  jal <= '1';  wb_sel <= WB_PC4;
      when "1100111" =>                        -- JALR
        reg_write <= '1';  b_sel <= '1';  jalr <= '1';  wb_sel <= WB_PC4;
      when others =>
        null;                                  -- illegal: defaults apply
    end case;
  end process;
end architecture;