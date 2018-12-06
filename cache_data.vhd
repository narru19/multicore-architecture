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
		sb_data_in     : IN    STD_LOGIC_VECTOR(31 DOWNTO 0)
	);
END cache_data;

ARCHITECTURE cache_data_behavior OF cache_data IS
	CONSTANT BYTE_BITS : INTEGER := 8;
	CONSTANT WORD_BITS : INTEGER := 32;

	TYPE hit_t 			IS ARRAY(3 DOWNTO 0) OF STD_LOGIC;
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
	
	-- Determine if the has been a conflict
	SIGNAL obs_store_and_block_is_shared_i     : STD_LOGIC := '0';
	SIGNAL obs_store_and_block_is_modified_i   : STD_LOGIC := '0';
	SIGNAL obs_load_and_block_is_modified_i    : STD_LOGIC := '0';
	SIGNAL obs_store_from_other_L1             : STD_LOGIC := '0';
	SIGNAL obs_store_from_other_L1_and_present : STD_LOGIC := '0';
	SIGNAL obs_llc_evicts_and_present          : STD_LOGIC := '0';
	SIGNAL obs_llc_evicts                      : STD_LOGIC := '0';

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
next_state : PROCESS(clk, reset, state_i, obs_state_i, re, we, addr, mem_cmd, mem_addr, mem_done, mem_force_inv, mem_c2c, proc_hit_i, proc_repl_i, proc_inv_stop, obs_hit_i, obs_inv_stop, obs_store_and_block_is_shared_i, obs_store_and_block_is_modified_i, obs_load_and_block_is_modified_i, obs_store_from_other_L1_and_present, obs_llc_evicts_and_present, invalid_access_i)
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
							-- Must tell other L1s and LLC that we want the block as MODIFIED
							state_nx_i <= FORCEINV; 
						ELSE
							state_nx_i <= READY;
						END IF;
					ELSE
						state_nx_i <= ARBREQ;
					END IF;
				END IF;
			END IF;
		
		ELSIF state_i = WAITSB THEN
			IF proc_inv_stop = '0' THEN
				IF proc_hit_i = '1' THEN
					IF valid_fields(proc_hit_line_num_i) = STATE_SHARED AND we = '1' THEN
						-- Must tell other L1s and LLC that we want the block as MODIFIED
						state_nx_i <= FORCEINV;
					ELSE
						state_nx_i <= READY;
					END IF;
				ELSE
					state_nx_i <= ARBREQ;
				END IF;
			END IF;
		
		ELSIF state_i = FORCEINV THEN
			IF arb_ack = '1' THEN
				state_nx_i <= FORCEINVACK;
			END IF;
		
		ELSIF state_i = FORCEINVACK THEN
			IF mem_done = '1' THEN
				state_nx_i <= READY;
			END IF;
		
		ELSIF state_i = ARBREQ THEN
			IF arb_ack = '1' THEN
				IF proc_hit_i = '0' THEN
					IF proc_repl_i = '1' AND valid_fields(proc_hit_line_num_i) = STATE_MODIFIED THEN
						state_nx_i <= LINEREPL;
					ELSE
						state_nx_i <= LINEREQ;
					END IF;
				END IF;
			END IF;
		
		ELSIF state_i = LINEREPL THEN
			IF mem_done = '1' THEN
				state_nx_i <= ARBREQ;
			END IF;
		
		ELSIF state_i = LINEREQ THEN
			IF mem_done = '1' THEN
				state_nx_i <= READY;
			END IF;
		END IF;
		
		-- Observer Next State
		obs_state_nx_i <= obs_state_i;
		IF obs_state_i = READY THEN
			-- If we're observing another L1 storing and we have the block as modified or shared and...
			-- our processor is trying to store or load -> the block will soon be INVALID, switch to ARBREQ
			IF obs_store_and_block_is_modified_i = '1' OR obs_store_and_block_is_shared_i = '1' THEN
				IF obs_inv_stop = '1' THEN
					obs_state_nx_i <= WAITSB;
				ELSIF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
					state_nx_i <= ARBREQ;
					obs_state_nx_i <= READY;
				END IF;
			
			-- If we're observing another L1 loading and we have the block as modified and...
			-- our processor is trying to store -> the block will soon be SHARED, switch to FORCEINV
			ELSIF obs_load_and_block_is_modified_i = '1' THEN
				IF obs_inv_stop = '1' THEN
					obs_state_nx_i <= WAITSB;
				ELSIF state_i = READY AND we = '1' AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
					state_nx_i <= FORCEINV;
					obs_state_nx_i <= READY;
				END IF;
				
			-- If we're observing that some L1 is going from SHARED to MODIFIED and...
			-- our processor is trying to store or load -> the block will soon be INVALID, switch to ARBREQ
			ELSIF obs_store_from_other_L1_and_present = '1' THEN
				IF obs_inv_stop = '1' THEN
					obs_state_nx_i <= WAITSB;
				ELSIF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
					state_nx_i <= ARBREQ;
					obs_state_nx_i <= READY;
				END IF;
			
			-- If we're observing that the LLC is evicting a block and...
			-- our processor is trying to store or load -> the block will soon be INVALID, switch to ARBREQ
			ELSIF obs_llc_evicts_and_present = '1' THEN
				IF obs_inv_stop = '1' THEN
					obs_state_nx_i <= WAITSB;
				ELSIF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
					state_nx_i <= ARBREQ;
					obs_state_nx_i <= READY;
				END IF;
			END IF;
		
		ELSIF obs_state_i = WAITSB THEN
			IF obs_store_and_block_is_modified_i = '1' OR obs_store_and_block_is_shared_i = '1' THEN
				IF obs_inv_stop = '0' THEN
					obs_state_nx_i <= READY;
					IF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
						state_nx_i <= ARBREQ;
					END IF;
				END IF;
			
			ELSIF obs_load_and_block_is_modified_i = '1' THEN
				IF obs_inv_stop = '0' THEN
					obs_state_nx_i <= READY;
					IF state_i = READY AND we = '1' AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
						state_nx_i <= FORCEINV;
					END IF;
				END IF;
			
			ELSIF obs_store_from_other_L1_and_present = '1' THEN
				IF obs_inv_stop = '0' THEN
					obs_state_nx_i <= READY;
					IF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
						state_nx_i <= ARBREQ;
					END IF;
				END IF;
			
			ELSIF obs_llc_evicts_and_present = '1' THEN
				IF obs_inv_stop = '0' THEN
					obs_state_nx_i <= READY;
					IF (state_i = READY OR state_i = FORCEINV) AND (we = '1' OR re = '1') AND addr(31 DOWNTO 4) = mem_addr(31 DOWNTO 4) THEN
						state_nx_i <= ARBREQ;
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
			ELSIF state_nx_i = ARBREQ THEN
				arb_req <= '1';
			ELSIF state_nx_i = FORCEINV THEN
				arb_req <= '1';
			END IF;
		
		ELSIF state_i = FORCEINV THEN
			IF state_nx_i = FORCEINVACK THEN
				mem_addr      <= addr;
				mem_cmd       <= CMD_INV_M;
				mem_force_inv <= '1';
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = FORCEINVACK THEN
			IF state_nx_i = READY THEN
				LRU_execute(lru_fields, proc_hit_line_num_i);
				valid_fields(proc_hit_line_num_i) <= STATE_MODIFIED;
				line_num := proc_hit_line_num_i;
				arb_req <= '0';
			ELSE
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = ARBREQ THEN
			IF state_nx_i = LINEREPL THEN
				mem_cmd       <= CMD_PUT;
				mem_addr      <= tag_fields(lru_line_num_i) & "0000";
				mem_data      <= data_fields(lru_line_num_i);
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			ELSIF state_nx_i = LINEREQ THEN
				IF re = '1' THEN
					mem_cmd <= CMD_GETRD;
				ELSIF we = '1' THEN
					mem_cmd <= CMD_GETWR;
				END IF;
				mem_addr      <= addr;
				own_mem_cmd_i <= '1';
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = LINEREPL THEN
			IF state_nx_i = ARBREQ THEN
				arb_req <= '1';
				valid_fields(lru_line_num_i) <= STATE_INVALID;
			ELSE
				can_clear_bus := FALSE;
			END IF;
		
		ELSIF state_i = LINEREQ THEN
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
		END IF;
		
		IF sb_we = '1' THEN
			data_fields(sb_line_num_i)(sb_word_msb DOWNTO sb_word_lsb) <= sb_data_in;
		END IF;
		
		IF obs_state_i = READY OR obs_state_i = WAITSB THEN
			IF obs_state_nx_i = READY THEN
				-- Observe store and block as S -> Invalidate, LLC will provide data
				IF obs_store_and_block_is_shared_i = '1' THEN
					valid_fields(obs_hit_line_num_i) <= STATE_INVALID;
				
				-- Observe store and block as M -> Invalidate, provide data through C2C
				ELSIF obs_store_and_block_is_modified_i = '1' THEN
					-- Mark data as available so LLC knows when the data in the bus is valid
					-- This has no effect for this case, as the block will be MODIFIED in another
					-- L1, however we still signal this so that the LLC can go on
					mem_c2c  <= '1'; -- So that the LLC knows when to update if needed
					mem_done <= '1'; -- So that the other L1 knows when the data is ready
					mem_data <= data_fields(obs_hit_line_num_i);
					valid_fields(obs_hit_line_num_i) <= STATE_INVALID;
					can_clear_bus := FALSE;
				
				-- Observe load and block as M -> Shared, provide data through C2C
				ELSIF obs_load_and_block_is_modified_i = '1' THEN
					-- Mark data as available so LLC knows when the data in the bus is valid
					-- In this case, when the LLC receives "mem_c2c", it will know that it has
					-- to update its data and the state of the block to SHARED
					mem_c2c  <= '1';
					mem_done <= '1';
					mem_data <= data_fields(obs_hit_line_num_i);
					valid_fields(obs_hit_line_num_i) <= STATE_SHARED;
					can_clear_bus := FALSE;
				
				-- Observe that another L1 changes a block from S to M -> respond that
				-- we're coherent and invalidate if the block is present in the current L1
				ELSIF obs_store_from_other_L1 = '1' THEN
					-- If another L1 is changing from SHARED to MODIFIED, we must answer that
					-- we are coherent, and invalidate the block that is being modified in the
					-- other cache if it must be done. The LLC will invalidate within 1 cycle,
					-- and the other L1 will be waiting for our acknowledgement "mem_done".
					mem_done <= '1';
					IF obs_store_from_other_L1_and_present = '1' THEN
						valid_fields(obs_hit_line_num_i) <= STATE_INVALID;
					END IF;
					can_clear_bus := FALSE;
				
				-- Observe that the LLC is evicting some block
				ELSIF obs_llc_evicts = '1' THEN
					-- If an LLC is evicting a block, respond that we've invalidated whether it is
					-- present or not. If it is present and it is SHARED, simply invalidate. If it
					-- is present and it is MODIFIED, this won't be the path taken since the LLC will
					-- create a fake GETWR request and this L1 will activate the C2C transfer (obs 2)
					IF obs_llc_evicts_and_present = '1' THEN
						-- Cannot happen here, will happen in "obs_store_and_block_is_modified_i"
						-- IF (valid_fields(obs_hit_line_num_i) = STATE_MODIFIED) THEN
						valid_fields(obs_hit_line_num_i) <= STATE_INVALID;
					END IF;
					done_inv <= '1';
					can_clear_bus := FALSE;
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
obs_hit_line_i(0) <= '1' WHEN (valid_fields(0) = STATE_SHARED OR valid_fields(0) = STATE_MODIFIED) AND is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND tag_fields(0) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(1) <= '1' WHEN (valid_fields(1) = STATE_SHARED OR valid_fields(1) = STATE_MODIFIED) AND is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND tag_fields(1) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(2) <= '1' WHEN (valid_fields(2) = STATE_SHARED OR valid_fields(2) = STATE_MODIFIED) AND is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND tag_fields(2) = mem_addr(31 DOWNTO 4) ELSE '0';
obs_hit_line_i(3) <= '1' WHEN (valid_fields(3) = STATE_SHARED OR valid_fields(3) = STATE_MODIFIED) AND is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND tag_fields(3) = mem_addr(31 DOWNTO 4) ELSE '0';

-- Determine which line has hit the observation
obs_hit_line_num_i <=
	     0 WHEN obs_hit_line_i(0) = '1'
	ELSE 1 WHEN obs_hit_line_i(1) = '1'
	ELSE 2 WHEN obs_hit_line_i(2) = '1'
	ELSE 3 WHEN obs_hit_line_i(3) = '1'
	ELSE 0;

-- Determine whether there was an observer hit
obs_hit_i <= '1' WHEN (obs_hit_line_i(0) = '1' OR obs_hit_line_i(1) = '1' OR obs_hit_line_i(2) = '1' OR obs_hit_line_i(3) = '1') ELSE '0';

-- Determine if the cache observes a conflict when someone's trying to...
-- 1) Get a block with intention to write (CMD_GETWR) and we have it as SHARED
--   > Must invalidate
-- 2) Get a block with intention to write (CMD_GETWR) and we have it as MODIFIED
--   > Must transfer Cache 2 Cache & switch from MODIFIED to INVALID
-- 3) Get a block with intention to read  (CMD_GETRD) and we have it as MODIFIED
--   > Must transfer Cache 2 Cache & switch from MODIFIED to SHARED
-- 4) An L1 changes a block from SHARED to MODIFIED
--   > Must answer with an ack, whether we have that same block or not
-- 5) Same as 4) but we have the block as SHARED
--   > Must switch from SHARED to INVALID (and also answer with an ack through "mem_done", done by 4)
-- 6) The LLC evicts a block that is SHARED or MODIFIED
--   > Must respond whether we invalidate or it already is invalidated
-- 7) The LLC evicts a block that is SHARED or MODIFIED and we have it as SHARED or MODIFIED
--   > Must invalidate and update the LLC if needed (MODIFIED)
obs_store_and_block_is_shared_i     <= '1' WHEN obs_hit_i = '1' AND mem_cmd = CMD_GETWR AND valid_fields(obs_hit_line_num_i) = STATE_SHARED ELSE '0';
obs_store_and_block_is_modified_i   <= '1' WHEN obs_hit_i = '1' AND mem_cmd = CMD_GETWR AND valid_fields(obs_hit_line_num_i) = STATE_MODIFIED ELSE '0';
obs_load_and_block_is_modified_i    <= '1' WHEN obs_hit_i = '1' AND mem_cmd = CMD_GETRD AND valid_fields(obs_hit_line_num_i) = STATE_MODIFIED ELSE '0';
obs_store_from_other_L1             <= '1' WHEN is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND mem_cmd = CMD_INV_M ELSE '0';
obs_store_from_other_L1_and_present <= '1' WHEN obs_hit_i = '1' AND mem_cmd = CMD_INV_M ELSE '0';
obs_llc_evicts                      <= '1' WHEN is_cmd(mem_cmd) AND own_mem_cmd_i = '0' AND mem_cmd = CMD_INV_S ELSE '0';
obs_llc_evicts_and_present          <= '1' WHEN obs_hit_i = '1' AND mem_cmd = CMD_INV_S ELSE '0';

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

-- Blocks will invalidate only in cases 1), 2), 4) and 5) from the observer signals above.
-- Case 3) will not invalidate as it will go to SHARED, and case 6) is uncertain, it only happens in case 5) which is case 6) when the block isn't INVALID
-- obs_inv       <= obs_store_and_block_is_shared_i OR obs_store_and_block_is_modified_i OR obs_store_from_other_L1_and_present OR obs_llc_evicts_and_present;
obs_inv       <= obs_store_and_block_is_shared_i OR obs_store_and_block_is_modified_i;
obs_inv_addr  <= mem_addr;

END cache_data_behavior;
