LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE ieee.std_logic_textio.ALL;
USE std.textio.ALL;
USE work.utils.ALL;

ENTITY cache_data IS
	PORT(
		clk            : IN    STD_LOGIC;
		reset          : IN    STD_LOGIC;
		addr           : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		re             : IN    STD_LOGIC;
		we             : IN    STD_LOGIC;
		data_out       : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		hit            : OUT   STD_LOGIC;
		done           : OUT   STD_LOGIC;
		invalid_access : OUT   STD_LOGIC;
		done_inv       : OUT   STD_LOGIC;
		arb_req        : OUT   STD_LOGIC;
		arb_ack        : IN    STD_LOGIC;
		mem_cmd        : INOUT STD_LOGIC_VECTOR(2 DOWNTO 0);
		mem_addr       : INOUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		mem_done       : INOUT STD_LOGIC;
		mem_force_inv  : INOUT STD_LOGIC;
		mem_data       : INOUT STD_LOGIC_VECTOR(127 DOWNTO 0);
		mem_c2c        : INOUT STD_LOGIC;
		proc_inv       : OUT   STD_LOGIC;
		proc_inv_addr  : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		proc_inv_stop  : IN    STD_LOGIC;
		obs_inv        : OUT   STD_LOGIC;
		obs_inv_addr   : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		obs_inv_stop   : IN    STD_LOGIC;
		sb_addr        : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		sb_we          : IN    STD_LOGIC;
		sb_data_in     : IN    STD_LOGIC_VECTOR(31 DOWNTO 0);
		-- Directory Interface
		dir_addr       : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0);
		dir_we         : OUT   STD_LOGIC;                     -- L1 wants to modify the address
		dir_re         : OUT   STD_LOGIC;                     -- L1 wants to read the address
		dir_evict      : OUT   STD_LOGIC;                     -- L1 wants to evict the address
		dir_evict_addr : OUT   STD_LOGIC_VECTOR(31 DOWNTO 0); -- The address to evict
		dir_ack        : IN    STD_LOGIC;                     -- The directory signals that L1 can go on with its request
		dir_inv        : IN    STD_LOGIC;                     -- The directory wants the L1 to invalidate an addrss
		dir_inv_llc    : IN    STD_LOGIC;                     -- Whether the invalidation was triggered by the LLC
		dir_inv_addr   : IN    STD_LOGIC_VECTOR(31 DOWNTO 0); -- The address to invalidate
		dir_inv_ack    : OUT   STD_LOGIC;                     -- Acknowledgment of invalidation from L1 to directory
		dir_c2c        : IN    STD_LOGIC;                     -- The directory wants the L1 to make a C2C transaction (dir_c2c_addr)
                                                              --   Whether to invalidate the transfered line is known through (dir_inv)
                                                              --   Once transfered, this is signaled through mem_done (mem_done = 1)
		dir_c2c_addr   : IN    STD_LOGIC_VECTOR(31 DOWNTO 0)  -- The address of the data that must be transfered
	);
END cache_data;


ARCHITECTURE cache_data_behavior OF cache_data IS
	CONSTANT BYTE_BITS : INTEGER := 8;
	CONSTANT WORD_BITS : INTEGER := 32;

	TYPE hit_t          IS ARRAY(3 DOWNTO 0) OF STD_LOGIC;
	TYPE lru_fields_t   IS ARRAY(3 DOWNTO 0) OF INTEGER RANGE 0 to 3;
	TYPE tag_fields_t   IS ARRAY(3 DOWNTO 0) OF STD_LOGIC_VECTOR(27 DOWNTO 0);
	TYPE data_fields_t  IS ARRAY(3 DOWNTO 0) OF STD_LOGIC_VECTOR(127 DOWNTO 0);
	TYPE valid_fields_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC_VECTOR(1 DOWNTO 0);

	-- Fields of the cache
	SIGNAL lru_fields   : lru_fields_t;
	SIGNAL tag_fields   : tag_fields_t;
	SIGNAL data_fields  : data_fields_t;
	SIGNAL valid_fields : valid_fields_t;

	-- Invalid address
	SIGNAL invalid_access_i : STD_LOGIC;

	-- Own memory command
	SIGNAL own_mem_cmd_i : STD_LOGIC;

	-- The next state of the cache
	SIGNAL state_i    : data_cache_state_t;
	SIGNAL state_nx_i : data_cache_state_t;

	-- Observer state
	SIGNAL obs_state_i    : obs_data_cache_state_t;
	SIGNAL obs_state_nx_i : obs_data_cache_state_t;

	-- Determine the line of the cache that has hit with the access
	SIGNAL proc_hit_i          : STD_LOGIC := '0';
	SIGNAL proc_hit_line_i     : hit_t;
	SIGNAL proc_hit_line_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Determine the line of the cache that has hit with the observation
	SIGNAL obs_hit_i           : STD_LOGIC := '0';
	SIGNAL obs_hit_line_i      : hit_t;
	SIGNAL obs_hit_line_num_i  : INTEGER RANGE 0 TO 3 := 0;
	
	-- Determine the line of the cache that has hit with dir_inv_addr
	SIGNAL dir_inv_hit_i          : STD_LOGIC := '0';
	SIGNAL dir_inv_hit_line_i     : hit_t;
	SIGNAL dir_inv_hit_line_num_i : INTEGER RANGE 0 TO 3 := 0;
	
	-- Determine the line of the cache that has hit with dir_c2c_addr
	SIGNAL c2c_hit_i          : STD_LOGIC := '0';
	SIGNAL c2c_hit_line_i     : hit_t;
	SIGNAL c2c_hit_line_num_i : INTEGER RANGE 0 TO 3 := 0;
	
	-- Determine if there has been a conflict
	SIGNAL obs_rd_i              : STD_LOGIC := '0';
	SIGNAL obs_hit_line_rd_i     : hit_t;
	SIGNAL obs_hit_line_rd_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Determine the line number to output
	SIGNAL data_out_line_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Processor replacement signals
	SIGNAL proc_repl_i    : STD_LOGIC := '0';
	SIGNAL lru_line_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Determine the target word of the access
	SIGNAL ch_word_msb : INTEGER RANGE 0 TO 127 := 31;
	SIGNAL ch_word_lsb : INTEGER RANGE 0 TO 127 := 0;

	-- Store buffer signals
	SIGNAL sb_line_i     : hit_t;
	SIGNAL sb_line_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Determine the target word of the SB store
	SIGNAL sb_word_msb : INTEGER RANGE 0 TO 127 := 31;
	SIGNAL sb_word_lsb : INTEGER RANGE 0 TO 127 := 0;

	-- Procedure to reset and initialize the cache
	PROCEDURE reset_cache(
			SIGNAL lru_fields   : OUT lru_fields_t;
			SIGNAL valid_fields : OUT valid_fields_t;
			SIGNAL arb_req      : OUT STD_LOGIC
		) IS
	BEGIN
		-- Initialize LRU and valid fields
		FOR i IN 0 TO 3 LOOP
			lru_fields(i) <= i;
			valid_fields(i) <= STATE_INVALID;
		END LOOP;
		
		arb_req <= '0';
	END PROCEDURE;

	PROCEDURE clear_bus(
			SIGNAL mem_cmd       : OUT STD_LOGIC_VECTOR(2   DOWNTO 0);
			SIGNAL mem_addr      : OUT STD_LOGIC_VECTOR(31  DOWNTO 0);
			SIGNAL mem_data      : OUT STD_LOGIC_VECTOR(127 DOWNTO 0);
			SIGNAL mem_done      : OUT STD_LOGIC;
			SIGNAL mem_force_inv : OUT STD_LOGIC;
			SIGNAL mem_c2c       : OUT STD_LOGIC;
			SIGNAL own_mem_cmd_i : OUT STD_LOGIC;
			SIGNAL done_inv      : OUT STD_LOGIC
		) IS
	BEGIN
		mem_cmd       <= (OTHERS => 'Z');
		mem_addr      <= (OTHERS => 'Z');
		mem_data      <= (OTHERS => 'Z');
		mem_done      <= 'Z';
		mem_force_inv <= 'Z';
		mem_c2c       <= 'Z';
		own_mem_cmd_i <= '0';
		done_inv      <= '0';
	END PROCEDURE;

	-- Procedure to execute the Least Recently Used alogrithm
	PROCEDURE LRU_execute(
			SIGNAL lru_fields : INOUT lru_fields_t;
			SIGNAL line_id : IN INTEGER RANGE 0 TO 3
		) IS
		VARIABLE old_value : INTEGER RANGE 0 TO 3 := lru_fields(line_id);
	BEGIN
		FOR i IN 0 TO 3 LOOP
			IF lru_fields(i) < old_value THEN
				lru_fields(i) <= lru_fields(i) + 1;
			END IF;
		lru_fields(line_id) <= 0;
		END LOOP;
	END PROCEDURE;
BEGIN

-- Process that represents the internal register
internal_register : PROCESS(clk, reset)
BEGIN
	IF rising_edge(clk) THEN
		IF reset = '1' THEN
			state_i <= READY;
			obs_state_i <= READY;
		ELSE
			state_i <= state_nx_i;
			obs_state_i <= obs_state_nx_i;
		END IF;
	END IF;
END PROCESS internal_register;



-- Process that computes the next state of the cache
next_state : PROCESS(clk, reset, state_i, obs_state_i, re, we, addr, mem_cmd, mem_addr, mem_done, mem_force_inv, mem_c2c, proc_hit_i, proc_repl_i, proc_hit_line_num_i, obs_hit_i, obs_inv_stop, invalid_access_i, dir_ack, dir_inv, dir_c2c, dir_inv_hit_i, dir_inv_hit_line_num_i, dir_inv_hit_line_i, sb_addr, sb_we, sb_data_in, c2c_hit_i, c2c_hit_line_i, c2c_hit_line_num_i)
BEGIN
	IF reset = '1' THEN
		state_nx_i <= READY;
		obs_state_nx_i <= READY;
	ELSIF clk = '1' THEN
		-- Processor Next State
		state_nx_i <= state_i;
		
		IF state_i = READY THEN
			IF (re = '1' OR we = '1') AND invalid_access_i = '0' THEN
				IF proc_inv_stop = '1' THEN
					state_nx_i <= WAITSB;
				ELSE
					IF proc_hit_i = '1' THEN
						IF valid_fields(proc_hit_line_num_i) = STATE_SHARED AND we = '1' THEN
							state_nx_i <= WAIT_DIR; 
						ELSE
							state_nx_i <= READY;
						END IF;
					ELSE
						state_nx_i <= WAIT_DIR;
					END IF;
				END IF;
			END IF;
		
		ELSIF state_i = WAITSB THEN
			IF proc_inv_stop = '0' THEN
				IF proc_hit_i = '1' THEN
					IF valid_fields(proc_hit_line_num_i) = STATE_SHARED AND we = '1' THEN
						state_nx_i <= WAIT_DIR;
					ELSE
						state_nx_i <= READY;
					END IF;
				ELSE
					state_nx_i <= WAIT_DIR;
				END IF;
			END IF;
		
		ELSIF state_i = WAIT_DIR THEN
			IF dir_ack = '1' THEN
				IF proc_hit_i = '1' THEN
					state_nx_i <= READY;
				ELSIF (proc_hit_i = '0' AND proc_repl_i = '0') THEN
					state_nx_i <= ARBREQ;
				ELSIF (proc_hit_i = '0' AND proc_repl_i = '1') THEN
					state_nx_i <= EVICT_ARB;
				END IF;
			END IF;
		
		ELSIF state_i = ARBREQ THEN
			IF arb_ack = '1' THEN
				state_nx_i <= MEMREQ;
			END IF;
		
		ELSIF state_i = MEMREQ THEN
			IF mem_done = '1' THEN
				state_nx_i <= READY;
			END IF;
		
		ELSIF state_i = EVICT_ARB THEN
			IF arb_ack = '1' THEN
				IF valid_fields(lru_line_num_i) = STATE_SHARED THEN
					state_nx_i <= MEMREQ;
				ELSIF valid_fields(lru_line_num_i) = STATE_MODIFIED THEN
					state_nx_i <= EVICT_MEM;
				END IF;
			END IF;
		
		ELSIF state_i = EVICT_MEM THEN
			IF mem_done = '1' THEN
				state_nx_i <= FINISH_EVICT;
			END IF;
		
		ELSIF state_i = FINISH_EVICT THEN
			state_nx_i <= MEMREQ;
		END IF;
		
		-- Observer Next State
		obs_state_nx_i <= obs_state_i;
		IF obs_state_i = READY THEN
			IF dir_inv = '1' THEN
				IF obs_inv_stop = '1' THEN
					obs_state_nx_i <= WAITSB;
				ELSIF (state_i = READY) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = dir_inv_addr(31 DOWNTO 4) THEN
					state_nx_i <= WAIT_DIR;
					obs_state_nx_i <= READY;
				END IF;
			END IF;
		
		ELSIF obs_state_i = WAITSB THEN
			IF dir_inv = '1' THEN
				IF obs_inv_stop = '0' THEN
					obs_state_nx_i <= READY;
					IF (state_i = READY) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = dir_inv_addr(31 DOWNTO 4) THEN
						state_nx_i <= WAITSB;
					END IF;
				END IF;
			END IF;
		END IF;
	END IF;
END PROCESS next_state;


-- Process that sets the output signals of the cache
execution_process : PROCESS(clk)
	VARIABLE line_num : INTEGER RANGE 0 TO 3;
	VARIABLE can_clear_bus : BOOLEAN;
BEGIN
	line_num := 0;
	can_clear_bus := TRUE;
	
	IF rising_edge(clk) AND reset = '1' THEN
		reset_cache(lru_fields, valid_fields, arb_req);
		clear_bus(mem_cmd, mem_addr, mem_data, mem_done, mem_force_inv, mem_c2c, own_mem_cmd_i, done_inv);
	
	ELSIF falling_edge(clk) AND reset = '0' THEN
		IF state_i = READY OR state_i = WAITSB THEN
			IF state_nx_i = READY THEN
				IF re = '1' OR we = '1' THEN
					LRU_execute(lru_fields, proc_hit_line_num_i);
					line_num := proc_hit_line_num_i;
				END IF;
			ELSIF state_nx_i = WAIT_DIR THEN
				IF (proc_hit_i = '1') THEN
					dir_re   <= re;
					dir_we   <= we;
					dir_addr <= addr;
				ELSIF (proc_hit_i = '0' AND proc_repl_i = '0') THEN
					dir_re   <= re;
					dir_we   <= we;
					dir_addr <= addr;
				ELSIF (proc_hit_i = '0' AND proc_repl_i = '1') THEN
					dir_evict      <= '1';
					dir_evict_addr <= tag_fields(lru_line_num_i) & "0000";
					dir_re         <= re;
					dir_we         <= we;
					dir_addr       <= addr;
				END IF;
			END IF;
		
		ELSIF state_i = WAIT_DIR THEN
			IF state_nx_i = READY THEN
				LRU_execute(lru_fields, proc_hit_line_num_i);
				valid_fields(proc_hit_line_num_i) <= STATE_MODIFIED;
				dir_re <= '0';
				dir_we <= '0';
				line_num := proc_hit_line_num_i;
			ELSIF (state_nx_i = ARBREQ OR state_nx_i = EVICT_ARB) THEN
				arb_req   <= '1';
				dir_re    <= '0';
				dir_we    <= '0';
				dir_evict <= '0';
			END IF;
		
		ELSIF state_i = ARBREQ THEN
			IF state_nx_i = MEMREQ THEN
				IF re = '1' THEN
					mem_cmd <= CMD_GETRD;
				ELSIF we = '1' THEN
					mem_cmd <= CMD_GETWR;
				END IF;
				mem_addr      <= addr;
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = MEMREQ THEN
			IF state_nx_i = READY THEN
				IF re = '1' THEN
					valid_fields(lru_line_num_i) <= STATE_SHARED;
				ELSIF we = '1' THEN
					valid_fields(lru_line_num_i) <= STATE_MODIFIED;
				END IF;
				arb_req <= '0';
				tag_fields(lru_line_num_i) <= addr(31 DOWNTO 4);
				data_fields(lru_line_num_i) <= mem_data;
				LRU_execute(lru_fields, lru_line_num_i);
				line_num := lru_line_num_i;
			ELSE
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = EVICT_ARB THEN
			IF state_nx_i = MEMREQ THEN
				IF re = '1' THEN
					mem_cmd <= CMD_GETRD;
				ELSIF we = '1' THEN
					mem_cmd <= CMD_GETWR;
				END IF;
				mem_addr      <= addr;
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			ELSIF state_nx_i = EVICT_MEM THEN
				mem_cmd       <= CMD_PUT;
				mem_addr      <= tag_fields(lru_line_num_i) & "0000";
				mem_data      <= data_fields(lru_line_num_i);
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = EVICT_MEM THEN
			IF state_nx_i = FINISH_EVICT THEN
				IF re = '1' THEN
					mem_cmd <= CMD_GETRD;
				ELSIF we = '1' THEN
					mem_cmd <= CMD_GETWR;
				END IF;
				mem_addr      <= addr;
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			ELSE
				can_clear_bus := FALSE;
			END IF;
			
		ELSIF state_i = FINISH_EVICT THEN
			can_clear_bus := FALSE;
		END IF;
		
		IF sb_we = '1' THEN
			data_fields(sb_line_num_i)(sb_word_msb DOWNTO sb_word_lsb) <= sb_data_in;
		END IF;
		
		IF obs_state_i = READY OR obs_state_i = WAITSB THEN
			dir_inv_ack <= '0';
			IF obs_state_nx_i = READY THEN
				IF (dir_inv = '1' AND dir_c2c = '0' AND dir_inv_hit_i = '1') THEN
					valid_fields(dir_inv_hit_line_num_i) <= STATE_INVALID;
					dir_inv_ack <= '1';
				
				ELSIF (dir_c2c = '1' AND own_mem_cmd_i = '0' AND mem_addr = dir_c2c_addr AND c2c_hit_i = '1') THEN
					mem_c2c <= '1';
					mem_done <= '1';
					mem_data <= data_fields(c2c_hit_line_num_i);
					can_clear_bus := FALSE;
					IF (dir_inv = '0') THEN
						valid_fields(c2c_hit_line_num_i) <= STATE_SHARED;
					ELSIF (dir_inv = '1') THEN
						valid_fields(c2c_hit_line_num_i) <= STATE_INVALID;
						dir_inv_ack <= '1';
					END IF;
				END IF;
			END IF;
		END IF;
		
		IF can_clear_bus THEN
			clear_bus(mem_cmd, mem_addr, mem_data, mem_done, mem_force_inv, mem_c2c, own_mem_cmd_i, done_inv);
		END IF;
		
		data_out_line_num_i <= line_num;
	END IF;
END PROCESS execution_process;


-----------------------
--    SIGNAL LOGIC   --

-- Determine the least recently used line
lru_line_num_i <= 
	     0 WHEN valid_fields(0) = STATE_INVALID
	ELSE 1 WHEN valid_fields(1) = STATE_INVALID
	ELSE 2 WHEN valid_fields(2) = STATE_INVALID
	ELSE 3 WHEN valid_fields(3) = STATE_INVALID
	ELSE 0 WHEN lru_fields(0) = 3
	ELSE 1 WHEN lru_fields(1) = 3
	ELSE 2 WHEN lru_fields(2) = 3
	ELSE 3 WHEN lru_fields(3) = 3
	ELSE 0;

-- Check if the access is invalid
invalid_access_i <= '1' WHEN (re = '1' OR we = '1') AND addr(1 DOWNTO 0) /= "00" ELSE '0';

-- For each line, determine if the access has hit
proc_hit_line_i(0) <= '1' WHEN (valid_fields(0) = STATE_SHARED OR valid_fields(0) = STATE_MODIFIED) AND tag_fields(0) = addr(31 DOWNTO 4) ELSE '0';
proc_hit_line_i(1) <= '1' WHEN (valid_fields(1) = STATE_SHARED OR valid_fields(1) = STATE_MODIFIED) AND tag_fields(1) = addr(31 DOWNTO 4) ELSE '0';
proc_hit_line_i(2) <= '1' WHEN (valid_fields(2) = STATE_SHARED OR valid_fields(2) = STATE_MODIFIED) AND tag_fields(2) = addr(31 DOWNTO 4) ELSE '0';
proc_hit_line_i(3) <= '1' WHEN (valid_fields(3) = STATE_SHARED OR valid_fields(3) = STATE_MODIFIED) AND tag_fields(3) = addr(31 DOWNTO 4) ELSE '0';

-- Determine which line has hit (WARNING: only use if a line has hit)
proc_hit_line_num_i <=
	     0 WHEN proc_hit_line_i(0) = '1'
	ELSE 1 WHEN proc_hit_line_i(1) = '1'
	ELSE 2 WHEN proc_hit_line_i(2) = '1'
	ELSE 3 WHEN proc_hit_line_i(3) = '1'
	ELSE 0;

-- Determine if the access has hit
proc_hit_i <= proc_hit_line_i(0) OR proc_hit_line_i(1) OR proc_hit_line_i(2) OR proc_hit_line_i(3);

-- Determine if the cache needs a line replacement
proc_repl_i <= (re OR we) AND NOT proc_hit_i AND (to_std_logic(valid_fields(lru_line_num_i) = STATE_SHARED) OR to_std_logic(valid_fields(lru_line_num_i) = STATE_MODIFIED));

-- For each line, determine if the observer has hit
obs_hit_line_i(0) <= '1' WHEN tag_fields(0) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(1) <= '1' WHEN tag_fields(1) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(2) <= '1' WHEN tag_fields(2) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(3) <= '1' WHEN tag_fields(3) = mem_addr(31 DOWNTO 4) ELSE '0';

-- Determine which line has hit the observation
obs_hit_line_num_i <=
	     0 WHEN obs_hit_line_i(0) = '1'
	ELSE 1 WHEN obs_hit_line_i(1) = '1'
	ELSE 2 WHEN obs_hit_line_i(2) = '1'
	ELSE 3 WHEN obs_hit_line_i(3) = '1'
	ELSE 0;

-- For each line, determine if the observer has hit
c2c_hit_line_i(0) <= '1' WHEN tag_fields(0) = dir_c2c_addr(31 DOWNTO 4) ELSE '0';
c2c_hit_line_i(1) <= '1' WHEN tag_fields(1) = dir_c2c_addr(31 DOWNTO 4) ELSE '0';
c2c_hit_line_i(2) <= '1' WHEN tag_fields(2) = dir_c2c_addr(31 DOWNTO 4) ELSE '0';
c2c_hit_line_i(3) <= '1' WHEN tag_fields(3) = dir_c2c_addr(31 DOWNTO 4) ELSE '0';

-- Determine which line has hit the observation
c2c_hit_line_num_i <=
	     0 WHEN c2c_hit_line_i(0) = '1'
	ELSE 1 WHEN c2c_hit_line_i(1) = '1'
	ELSE 2 WHEN c2c_hit_line_i(2) = '1'
	ELSE 3 WHEN c2c_hit_line_i(3) = '1'
	ELSE 0;

c2c_hit_i <= c2c_hit_line_i(0) OR c2c_hit_line_i(1) OR c2c_hit_line_i(2) OR c2c_hit_line_i(3);

-- For each line, determine if the dir_inv_addr has hit
dir_inv_hit_line_i(0) <= '1' WHEN tag_fields(0) = dir_inv_addr(31 DOWNTO 4) ELSE '0';
dir_inv_hit_line_i(1) <= '1' WHEN tag_fields(1) = dir_inv_addr(31 DOWNTO 4) ELSE '0';
dir_inv_hit_line_i(2) <= '1' WHEN tag_fields(2) = dir_inv_addr(31 DOWNTO 4) ELSE '0';
dir_inv_hit_line_i(3) <= '1' WHEN tag_fields(3) = dir_inv_addr(31 DOWNTO 4) ELSE '0';

dir_inv_hit_i <= dir_inv_hit_line_i(0) OR dir_inv_hit_line_i(1) OR dir_inv_hit_line_i(2) OR dir_inv_hit_line_i(3);

-- Determine which line has hit the dir_inv_addr
dir_inv_hit_line_num_i <=
	     0 WHEN dir_inv_hit_line_i(0) = '1'
	ELSE 1 WHEN dir_inv_hit_line_i(1) = '1'
	ELSE 2 WHEN dir_inv_hit_line_i(2) = '1'
	ELSE 3 WHEN dir_inv_hit_line_i(3) = '1'
	ELSE 0;

-- Store buffer signals
sb_line_i(0) <= to_std_logic(valid_fields(0) = STATE_MODIFIED) AND to_std_logic(tag_fields(0) = sb_addr(31 DOWNTO 4));
sb_line_i(1) <= to_std_logic(valid_fields(1) = STATE_MODIFIED) AND to_std_logic(tag_fields(1) = sb_addr(31 DOWNTO 4));
sb_line_i(2) <= to_std_logic(valid_fields(2) = STATE_MODIFIED) AND to_std_logic(tag_fields(2) = sb_addr(31 DOWNTO 4));
sb_line_i(3) <= to_std_logic(valid_fields(3) = STATE_MODIFIED) AND to_std_logic(tag_fields(3) = sb_addr(31 DOWNTO 4));

sb_line_num_i <= 
	     0 WHEN sb_line_i(0) = '1'
	ELSE 1 WHEN sb_line_i(1) = '1'
	ELSE 2 WHEN sb_line_i(2) = '1'
	ELSE 3 WHEN sb_line_i(3) = '1'
	ELSE 0;

-- Store buffer logic
sb_word_msb <= (to_integer(unsigned(sb_addr(3 DOWNTO 2))) + 1) * WORD_BITS - 1;
sb_word_lsb <= (to_integer(unsigned(sb_addr(3 DOWNTO 2))) * WORD_BITS);

-- Output Data logic
invalid_access <= invalid_access_i;

ch_word_msb <= (to_integer(unsigned(addr(3 DOWNTO 2))) + 1) * WORD_BITS - 1;
ch_word_lsb <= (to_integer(unsigned(addr(3 DOWNTO 2))) * WORD_BITS);

data_out <= data_fields(data_out_line_num_i)(ch_word_msb DOWNTO ch_word_lsb);

-- The cache stalls when there is a cache operation that misses
-- The cache does not stall when there's a hit or there are no requests (!re AND !we)
done <= (proc_hit_i AND (re OR (we AND to_std_logic(valid_fields(proc_hit_line_num_i) = STATE_MODIFIED)))) OR NOT(re OR we);
hit  <= (proc_hit_i AND (re OR (we AND to_std_logic(valid_fields(proc_hit_line_num_i) = STATE_MODIFIED))));

proc_inv      <= proc_repl_i;
proc_inv_addr <= tag_fields(lru_line_num_i) & "0000";

obs_inv       <= dir_inv AND dir_inv_hit_i AND NOT dir_inv_llc;
obs_inv_addr  <= dir_inv_addr;

END cache_data_behavior;
