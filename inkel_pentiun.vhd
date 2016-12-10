LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;

ENTITY inkel_pentiun IS
	PORT(
		clk     : IN  STD_LOGIC;
		reset   : IN  STD_LOGIC;
		output  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
	);
end inkel_pentiun;

ARCHITECTURE structure OF inkel_pentiun IS
	COMPONENT mux2_1 IS
		PORT(
			DIn0 : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
			DIn1 : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
			ctrl : IN  STD_LOGIC;
			Dout : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT reg_status IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			we : IN STD_LOGIC;
			pc_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			status_in : IN STD_LOGIC;
			exc_in : IN STD_LOGIC;
			exc_code_in : IN STD_LOGIC_VECTOR(1 DOWNTO 0);
			exc_data_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			pc_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			status_out : OUT STD_LOGIC;
			exc_out : OUT STD_LOGIC;
			exc_code_out : OUT STD_LOGIC_VECTOR(1 DOWNTO 0);
			exc_data_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT memory IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			f_req : IN STD_LOGIC;
			d_req : IN STD_LOGIC;
			d_we : IN STD_LOGIC;
			f_done : OUT STD_LOGIC;
			d_done : OUT STD_LOGIC;
			f_addr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			d_addr : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			d_data_in : IN STD_LOGIC_VECTOR(127 DOWNTO 0);
			f_data_out : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
			d_data_out : OUT STD_LOGIC_VECTOR(127 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT pc IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			addr_jump : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			branch_taken_D : IN STD_LOGIC;
			load_PC : IN STD_LOGIC;
			pc : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT fetch IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			pc : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			branch_taken_D : IN STD_LOGIC;
			inst : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			inst_v : OUT STD_LOGIC;
			mem_req : OUT STD_LOGIC;
			mem_addr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			mem_done : IN STD_LOGIC;
			mem_data_in : IN STD_LOGIC_VECTOR(127 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT memoriaRAM_D IS
		PORT(
			CLK : IN STD_LOGIC;
			ADDR : IN STD_LOGIC_VECTOR (31 DOWNTO 0); --Dir
			Din : IN STD_LOGIC_VECTOR (31 DOWNTO 0);--entrada de datos para el puerto de escritura
			WE : IN STD_LOGIC;		-- write enable
			RE : IN STD_LOGIC;		-- read enable
			Dout : OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT reg_FD IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			we : IN STD_LOGIC;
			inst_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			inst_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT mux2_32bits IS
		PORT(
			DIn0 : IN  STD_LOGIC_VECTOR (31 DOWNTO 0);
			DIn1 : IN  STD_LOGIC_VECTOR (31 DOWNTO 0);
			ctrl : IN  STD_LOGIC;
			Dout : OUT  STD_LOGIC_VECTOR (31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT BReg IS
		PORT(
			clk : IN  STD_LOGIC;
			reset : IN  STD_LOGIC;
			RA : IN  STD_LOGIC_VECTOR(4 DOWNTO 0);
			RB : IN  STD_LOGIC_VECTOR(4 DOWNTO 0);
			RW : IN  STD_LOGIC_VECTOR(4 DOWNTO 0);
			BusW : IN  STD_LOGIC_VECTOR(31 DOWNTO 0);
			RegWrite : IN  STD_LOGIC;
			BusA : OUT  STD_LOGIC_VECTOR(31 DOWNTO 0);
			BusB : OUT  STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT decode IS
		PORT(
			inst : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			pc : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			op_code : OUT STD_LOGIC_VECTOR(6 DOWNTO 0);
			reg_src1 : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_src2 : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_dest : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			inm_ext : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			jump_addr : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			ALU_ctrl : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
			branch : OUT STD_LOGIC;
			jump : OUT STD_LOGIC;
			reg_src1_v : OUT STD_LOGIC;
			reg_src2_v : OUT STD_LOGIC;
			mul : OUT STD_LOGIC;
			mem_write : OUT STD_LOGIC;
			byte : OUT STD_LOGIC;
			mem_read : OUT STD_LOGIC;
			mem_to_reg : OUT STD_LOGIC;
			reg_we : OUT STD_LOGIC
		);
	END COMPONENT;

	COMPONENT bypass_unit IS
		PORT(
			reg_src1_A      : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_src2_A      : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_src1_v_A    : IN STD_LOGIC;
			reg_src2_v_A    : IN STD_LOGIC;
			reg_dest_C      : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_we_C        : IN STD_LOGIC;
			reg_dest_W      : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_we_W        : IN STD_LOGIC;
			mux_src1_BP     : OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			mux_src2_BP     : OUT STD_LOGIC_VECTOR (1 DOWNTO 0);
			mux_mem_data_BP : OUT STD_LOGIC_VECTOR (1 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT detention_unit IS
		PORT(
			reset          : IN STD_LOGIC;
			branch_taken_D : IN STD_LOGIC;
			reg_src1_D     : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_src2_D     : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_dest_D     : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			reg_src1_v_D   : IN STD_LOGIC;
			reg_src2_v_D   : IN STD_LOGIC;
			mem_we_D       : IN STD_LOGIC;
			reg_dest_A     : IN STD_LOGIC_VECTOR (4 DOWNTO 0);
			mem_read_A     : IN STD_LOGIC;
			mul_det_A      : IN STD_LOGIC;
			done_F         : IN STD_LOGIC;
			done_C         : IN STD_LOGIC;
			switch_ctrl    : OUT STD_LOGIC;
			reg_PC_reset   : OUT STD_LOGIC;
			reg_F_D_reset  : OUT STD_LOGIC;
			reg_D_A_reset  : OUT STD_LOGIC;
			reg_A_C_reset  : OUT STD_LOGIC;
			reg_C_W_reset  : OUT STD_LOGIC;
			reg_PC_we      : OUT STD_LOGIC;
			reg_F_D_we     : OUT STD_LOGIC;
			reg_D_A_we     : OUT STD_LOGIC;
			reg_A_C_we     : OUT STD_LOGIC;
			reg_C_W_we     : OUT STD_LOGIC
		);
	END COMPONENT;

	COMPONENT reg_DA IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			we : IN STD_LOGIC;
			mul_in : IN STD_LOGIC;
			mem_we_in : IN STD_LOGIC;
			byte_in : IN STD_LOGIC;
			mem_read_in : IN STD_LOGIC;
			mem_to_reg_in : IN STD_LOGIC;
			reg_we_in : IN STD_LOGIC;
			inm_ext_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			ALU_ctrl_in : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
			reg_src1_v_in : IN STD_LOGIC;
			reg_src2_v_in : IN STD_LOGIC;
			reg_src1_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_src2_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_dest_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_data1_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			reg_data2_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			mul_out : OUT STD_LOGIC;
			mem_we_out : OUT STD_LOGIC;
			byte_out : OUT STD_LOGIC;
			mem_read_out : OUT STD_LOGIC;
			mem_to_reg_out : OUT STD_LOGIC;
			reg_we_out : OUT STD_LOGIC;
			inm_ext_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			ALU_ctrl_out : OUT STD_LOGIC_VECTOR(2 DOWNTO 0);
			reg_src1_v_out : OUT STD_LOGIC;
			reg_src2_v_out : OUT STD_LOGIC;
			reg_src1_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_src2_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_dest_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			reg_data1_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			reg_data2_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT mux4_32bits IS
		PORT(
			DIn0 : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			DIn1 : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			DIn2 : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			DIn3 : IN STD_LOGIC_VECTOR (31 DOWNTO 0);
			ctrl : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
			Dout : OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT ALU IS
		PORT(
			DA : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			DB : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			ALUctrl : IN STD_LOGIC_VECTOR(2 DOWNTO 0);
			Dout : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT ALU_MUL IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			load : IN STD_LOGIC;
			DA : IN STD_LOGIC_VECTOR (31 downto 0); --entrada 1
			DB : IN STD_LOGIC_VECTOR (31 downto 0); --entrada 2
			--Counter : OUT STD_LOGIC_VECTOR(2 downto 0); --contador de los ciclos restantes para la multiplicacion
			Mul_ready : OUT STD_LOGIC;
			Dout : OUT STD_LOGIC_VECTOR (31 downto 0)
		);
	END COMPONENT;

	COMPONENT Switch_UD IS
		PORT(
			Reg_Write : IN STD_LOGIC;
			Mem_Read : IN STD_LOGIC;
			Byte : IN STD_LOGIC;
			Mem_Write : IN STD_LOGIC;
			MemtoReg : IN STD_LOGIC;
			ALU_Src_A : IN STD_LOGIC;
			ALU_Src_B : IN STD_LOGIC;
			Mul: IN STD_LOGIC;
			ctrl : IN STD_LOGIC;
			Reg_Write_out : OUT STD_LOGIC;
			Mem_Read_out : OUT STD_LOGIC;
			Byte_out : OUT STD_LOGIC;
			Mem_Write_out : OUT STD_LOGIC;
			MemtoReg_out : OUT STD_LOGIC;
			ALU_Src_A_out : OUT STD_LOGIC;
			ALU_Src_B_out : OUT STD_LOGIC;
			Mul_out : OUT STD_LOGIC
		);
	END COMPONENT;

	COMPONENT reg_AC IS
		PORT(
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			we : IN STD_LOGIC;
			mem_we_in : IN STD_LOGIC;
			byte_in : IN STD_LOGIC;
			mem_read_in : IN STD_LOGIC;
			mem_to_reg_in : IN STD_LOGIC;
			reg_we_in : IN STD_LOGIC;
			reg_dest_in : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
			ALU_out_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			mem_data_in : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			mem_we_out : OUT STD_LOGIC;
			byte_out : OUT STD_LOGIC;
			mem_read_out : OUT STD_LOGIC;
			mem_to_reg_out : OUT STD_LOGIC;
			reg_we_out : OUT STD_LOGIC;
			reg_dest_out : OUT STD_LOGIC_VECTOR(4 DOWNTO 0);
			ALU_out_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			mem_data_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT Banco_WB IS
		PORT(
			ALU_out_MEM : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			ALU_out_WB : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			MEM_out : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
			MDR : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
			clk : IN STD_LOGIC;
			reset : IN STD_LOGIC;
			load : IN STD_LOGIC;
			MemtoReg_MEM : IN STD_LOGIC;
			RegWrite_MEM : IN STD_LOGIC;
			MemtoReg_WB : OUT STD_LOGIC;
			RegWrite_WB : OUT STD_LOGIC;
			RW_MEM : IN STD_LOGIC_VECTOR(4 DOWNTO 0);
			RW_WB : OUT STD_LOGIC_VECTOR(4 DOWNTO 0)
		);
	END COMPONENT;

	-- Fetch stage signals
	SIGNAL inst_v_F : STD_LOGIC;
	SIGNAL mem_req_F : STD_LOGIC;
	SIGNAL mem_done_F : STD_LOGIC;
	SIGNAL pc_F : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inst_F : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL mem_addr_F : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL mem_data_in_F : STD_LOGIC_VECTOR(127 DOWNTO 0);

	-- Decode stage signals
	SIGNAL branch_D : STD_LOGIC;
	SIGNAL jump_D : STD_LOGIC;
	SIGNAL branch_taken_D : STD_LOGIC;
	SIGNAL reg_we_D : STD_LOGIC;
	SIGNAL mem_read_D : STD_LOGIC;
	SIGNAL byte_D : STD_LOGIC;
	SIGNAL mem_we_D : STD_LOGIC;
	SIGNAL mem_to_reg_D : STD_LOGIC;
	SIGNAL reg_src1_v_D : STD_LOGIC;
	SIGNAL reg_src2_v_D : STD_LOGIC;
	SIGNAL mul_D : STD_LOGIC;
	SIGNAL switch_ctrl : STD_LOGIC;
	SIGNAL Z : STD_LOGIC;
	SIGNAL ALU_ctrl_D : STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL reg_src1_D : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL reg_src2_D : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL reg_dest_D : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL op_code_D : STD_LOGIC_VECTOR(6 DOWNTO 0);
	SIGNAL inst_D : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL pc_D : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL jump_addr_D : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL reg_data1_D : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL reg_data2_D : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inm_ext_D : STD_LOGIC_VECTOR(31 DOWNTO 0);

	-- ALU stage signals
	SIGNAL mem_read_A : STD_LOGIC;
	SIGNAL mem_to_reg_A : STD_LOGIC;
	SIGNAL mul_det_A : STD_LOGIC;
	SIGNAL mul_ready_A : STD_LOGIC;
	SIGNAL mul_A : STD_LOGIC;
	SIGNAL reg_src1_v_A : STD_LOGIC;
	SIGNAL reg_src2_v_A : STD_LOGIC;
	SIGNAL mem_we_A : STD_LOGIC;
	SIGNAL byte_A : STD_LOGIC;
	SIGNAL reg_we_A : STD_LOGIC;
	SIGNAL ALU_ctrl_A : STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL reg_dest_A : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL reg_src1_A : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL reg_src2_A : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL pc_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL reg_data1_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL reg_data2_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inm_ext_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ALU_out_tmp : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ALU_out_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL mul_out_tmp : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL mem_data_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL data1_BP_A : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL data2_BP_A : STD_LOGIC_VECTOR(31 DOWNTO 0);

	-- Cache stage signals
	SIGNAL mem_we_C : STD_LOGIC;
	SIGNAL byte_C : STD_LOGIC;
	SIGNAL mem_read_C : STD_LOGIC;
	SIGNAL mem_to_reg_C : STD_LOGIC;
	SIGNAL reg_we_C : STD_LOGIC;
	SIGNAL reg_dest_C : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL pc_C : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ALU_out_C : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL data_in_C : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL data_out_C : STD_LOGIC_VECTOR(31 DOWNTO 0);

	-- Writeback stage signals
	SIGNAL reg_we_WB : STD_LOGIC;
	SIGNAL mem_to_reg_WB: STD_LOGIC;
	SIGNAL reg_dest_WB : STD_LOGIC_VECTOR(4 DOWNTO 0);
	SIGNAL reg_data_WB : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL mem_data_out_WB : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ALU_out_WB : STD_LOGIC_VECTOR(31 DOWNTO 0);

	-- Segmentation registers signals
	SIGNAL reg_F_D_reset : STD_LOGIC;
	SIGNAL reg_D_A_reset : STD_LOGIC;
	SIGNAL reg_A_C_reset : STD_LOGIC;
	SIGNAL reg_C_W_reset : STD_LOGIC;
	SIGNAL reg_F_D_we : STD_LOGIC;
	SIGNAL reg_D_A_we : STD_LOGIC;
	SIGNAL reg_A_C_we : STD_LOGIC;
	SIGNAL reg_C_W_we : STD_LOGIC;

	-- Stall unit signals
	SIGNAL load_PC : STD_LOGIC;
	SIGNAL reset_PC : STD_LOGIC;
	SIGNAL mem_read_UD : STD_LOGIC;
	SIGNAL byte_UD : STD_LOGIC;
	SIGNAL mem_we_UD : STD_LOGIC;
	SIGNAL mem_to_reg_UD : STD_LOGIC;
	SIGNAL reg_src1_v_UD : STD_LOGIC;
	SIGNAL reg_src2_v_UD : STD_LOGIC;
	SIGNAL reg_we_UD : STD_LOGIC;
	SIGNAL mul_UD : STD_LOGIC;

	-- Bypass unit signals
	SIGNAL mux_src1_BP : STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL mux_src2_BP : STD_LOGIC_VECTOR(1 DOWNTO 0);
	SIGNAL mux_mem_data_BP : STD_LOGIC_VECTOR(1 DOWNTO 0);

BEGIN

	----------------------------- Fetch -------------------------------

	reg_pc: pc PORT MAP(
		clk => clk,
		reset => reset_PC,
		addr_jump => jump_addr_D,
		branch_taken_D => branch_taken_D,
		load_PC => load_PC,
		pc => pc_F
	);

	mem: memory PORT MAP(
		clk => clk,
		reset => reset,
		f_req => mem_req_F,
		d_req => '0',
		d_we => '0',
		f_done => mem_done_F,
		d_done => open, -- Unused output
		f_addr => mem_addr_F,
		d_addr => (OTHERS => 'Z'),
		d_data_in => (OTHERS => 'Z'),
		f_data_out => mem_data_in_F,
		d_data_out => open -- Unusued output
	);

	f: fetch PORT MAP(
		clk => clk,
		reset => reset,
		pc => pc_F,
		branch_taken_D => branch_taken_D,
		inst => inst_F,
		inst_v => inst_v_F,
		mem_req => mem_req_F,
		mem_addr => mem_addr_F,
		mem_done => mem_done_F,
		mem_data_in => mem_data_in_F
	);

	reg_F_D: reg_FD PORT MAP(
		clk => clk,
		reset => reg_F_D_reset,
		we => reg_F_D_we,
		inst_in => inst_F,
		inst_out => inst_D
	);

	reg_status_F_D: reg_status PORT MAP(
		clk => clk,
		reset => reg_F_D_reset,
		we => reg_F_D_we,
		pc_in => pc_F,
		status_in => '0',
		exc_in => '0',
		exc_code_in => (OTHERS => '0'),
		exc_data_in => (OTHERS => '0'),
		pc_out => pc_D,
		status_out => open,
		exc_out => open,
		exc_code_out => open,
		exc_data_out => open
	);

	----------------------------- Decode -------------------------------

	UD : detention_unit PORT MAP(
		reset => reset,
		branch_taken_D => branch_taken_D,
		reg_src1_D => reg_src1_D,
		reg_src2_D => reg_src2_D,
		reg_dest_D => reg_dest_D,
		reg_src1_v_D => reg_src1_v_D,
		reg_src2_v_D => reg_src2_v_D,
		mem_we_D => mem_we_D,
		reg_dest_A => reg_dest_A,
		mem_read_A => mem_read_A,
		mul_det_A => mul_det_A,
		done_F => inst_v_F,
		done_C => '1',
		switch_ctrl => switch_ctrl,
		reg_PC_reset => reset_PC,
		reg_F_D_reset => reg_F_D_reset,
		reg_D_A_reset => reg_D_A_reset,
		reg_A_C_reset => reg_A_C_reset,
		reg_C_W_reset => reg_C_W_reset,
		reg_PC_we => load_PC,
		reg_F_D_we => reg_F_D_we,
		reg_D_A_we => reg_D_A_we,
		reg_A_C_we => reg_A_C_we,
		reg_C_W_we => reg_C_W_we
	);

	d: decode PORT MAP(
		inst => inst_D,
		pc => pc_D,
		op_code => op_code_D,
		reg_src1 => reg_src1_D,
		reg_src2 => reg_src2_D,
		reg_dest => reg_dest_D,
		inm_ext => inm_ext_D,
		jump_addr => jump_addr_D,
		ALU_ctrl => ALU_ctrl_D,
		branch => branch_D,
		jump => jump_D,
		reg_src1_v => reg_src1_v_D,
		reg_src2_v => reg_src2_v_D,
		mul => mul_D,
		mem_write => mem_we_D,
		byte => byte_D,
		mem_read => mem_read_D,
		mem_to_reg => mem_to_reg_D,
		reg_we => reg_we_D
	);

	Switch_det: Switch_UD PORT MAP(
		Reg_Write => reg_we_D,
		Mem_Read => mem_read_D,
		Byte => byte_D,
		Mem_Write => mem_we_D,
		MemtoReg => mem_to_reg_D,
		ALU_Src_A => reg_src1_v_D,
		ALU_Src_B => reg_src2_v_D,
		Mul => mul_D,
		ctrl => switch_ctrl,
		Reg_Write_out => reg_we_UD,
		Mem_Read_out => mem_read_UD,
		Byte_out => byte_UD,
		Mem_Write_out => mem_we_UD,
		MemtoReg_out => mem_to_reg_UD,
		ALU_Src_A_out => reg_src1_v_UD,
		ALU_Src_B_out => reg_src2_v_UD,
		Mul_out => mul_UD
	);

	Register_bank: BReg PORT MAP(
		clk => clk,
		reset => reset,
		RA => reg_src1_D,
		RB => reg_src2_D,
		RW => reg_dest_WB,
		BusW => reg_data_WB,
		RegWrite => reg_we_WB,
		BusA => reg_data1_D,
		BusB => reg_data2_D
	);

	Z <= '1' WHEN (reg_data1_D = reg_data2_D) ELSE '0';
	branch_taken_D <= (Z AND branch_D) OR jump_D;

	reg_D_A: reg_DA PORT MAP(
		clk => clk,
		reset => reg_D_A_reset,
		we => reg_D_A_we,
		mul_in => mul_UD,
		mem_we_in => mem_we_UD,
		byte_in => byte_UD,
		mem_read_in => mem_read_UD,
		mem_to_reg_in => mem_to_reg_UD,
		reg_we_in => reg_we_UD,
		inm_ext_in => inm_ext_D,
		ALU_ctrl_in => ALU_ctrl_D,
		reg_src1_v_in => reg_src1_v_UD,
		reg_src2_v_in => reg_src2_v_UD,
		reg_src1_in => reg_src1_D,
		reg_src2_in => reg_src2_D,
		reg_dest_in => reg_dest_D,
		reg_data1_in => reg_data1_D,
		reg_data2_in => reg_data2_D,
		mul_out => mul_A,
		mem_we_out => mem_we_A,
		byte_out => byte_A,
		mem_read_out => mem_read_A,
		mem_to_reg_out => mem_to_reg_A,
		reg_we_out => reg_we_A,
		inm_ext_out => inm_ext_A,
		ALU_ctrl_out => ALU_ctrl_A,
		reg_src1_v_out => reg_src1_v_A,
		reg_src2_v_out => reg_src2_v_A,
		reg_src1_out => reg_src1_A,
		reg_src2_out => reg_src2_A,
		reg_dest_out => reg_dest_A,
		reg_data1_out => reg_data1_A,
		reg_data2_out => reg_data2_A
	);

	reg_status_D_A: reg_status PORT MAP(
		clk => clk,
		reset => reg_D_A_reset,
		we => reg_D_A_we,
		pc_in => pc_D,
		status_in => '0',
		exc_in => '0',
		exc_code_in => (OTHERS => '0'),
		exc_data_in => (OTHERS => '0'),
		pc_out => pc_A,
		status_out => open,
		exc_out => open,
		exc_code_out => open,
		exc_data_out => open
	);

	--------------------------------- Execution ------------------------------------------

	UB : bypass_unit PORT MAP(
		reg_src1_A => reg_src1_A,
		reg_src2_A => reg_src2_A,
		reg_src1_v_A => reg_src1_v_A,
		reg_src2_v_A => reg_src2_v_A,
		reg_dest_C => reg_dest_C,
		reg_we_C => reg_we_C,
		reg_dest_W => reg_dest_WB,
		reg_we_W => reg_we_WB,
		mux_src1_BP => mux_src1_BP,
		mux_src2_BP => mux_src2_BP,
		mux_mem_data_BP => mux_mem_data_BP
	);

	mux_a: mux4_32bits PORT MAP(
		Din0 => reg_data1_A,
		Din1 => reg_data_WB,
		Din2 => ALU_out_C,
		DIn3 => "00000000000000000000000000000000",
		ctrl => mux_src1_BP,
		Dout => data1_BP_A
	);

	mux_b: mux4_32bits PORT MAP(
		Din0 => reg_data2_A,
		Din1 => reg_data_WB,
		Din2 => ALU_out_C,
		DIn3 => inm_ext_A,
		ctrl => mux_src2_BP,
		Dout => data2_BP_A
	);

	ALU_MIPs: ALU PORT MAP(
		DA => data1_BP_A,
		DB => data2_BP_A,
		ALUctrl => ALU_ctrl_A,
		Dout => ALU_out_tmp
	);

	Mul_unit: ALU_MUL PORT MAP(
		clk => clk,
		reset => reset,
		load => mul_A,
		DA => data1_BP_A,
		DB => data2_BP_A,
		--Counter => Mul_counter,
		Mul_ready => mul_ready_A,
		Dout => mul_out_tmp
	);

	mux_alu: mux2_32bits PORT MAP(
		Din0 => ALU_out_tmp,
		Din1 => mul_out_tmp,
		ctrl => mul_A,
		Dout => ALU_out_A
	);

	mux_c : mux4_32bits PORT MAP(
		Din0 => reg_data2_A,
		Din1 => reg_data_WB,
		Din2 => ALU_out_C,
		DIn3 => "00000000000000000000000000000000",
		ctrl => mux_mem_data_BP,
		Dout => mem_data_A
	);

	mul_det_A <= mul_A AND NOT(mul_ready_A);

	reg_A_C: reg_AC PORT MAP(
		clk => clk,
		reset => reg_A_C_reset,
		we => reg_A_C_we,
		mem_we_in => mem_we_A,
		byte_in => byte_A,
		mem_read_in => mem_read_A,
		mem_to_reg_in => mem_to_reg_A,
		reg_we_in => reg_we_A,
		reg_dest_in => reg_dest_A,
		ALU_out_in => ALU_out_A,
		mem_data_in => mem_data_A,
		mem_we_out => mem_we_C,
		byte_out => byte_C,
		mem_read_out => mem_read_C,
		mem_to_reg_out => mem_to_reg_C,
		reg_we_out => reg_we_C,
		reg_dest_out => reg_dest_C,
		ALU_out_out => ALU_out_C,
		mem_data_out => data_in_C
	);

	reg_status_A_C: reg_status PORT MAP(
		clk => clk,
		reset => reg_A_C_reset,
		we => reg_A_C_we,
		pc_in => pc_A,
		status_in => '0',
		exc_in => '0',
		exc_code_in => (OTHERS => '0'),
		exc_data_in => (OTHERS => '0'),
		pc_out => pc_C,
		status_out => open,
		exc_out => open,
		exc_code_out => open,
		exc_data_out => open
	);

	-------------------------------- Memory  ----------------------------------------------

	Mem_D: memoriaRAM_D PORT MAP(
		CLK => CLK,
		ADDR => ALU_out_C,
		Din => data_in_C,
		WE => mem_we_C,
		RE => mem_read_C,
		Dout => data_out_C
	);

	Banco_MEM_WB: Banco_WB PORT MAP(
		ALU_out_MEM => ALU_out_C,
		ALU_out_WB => ALU_out_WB,
		Mem_out => data_out_C,
		MDR => mem_data_out_WB,
		clk => clk,
		reset => reg_C_W_reset,
		load => reg_C_W_we,
		MemtoReg_MEM => mem_to_reg_C,
		RegWrite_MEM => reg_we_C,
		MemtoReg_WB => mem_to_reg_WB,
		RegWrite_WB => reg_we_WB,
		RW_MEM => reg_dest_C,
		RW_WB => reg_dest_WB
	);

	mux_busW: mux2_1 PORT map(
		Din0 => ALU_out_WB,
		DIn1 => mem_data_out_WB,
		ctrl => mem_to_reg_WB,
		Dout => reg_data_WB
	);

	output <= inst_D;

END structure;

