LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.utils.ALL;

ENTITY store_buffer IS
	PORT(
		clk            : IN STD_LOGIC;
		reset          : IN STD_LOGIC;
		addr           : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		data_in        : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		re             : IN STD_LOGIC;
		we             : IN STD_LOGIC;
		is_byte        : IN STD_LOGIC;
		no_action      : IN STD_LOGIC;
		repl           : IN STD_LOGIC;
		repl_addr      : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
		done           : OUT STD_LOGIC;
		hit            : OUT STD_LOGIC;
		permit_repl    : OUT STD_LOGIC;
		tags_we        : OUT STD_LOGIC;
		tags_addr      : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		tags_is_byte   : OUT STD_LOGIC;
		cache_we       : OUT STD_LOGIC;
		cache_is_byte  : OUT STD_LOGIC;
		cache_data_in  : OUT STD_LOGIC_VECTOR(31 DOWNTO 0);
		stbuf_data_out : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
	);
END store_buffer;

ARCHITECTURE store_buffer_behavior OF store_buffer IS
	CONSTANT BYTE_BITS : INTEGER := 8;
	CONSTANT WORD_BITS : INTEGER := 32;
	CONSTANT NONE_OP : INTEGER := 0;
	CONSTANT LOAD_OP : INTEGER := 1;
	CONSTANT STORE_OP : INTEGER := 2;

	TYPE valid_fields_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC;
	TYPE addr_fields_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
	TYPE byte_fields_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC;
	TYPE data_fields_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC_VECTOR(31 DOWNTO 0);
	TYPE hit_t IS ARRAY(3 DOWNTO 0) OF STD_LOGIC;

	-- Fields of the store buffer
	SIGNAL valid_fields : valid_fields_t;
	SIGNAL addr_fields : addr_fields_t;
	SIGNAL byte_fields : byte_fields_t;
	SIGNAL data_fields : data_fields_t;

	-- Determine the next state
	SIGNAL state_i : store_buffer_state_t;
	SIGNAL state_nx_i : store_buffer_state_t;

	-- Current occupation of the buffer
	SIGNAL size_i : INTEGER RANGE 0 TO 4;
	SIGNAL size_nx_i : INTEGER RANGE 0 TO 4;

	-- Pointer to the start
	SIGNAL start_i : INTEGER RANGE 0 TO 3;
	SIGNAL start_nx_i : INTEGER RANGE 0 TO 3;

	-- Determine the entry of the buffer that has hit with the access
	SIGNAL hit_i : STD_LOGIC := '0';
	SIGNAL hit_entry_i : hit_t;
	SIGNAL hit_entry_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Determine the entry of the buffer that has hit with the replaced cache line
	SIGNAL repl_hit_i : STD_LOGIC := '0';
	SIGNAL repl_hit_entry_i : hit_t;
	SIGNAL repl_hit_entry_num_i : INTEGER RANGE 0 TO 3 := 0;

	-- Internal signal to control the write enable of the
	-- data cache. Not stable during the second half of the
	-- cycle.
	SIGNAL cache_we_i : STD_LOGIC := '0';

	-- Determine if the buffer needs to be flushed
	SIGNAL start_flush_i : STD_LOGIC;

	-- Determine if the buffer is currently flushing their entries
	SIGNAL flushing_i : STD_LOGIC;

	-- Determine if the store buffer is able to complete a previous write
	SIGNAL complete_write_i : STD_LOGIC;

	-- Determine if the store buffer has to add a new entry
	SIGNAL add_entry_i : STD_LOGIC;

	-- Procedure to reset and initialize the buffer
	PROCEDURE init_store_buffer(
			SIGNAL valid_fields : OUT valid_fields_t;
			SIGNAL size_nx_i : OUT INTEGER RANGE 0 TO 4;
			SIGNAL start_nx_i : OUT INTEGER RANGE 0 TO 3
		) IS
	BEGIN
		-- Initialize valid fields
		FOR i IN 0 TO 3 LOOP
			valid_fields(i) <= '0';
		END LOOP;

		size_nx_i <= 0;
		start_nx_i <= 0;
	END PROCEDURE;
BEGIN

internal_reg_process : PROCESS(clk, reset)
BEGIN
	IF rising_edge(clk) THEN
		IF reset = '1' THEN
			state_i <= READY;
			start_i <= 0;
			size_i <= 0;
		ELSE
			state_i <= state_nx_i;
			start_i <= start_nx_i;
			size_i <= size_nx_i;
		END IF;
	ELSIF falling_edge(clk) THEN
		IF reset = '1' THEN
			cache_we <= '0';
		ELSE
			cache_we <= cache_we_i;
		END IF;
	END IF;
END PROCESS internal_reg_process;


next_state_process : PROCESS(reset, state_i, we, re, start_flush_i, size_i)
BEGIN
	IF reset = '0' THEN
		-- Compute the next state only in
		-- the first half of the cycle
		IF clk = '1' THEN
			state_nx_i <= state_i;
			IF state_i = READY THEN
				IF we = '1' OR re = '1' THEN
					IF start_flush_i = '1' THEN
						IF size_i > 1 THEN
							state_nx_i <= FLUSHING;
						ELSIF size_i = 1 THEN
							state_nx_i <= FLUSHED;
						END IF;
					END IF;
				END IF;
			ELSIF state_i = FLUSHING THEN
				IF size_i = 1 THEN
					state_nx_i <= FLUSHED;
				END IF;
			ELSIF state_i = FLUSHED THEN
				state_nx_i <= READY;
			END IF;
		END IF;
	ELSE
		state_nx_i <= READY;
	END IF;
END PROCESS next_state_process;


execution_process : PROCESS(clk, reset)
	VARIABLE new_entry : INTEGER RANGE 0 TO 3;
BEGIN
	IF falling_edge(clk) THEN
		IF reset = '0' THEN
			IF complete_write_i = '1' OR flushing_i = '1' THEN
				valid_fields(start_i) <= '0';
				start_nx_i <= (start_i + 1) MOD 4;
				size_nx_i <= size_i - 1;

			ELSIF add_entry_i = '1' THEN
				new_entry := (start_i + size_i) MOD 4;
				valid_fields(new_entry) <= '1';
				addr_fields(new_entry) <= addr;
				byte_fields(new_entry) <= is_byte;
				data_fields(new_entry) <= data_in;
				size_nx_i <= size_nx_i + 1;
			END IF;
		ELSE
			init_store_buffer(valid_fields, size_nx_i, start_nx_i);
		END IF;
	END IF;
END PROCESS execution_process;

-- Need a flush when there is a line replacement and the store buffer is holding a pending write in that line
-- or there is a new write access and the buffer is full
start_flush_i <= '1' WHEN (repl = '1' AND repl_hit_i = '1') OR (we = '1' AND size_i = 4) ELSE '0';

-- Flush an entry of the buffer if the flushing process just started or the current state of the
-- buffer is flush
flushing_i <= '1' WHEN start_flush_i = '1' OR state_i = FLUSHING ELSE '0';

-- The buffer can complete a previous write if there is no
-- memory instruction and there is at least one entry
complete_write_i <= '1' WHEN we = '0' AND re = '0' AND size_i > 0 ELSE '0';

-- Logic to determine if a new entry has to be added
add_entry_i <= '1' WHEN we = '1' AND (state_i = FLUSHED OR (state_i = READY AND state_nx_i = READY AND no_action = '0')) ELSE '0';

-- For each entry, determine if it has hit with the access
hit_entry_i(0) <= valid_fields(0) AND to_std_logic(addr_fields(0)(31 DOWNTO 2) = addr(31 DOWNTO 2));
hit_entry_i(1) <= valid_fields(1) AND to_std_logic(addr_fields(1)(31 DOWNTO 2) = addr(31 DOWNTO 2));
hit_entry_i(2) <= valid_fields(2) AND to_std_logic(addr_fields(2)(31 DOWNTO 2) = addr(31 DOWNTO 2));
hit_entry_i(3) <= valid_fields(3) AND to_std_logic(addr_fields(3)(31 DOWNTO 2) = addr(31 DOWNTO 2));

-- For each entry, determine if it has hit with the replaced cache line
repl_hit_entry_i(0) <= valid_fields(0) AND to_std_logic(addr_fields(0)(31 DOWNTO 4) = repl_addr(31 DOWNTO 4));
repl_hit_entry_i(1) <= valid_fields(1) AND to_std_logic(addr_fields(1)(31 DOWNTO 4) = repl_addr(31 DOWNTO 4));
repl_hit_entry_i(2) <= valid_fields(2) AND to_std_logic(addr_fields(2)(31 DOWNTO 4) = repl_addr(31 DOWNTO 4));
repl_hit_entry_i(3) <= valid_fields(3) AND to_std_logic(addr_fields(3)(31 DOWNTO 4) = repl_addr(31 DOWNTO 4));

-- Determine which entry has hit with the access
hit_entry_num_i <= 0 WHEN hit_entry_i(0) = '1'
		ELSE 1 WHEN hit_entry_i(1) = '1'
		ELSE 2 WHEN hit_entry_i(2) = '1'
		ELSE 3 WHEN hit_entry_i(3) = '1'
		ELSE 0;

-- Determine which entry has hit with the replaced cache line
repl_hit_entry_num_i <= 0 WHEN repl_hit_entry_i(0) = '1'
		ELSE 1 WHEN repl_hit_entry_i(1) = '1'
		ELSE 2 WHEN repl_hit_entry_i(2) = '1'
		ELSE 3 WHEN repl_hit_entry_i(3) = '1'
		ELSE 0;

-- Determine if the access has hit
hit_i <= hit_entry_i(0) OR hit_entry_i(1) OR hit_entry_i(2) OR hit_entry_i(3);

-- Determine if the replaced cache line has hit
repl_hit_i <= repl_hit_entry_i(0) OR repl_hit_entry_i(1) OR repl_hit_entry_i(2) OR repl_hit_entry_i(3);

-- Logic to send stores to the tags component
tags_we <= flushing_i OR complete_write_i;
tags_addr <= addr_fields(start_i);
tags_is_byte <= byte_fields(start_i);

-- Logic to send stores to the data component
cache_we_i <= flushing_i OR complete_write_i;
cache_is_byte <= byte_fields(start_i);
cache_data_in <= data_fields(start_i);

-- Logic to control the output data from the store buffer
stbuf_data_out <= data_fields(hit_entry_num_i);
hit <= hit_i;

-- Permit the replacement when the flushing process has finished
permit_repl <= '1' WHEN state_i = FLUSHED ELSE '0';
done <= '1' WHEN state_nx_i = READY ELSE '0';

END store_buffer_behavior;