package alu_pkg is
  type alu_op_t is (ALU_ADD, ALU_SUB, ALU_AND, ALU_OR, ALU_XOR,
                    ALU_SLL, ALU_SRL, ALU_SRA, ALU_SLT, ALU_SLTU);
end package;