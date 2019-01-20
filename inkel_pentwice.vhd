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
			clk            : IN    STD_LOGIC;
			reset          : IN    STD_LOGIC;
			debug_dump     : IN    STD_LOGIC;
			done_inv       : OUT   STD_LOGIC;
			i_arb_req      : OUT   STD_LOGIC;
			d_arb_req      : OUT   STD_LOGIC;
			i_arb_ack      : IN    STD_LOGIC;
			d_arb_ack      : IN    STD_LOGIC;
			bus_cmd        : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
			bus_addr       : INOUT STD_LOGIC_VECTOR(31  DOWNTO 0);
			bus_done       : INOUT STD_LOGIC;
			bus_force_inv  : INOUT STD_LOGIC;
			bus_c2c        : INOUT STD_LOGIC;
			bus_data       : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
			pc_out         : OUT   STD_LOGIC_VECTOR(31  DOWNTO 0);
			dir_addr       : OUT   STD_LOGIC_VECTOR(31  DOWNTO 0);
			dir_we         : OUT   STD_LOGIC;
			dir_re         : OUT   STD_LOGIC;
			dir_evict      : OUT   STD_LOGIC;
			dir_evict_addr : OUT   STD_LOGIC_VECTOR(31  DOWNTO 0);
			dir_ack        : IN    STD_LOGIC;
			dir_inv        : IN    STD_LOGIC;
			dir_inv_llc    : IN    STD_LOGIC;
			dir_inv_addr   : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
			dir_inv_ack    : OUT   STD_LOGIC;
			dir_c2c        : IN    STD_LOGIC;
			dir_c2c_addr   : IN    STD_LOGIC_VECTOR(31 DOWNTO 0)
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
		arb_ack         : IN    STD_LOGIC;
		dir_inv         : IN    STD_LOGIC;
		dir_inv_addr    : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		dir_inv_ack     : OUT   STD_LOGIC;
		dir_evict       : OUT   STD_LOGIC;
		dir_addr        : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		dir_c2c         : IN    STD_LOGIC;
		dir_ack         : IN    STD_LOGIC
	);
	END COMPONENT;

	COMPONENT directory IS
	PORT(
		clk            : IN    STD_LOGIC;
		reset          : IN    STD_LOGIC;
		addr_one       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		we_one         : IN    STD_LOGIC;
		re_one         : IN    STD_LOGIC;
		evict_one      : IN    STD_LOGIC;
		evict_addr_one : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		ack_one        : OUT   STD_LOGIC;
		inv_one        : OUT   STD_LOGIC;
		inv_llc_one    : OUT   STD_LOGIC;
		inv_addr_one   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_one    : IN    STD_LOGIC;
		c2c_one        : OUT   STD_LOGIC;
		c2c_addr_one   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		addr_two       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		we_two         : IN    STD_LOGIC;
		re_two         : IN    STD_LOGIC;
		evict_two      : IN    STD_LOGIC;
		evict_addr_two : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		ack_two        : OUT   STD_LOGIC;
		inv_two        : OUT   STD_LOGIC;
		inv_llc_two    : OUT   STD_LOGIC;
		inv_addr_two   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_two    : IN    STD_LOGIC;
		c2c_two        : OUT   STD_LOGIC;
		c2c_addr_two   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_llc        : OUT   STD_LOGIC;
		inv_addr_llc   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		inv_ack_llc    : IN    STD_LOGIC;
		evict_llc      : IN    STD_LOGIC;
		addr_llc       : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		c2c_llc        : OUT   STD_LOGIC;
		ack_llc        : OUT   STD_LOGIC;
		bus_c2c        : INOUT STD_LOGIC
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

	-- Point to point directory signals
	-- Dir - L1_1
	SIGNAL addr_one_DIR       : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL we_one_DIR         : STD_LOGIC;
	SIGNAL re_one_DIR         : STD_LOGIC;
	SIGNAL evict_one_DIR      : STD_LOGIC;
	SIGNAL evict_addr_one_DIR : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ack_one_DIR        : STD_LOGIC;
	SIGNAL inv_one_DIR        : STD_LOGIC;
	SIGNAL inv_llc_one_DIR    : STD_LOGIC;
	SIGNAL inv_addr_one_DIR   : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inv_ack_one_DIR    : STD_LOGIC;
	SIGNAL c2c_one_DIR        : STD_LOGIC;
	SIGNAL c2c_addr_one_DIR   : STD_LOGIC_VECTOR(31 DOWNTO 0);
	-- Dir - L1_2
	SIGNAL addr_two_DIR       : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL we_two_DIR         : STD_LOGIC;
	SIGNAL re_two_DIR         : STD_LOGIC;
	SIGNAL evict_two_DIR      : STD_LOGIC;
	SIGNAL evict_addr_two_DIR : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL ack_two_DIR        : STD_LOGIC;
	SIGNAL inv_two_DIR        : STD_LOGIC;
	SIGNAL inv_llc_two_DIR    : STD_LOGIC;
	SIGNAL inv_addr_two_DIR   : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inv_ack_two_DIR    : STD_LOGIC;
	SIGNAL c2c_two_DIR        : STD_LOGIC;
	SIGNAL c2c_addr_two_DIR   : STD_LOGIC_VECTOR(31 DOWNTO 0);
	-- Dir - LLC
	SIGNAL inv_llc_DIR        : STD_LOGIC;
	SIGNAL inv_addr_llc_DIR   : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL inv_ack_llc_DIR    : STD_LOGIC;
	SIGNAL evict_llc_DIR      : STD_LOGIC;
	SIGNAL addr_llc_DIR       : STD_LOGIC_VECTOR(31 DOWNTO 0);
	SIGNAL c2c_llc_DIR        : STD_LOGIC;
	SIGNAL ack_llc_DIR        : STD_LOGIC;
	
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
			arb_ack         => ack_llc_ARB,
			dir_inv         => inv_llc_DIR,
			dir_inv_addr    => inv_addr_llc_DIR,
			dir_inv_ack     => inv_ack_llc_DIR,
			dir_evict       => evict_llc_DIR,
			dir_addr        => addr_llc_DIR,
			dir_c2c         => c2c_llc_DIR,
			dir_ack         => ack_llc_DIR
		);

		dir : directory PORT MAP (
			clk            => clk,
			reset          => reset,
			addr_one       => addr_one_DIR,
			we_one         => we_one_DIR,
			re_one         => re_one_DIR,
			evict_one      => evict_one_DIR,
			evict_addr_one => evict_addr_one_DIR,
			ack_one        => ack_one_DIR,
			inv_one        => inv_one_DIR,
			inv_llc_one    => inv_llc_one_DIR,
			inv_addr_one   => inv_addr_one_DIR,
			inv_ack_one    => inv_ack_one_DIR,
			c2c_one        => c2c_one_DIR,
			c2c_addr_one   => c2c_addr_one_DIR,
			addr_two       => addr_two_DIR,
			we_two         => we_two_DIR,
			re_two         => re_two_DIR,
			evict_two      => evict_two_DIR,
			evict_addr_two => evict_addr_two_DIR,
			ack_two        => ack_two_DIR,
			inv_two        => inv_two_DIR,
			inv_llc_two    => inv_llc_two_DIR,
			inv_addr_two   => inv_addr_two_DIR,
			inv_ack_two    => inv_ack_two_DIR,
			c2c_two        => c2c_two_DIR,
			c2c_addr_two   => c2c_addr_two_DIR,
			inv_llc        => inv_llc_DIR,
			inv_addr_llc   => inv_addr_llc_DIR,
			inv_ack_llc    => inv_ack_llc_DIR,
			evict_llc      => evict_llc_DIR,
			addr_llc       => addr_llc_DIR,
			ack_llc        => ack_llc_DIR,
			c2c_llc        => c2c_llc_DIR,
			bus_c2c        => c2c_BUS
		);

		proc0 : inkel_pentiun
			GENERIC MAP (proc_id => 0)
			PORT MAP (
				clk            => clk,
				reset          => reset,
				debug_dump     => debug_dump,
				done_inv       => done_inv_P0,
				i_arb_req      => req_one_i_ARB,
				d_arb_req      => req_one_d_ARB,
				i_arb_ack      => ack_one_i_ARB,
				d_arb_ack      => ack_one_d_ARB,
				bus_cmd        => cmd_BUS,
				bus_addr       => addr_BUS,
				bus_done       => done_BUS,
				bus_force_inv  => force_inv_BUS,
				bus_c2c        => c2c_BUS,
				bus_data       => data_BUS,
				pc_out         => OPEN,
				dir_addr       => addr_one_DIR,
				dir_we         => we_one_DIR,
				dir_re         => re_one_DIR,
				dir_evict      => evict_one_DIR,
				dir_evict_addr => evict_addr_one_DIR,
				dir_ack        => ack_one_DIR,
				dir_inv        => inv_one_DIR,
				dir_inv_llc    => inv_llc_one_DIR,
				dir_inv_addr   => inv_addr_one_DIR,
				dir_inv_ack    => inv_ack_one_DIR,
				dir_c2c        => c2c_one_DIR,
				dir_c2c_addr   => c2c_addr_one_DIR
		);

		proc1 : inkel_pentiun
			GENERIC MAP (proc_id => 1)
			PORT MAP (
				clk            => clk,
				reset          => reset,
				debug_dump     => debug_dump,
				done_inv       => done_inv_P1,
				i_arb_req      => req_two_i_ARB,
				d_arb_req      => req_two_d_ARB,
				i_arb_ack      => ack_two_i_ARB,
				d_arb_ack      => ack_two_d_ARB,
				bus_cmd        => cmd_BUS,
				bus_addr       => addr_BUS,
				bus_done       => done_BUS,
				bus_force_inv  => force_inv_BUS,
				bus_c2c        => c2c_BUS,
				bus_data       => data_BUS,
				pc_out         => OPEN,
				dir_addr       => addr_two_DIR,
				dir_we         => we_two_DIR,
				dir_re         => re_two_DIR,
				dir_evict      => evict_two_DIR,
				dir_evict_addr => evict_addr_two_DIR,
				dir_ack        => ack_two_DIR,
				dir_inv        => inv_two_DIR,
				dir_inv_llc    => inv_llc_one_DIR,
				dir_inv_addr   => inv_addr_two_DIR,
				dir_inv_ack    => inv_ack_two_DIR,
				dir_c2c        => c2c_two_DIR,
				dir_c2c_addr   => c2c_addr_two_DIR
		);

		debug_dump <= '0';

END structure;
