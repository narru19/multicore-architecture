LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE WORK.UTILS.ALL;

ENTITY inkel_pentwice IS
	PORT(
		clk    : IN STD_LOGIC;
		reset  : IN STD_LOGIC
	);
END inkel_pentwice;

ARCHITECTURE structure OF inkel_pentwice IS
	COMPONENT inkel_pentiun IS
		GENERIC (
			proc_id : INTEGER
		);
		PORT (
			clk           : IN    STD_LOGIC;
			reset         : IN    STD_LOGIC;
			debug_dump    : IN    STD_LOGIC;
			done_inv      : OUT   STD_LOGIC;
			i_arb_req     : OUT   STD_LOGIC;
			d_arb_req     : OUT   STD_LOGIC;
			i_arb_ack     : IN    STD_LOGIC;
			d_arb_ack     : IN    STD_LOGIC;
			bus_cmd       : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
			bus_addr      : INOUT STD_LOGIC_VECTOR(31  DOWNTO 0);
			bus_done      : INOUT STD_LOGIC;
			bus_force_inv : INOUT STD_LOGIC;
			bus_c2c       : INOUT STD_LOGIC;
			bus_data      : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
			pc_out        : OUT   STD_LOGIC_VECTOR(31  DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT memory IS
		PORT (
			clk        : IN    STD_LOGIC;
			reset      : IN    STD_LOGIC;
			debug_dump : IN    STD_LOGIC;
			cmd        : IN    STD_LOGIC_VECTOR(2 DOWNTO 0);
			done       : OUT   STD_LOGIC;
			addr       : IN    STD_LOGIC_VECTOR(31  DOWNTO 0);
			data       : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0)
		);
	END COMPONENT;

	COMPONENT arbiter IS
		PORT (
			clk       : IN  STD_LOGIC;
			reset     : IN  STD_LOGIC;
			llc_done  : IN  STD_LOGIC;
			req_one_i : IN  STD_LOGIC;
			req_two_i : IN  STD_LOGIC;
			req_one_d : IN  STD_LOGIC;
			req_two_d : IN  STD_LOGIC;
			ack_one_i : OUT STD_LOGIC;
			ack_two_i : OUT STD_LOGIC;
			ack_one_d : OUT STD_LOGIC;
			ack_two_d : OUT STD_LOGIC;
			req_llc   : IN  STD_LOGIC;
			ack_llc   : OUT STD_LOGIC
		);
	END COMPONENT;
	
	COMPONENT cache_last_level IS
	PORT (
		clk             : IN    STD_LOGIC;
		reset           : IN    STD_LOGIC;
		cache0_done_inv : IN    STD_LOGIC;                      -- LLC-L1 direct signals
		cache1_done_inv : IN    STD_LOGIC;
		bus_done        : INOUT STD_LOGIC;                      -- LLC-L1 bus signals
		bus_force_inv   : INOUT STD_LOGIC;
		bus_c2c         : INOUT STD_LOGIC;
		bus_cmd         : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		bus_addr        : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		bus_data        : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		mem_done        : IN    STD_LOGIC;                      -- LLC-Mem signals
		mem_cmd         : OUT   STD_LOGIC_VECTOR(2 DOWNTO 0);
		mem_addr        : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		mem_data        : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		arb_req         : OUT   STD_LOGIC;
		arb_ack         : IN    STD_LOGIC
	);
	END COMPONENT;

	SIGNAL cmd_MEM  : STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL addr_MEM : STD_LOGIC_VECTOR(31  DOWNTO 0);
	SIGNAL done_MEM : STD_LOGIC;
	SIGNAL data_MEM : STD_LOGIC_VECTOR(127 DOWNTO 0);
	
	SIGNAL cmd_BUS       : STD_LOGIC_VECTOR(2 DOWNTO 0);
	SIGNAL addr_BUS      : STD_LOGIC_VECTOR(31  DOWNTO 0);
	SIGNAL done_BUS      : STD_LOGIC;
	SIGNAL force_inv_BUS : STD_LOGIC;
	SIGNAL c2c_BUS       : STD_LOGIC;
	SIGNAL data_BUS      : STD_LOGIC_VECTOR(127 DOWNTO 0);
	
	SIGNAL req_one_i_ARB : STD_LOGIC;
	SIGNAL req_one_d_ARB : STD_LOGIC;
	SIGNAL ack_one_i_ARB : STD_LOGIC;
	SIGNAL ack_one_d_ARB : STD_LOGIC;
	SIGNAL req_two_i_ARB : STD_LOGIC;
	SIGNAL req_two_d_ARB : STD_LOGIC;
	SIGNAL ack_two_i_ARB : STD_LOGIC;
	SIGNAL ack_two_d_ARB : STD_LOGIC;
	SIGNAL req_llc_ARB   : STD_LOGIC;
	SIGNAL ack_llc_ARB   : STD_LOGIC;
	
	SIGNAL done_inv_P0 : STD_LOGIC;
	SIGNAL done_inv_P1 : STD_LOGIC;
	
	SIGNAL debug_dump : STD_LOGIC;

	BEGIN
		mem : memory PORT MAP (
			clk        => clk,
			reset      => reset,
			debug_dump => debug_dump,
			cmd        => cmd_MEM,
			done       => done_MEM,
			addr       => addr_MEM,
			data       => data_MEM
		);

		arb : arbiter PORT MAP (
			clk       => clk,
			reset     => reset,
			llc_done  => done_BUS,
			req_one_i => req_one_i_ARB,
			req_one_d => req_one_d_ARB,
			ack_one_i => ack_one_i_ARB,
			ack_one_d => ack_one_d_ARB,
			req_two_i => req_two_i_ARB,
			req_two_d => req_two_d_ARB,
			ack_two_i => ack_two_i_ARB,
			ack_two_d => ack_two_d_ARB,
			req_llc   => req_llc_ARB,
			ack_llc   => ack_llc_ARB
		);

		llc : cache_last_level PORT MAP (
			clk             => clk,
			reset           => reset,
			cache0_done_inv => done_inv_P0,
			cache1_done_inv => done_inv_P1,
			bus_done        => done_BUS,
			bus_force_inv   => force_inv_BUS,
			bus_c2c         => c2c_BUS,
			bus_cmd         => cmd_BUS,
			bus_addr        => addr_BUS,
			bus_data        => data_BUS,
			mem_done        => done_MEM,
			mem_cmd         => cmd_MEM,
			mem_addr        => addr_MEM,
			mem_data        => data_MEM,
			arb_req         => req_llc_ARB,
			arb_ack         => ack_llc_ARB
		);

		proc0 : inkel_pentiun
			GENERIC MAP (proc_id => 0)
			PORT MAP (
				clk           => clk,
				reset         => reset,
				debug_dump    => debug_dump,
				done_inv      => done_inv_P0,
				i_arb_req     => req_one_i_ARB,
				d_arb_req     => req_one_d_ARB,
				i_arb_ack     => ack_one_i_ARB,
				d_arb_ack     => ack_one_d_ARB,
				bus_cmd       => cmd_BUS,
				bus_addr      => addr_BUS,
				bus_done      => done_BUS,
				bus_force_inv => force_inv_BUS,
				bus_c2c       => c2c_BUS,
				bus_data      => data_BUS,
				pc_out        => OPEN
		);

		proc1 : inkel_pentiun
			GENERIC MAP (proc_id => 1)
			PORT MAP (
				clk           => clk,
				reset         => reset,
				debug_dump    => debug_dump,
				done_inv      => done_inv_P1,
				i_arb_req     => req_two_i_ARB,
				d_arb_req     => req_two_d_ARB,
				i_arb_ack     => ack_two_i_ARB,
				d_arb_ack     => ack_two_d_ARB,
				bus_cmd       => cmd_BUS,
				bus_addr      => addr_BUS,
				bus_done      => done_BUS,
				bus_force_inv => force_inv_BUS,
				bus_c2c       => c2c_BUS,
				bus_data      => data_BUS,
				pc_out        => OPEN
		);

		debug_dump <= '0';

END structure;
