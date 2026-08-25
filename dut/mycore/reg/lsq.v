`timescale 1ns/1ps

// Eight-entry load/store queue with one outstanding split-DM transaction.
// Loads issue in program order and cannot pass an older store or an older
// control/FENCE barrier.  Stores issue only while they are the ROB head.
module lsq (
    input             clk,
    input             reset,
    input             flush_in,

    input       [1:0] dispatch_count_in,
    input             dispatch0_enable_in,
    input             dispatch0_is_store_in,
    input      [63:0] dispatch0_seq_in,
    input       [2:0] dispatch0_rob_in,
    input       [5:0] dispatch0_pdst_in,
    input             dispatch0_writes_in,
    input       [2:0] dispatch0_lsu_op_in,
    input             dispatch1_enable_in,
    input             dispatch1_is_store_in,
    input      [63:0] dispatch1_seq_in,
    input       [2:0] dispatch1_rob_in,
    input       [5:0] dispatch1_pdst_in,
    input             dispatch1_writes_in,
    input       [2:0] dispatch1_lsu_op_in,
    output reg  [2:0] alloc_index0_out,
    output reg  [2:0] alloc_index1_out,
    output reg  [3:0] free_count_out,

    input             agu_capture_valid_in,
    input       [2:0] agu_capture_index_in,
    input      [31:0] agu_addr_in,
    input      [31:0] agu_wdata_in,
    input       [3:0] agu_wstrb_in,
    input       [2:0] agu_lsu_op_in,

    input             rob_head_valid_in,
    input       [2:0] rob_head_tag_in,
    input             rob_head_is_store_in,
    input             barrier_valid_in,
    input      [63:0] barrier_seq_in,

    output     [31:0] dm_req_addr_out,
    output            dm_req_rvalid_out,
    input             dm_req_rready_in,
    input             dm_resp_rvalid_in,
    input      [31:0] dm_resp_rdata_in,
    output            dm_req_wvalid_out,
    input             dm_req_wready_in,
    output      [3:0] dm_req_wstrb_out,
    output     [31:0] dm_req_wdata_out,
    input             dm_resp_wvalid_in,

    output            load_result_valid_out,
    input             load_result_grant_in,
    output      [2:0] load_result_rob_out,
    output      [5:0] load_result_pdst_out,
    output            load_result_writes_out,
    output     [31:0] load_result_value_out,

    output reg        store_complete_valid_out,
    output reg  [2:0] store_complete_rob_out,
    output            memory_idle_out
);

    localparam LSQ_DEPTH = 8;

    reg        entry_valid [0:LSQ_DEPTH-1];
    reg        entry_is_store [0:LSQ_DEPTH-1];
    reg        entry_addr_valid [0:LSQ_DEPTH-1];
    reg        entry_issued [0:LSQ_DEPTH-1];
    reg [63:0] entry_seq [0:LSQ_DEPTH-1];
    reg  [2:0] entry_rob [0:LSQ_DEPTH-1];
    reg  [5:0] entry_pdst [0:LSQ_DEPTH-1];
    reg        entry_writes [0:LSQ_DEPTH-1];
    reg  [2:0] entry_lsu_op [0:LSQ_DEPTH-1];
    reg [31:0] entry_addr [0:LSQ_DEPTH-1];
    reg [31:0] entry_wdata [0:LSQ_DEPTH-1];
    reg  [3:0] entry_wstrb [0:LSQ_DEPTH-1];

    reg        request_pending_q;
    reg        memory_busy_q;
    reg        request_write_q;
    reg  [2:0] request_index_q;
    reg [31:0] request_addr_q;
    reg [31:0] request_wdata_q;
    reg  [3:0] request_wstrb_q;
    reg  [2:0] request_rob_q;
    reg  [5:0] request_pdst_q;
    reg        request_writes_q;
    reg  [2:0] request_lsu_op_q;

    reg        drop_active_q;
    reg        drop_is_write_q;

    reg        load_result_valid_q;
    reg  [2:0] load_result_rob_q;
    reg  [5:0] load_result_pdst_q;
    reg        load_result_writes_q;
    reg [31:0] load_result_value_q;

    integer alloc_i;
    reg alloc0_found;
    reg alloc1_found;
    reg [2:0] first_free_index;
    reg [2:0] second_free_index;

    always @(*) begin
        free_count_out = 4'b0;
        first_free_index = 3'b0;
        second_free_index = 3'b0;
        alloc0_found = 1'b0;
        alloc1_found = 1'b0;
        for (alloc_i = 0; alloc_i < LSQ_DEPTH; alloc_i = alloc_i + 1) begin
            if (!entry_valid[alloc_i]) begin
                free_count_out = free_count_out + 1'b1;
                if (!alloc0_found) begin
                    first_free_index = alloc_i[2:0];
                    alloc0_found = 1'b1;
                end
                else if (!alloc1_found) begin
                    second_free_index = alloc_i[2:0];
                    alloc1_found = 1'b1;
                end
            end
        end

        alloc_index0_out = first_free_index;
        if (dispatch0_enable_in)
            alloc_index1_out = second_free_index;
        else
            alloc_index1_out = first_free_index;
    end

    integer select_i;
    integer select_j;
    reg candidate_valid;
    reg candidate_write;
    reg [2:0] candidate_index;
    reg [63:0] best_load_seq;
    reg older_store_found;
    reg older_load_found;
    reg older_barrier_found;

    always @(*) begin
        candidate_valid = 1'b0;
        candidate_write = 1'b0;
        candidate_index = 3'b0;
        best_load_seq = 64'hffff_ffff_ffff_ffff;
        older_store_found = 1'b0;
        older_load_found = 1'b0;
        older_barrier_found = 1'b0;

        if (!flush_in && !request_pending_q && !memory_busy_q &&
            !drop_active_q && !load_result_valid_q) begin
            if (rob_head_valid_in && rob_head_is_store_in) begin
                for (select_i = 0; select_i < LSQ_DEPTH;
                     select_i = select_i + 1) begin
                    if (!candidate_valid && entry_valid[select_i] &&
                        entry_is_store[select_i] &&
                        entry_addr_valid[select_i] &&
                        !entry_issued[select_i] &&
                        (entry_rob[select_i] == rob_head_tag_in)) begin
                        candidate_valid = 1'b1;
                        candidate_write = 1'b1;
                        candidate_index = select_i[2:0];
                    end
                end
            end

            // While a store is the ROB head, no load may be prepared even if
            // the store response cleared its LSQ entry in the prior cycle.
            // The head must retire before the younger load becomes eligible.
            if (!candidate_valid &&
                !(rob_head_valid_in && rob_head_is_store_in)) begin
                for (select_i = 0; select_i < LSQ_DEPTH;
                     select_i = select_i + 1) begin
                    if (entry_valid[select_i] &&
                        !entry_is_store[select_i] &&
                        entry_addr_valid[select_i] &&
                        !entry_issued[select_i]) begin
                        older_store_found = 1'b0;
                        older_load_found = 1'b0;
                        older_barrier_found = barrier_valid_in &&
                            (barrier_seq_in < entry_seq[select_i]);
                        for (select_j = 0; select_j < LSQ_DEPTH;
                             select_j = select_j + 1) begin
                            if (entry_valid[select_j] &&
                                (entry_seq[select_j] <
                                 entry_seq[select_i])) begin
                                if (entry_is_store[select_j])
                                    older_store_found = 1'b1;
                                else
                                    older_load_found = 1'b1;
                            end
                        end
                        if (!older_store_found && !older_load_found &&
                            !older_barrier_found &&
                            (entry_seq[select_i] < best_load_seq)) begin
                            candidate_valid = 1'b1;
                            candidate_write = 1'b0;
                            candidate_index = select_i[2:0];
                            best_load_seq = entry_seq[select_i];
                        end
                    end
                end
            end
        end
    end

    assign dm_req_addr_out = request_addr_q;
    assign dm_req_wdata_out = request_wdata_q;
    assign dm_req_wstrb_out = request_wstrb_q;
    assign dm_req_rvalid_out = request_pending_q && !request_write_q &&
                               !flush_in;
    assign dm_req_wvalid_out = request_pending_q && request_write_q &&
                               !flush_in;

    wire read_request_fire;
    wire write_request_fire;
    wire request_fire;
    wire active_response_now;
    wire drop_response_now;
    assign read_request_fire = dm_req_rvalid_out && dm_req_rready_in;
    assign write_request_fire = dm_req_wvalid_out && dm_req_wready_in;
    assign request_fire = read_request_fire || write_request_fire;
    assign active_response_now = request_write_q ?
                                 dm_resp_wvalid_in : dm_resp_rvalid_in;
    assign drop_response_now = drop_is_write_q ?
                               dm_resp_wvalid_in : dm_resp_rvalid_in;

    wire [31:0] extended_load_value;
    load_extender load_extender_inst (
        .lsu_op_in  (request_lsu_op_q),
        .raw_data_in(dm_resp_rdata_in),
        .value_out  (extended_load_value)
    );

    assign load_result_valid_out = load_result_valid_q;
    assign load_result_rob_out = load_result_rob_q;
    assign load_result_pdst_out = load_result_pdst_q;
    assign load_result_writes_out = load_result_writes_q;
    assign load_result_value_out = load_result_value_q;
    assign memory_idle_out = !request_pending_q && !memory_busy_q &&
                             !drop_active_q && !load_result_valid_q;

    integer state_i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (state_i = 0; state_i < LSQ_DEPTH;
                 state_i = state_i + 1) begin
                entry_valid[state_i] <= 1'b0;
                entry_is_store[state_i] <= 1'b0;
                entry_addr_valid[state_i] <= 1'b0;
                entry_issued[state_i] <= 1'b0;
                entry_seq[state_i] <= 64'b0;
                entry_rob[state_i] <= 3'b0;
                entry_pdst[state_i] <= 6'b0;
                entry_writes[state_i] <= 1'b0;
                entry_lsu_op[state_i] <= 3'b0;
                entry_addr[state_i] <= 32'b0;
                entry_wdata[state_i] <= 32'b0;
                entry_wstrb[state_i] <= 4'b0;
            end
            request_pending_q <= 1'b0;
            memory_busy_q <= 1'b0;
            request_write_q <= 1'b0;
            request_index_q <= 3'b0;
            request_addr_q <= 32'b0;
            request_wdata_q <= 32'b0;
            request_wstrb_q <= 4'b0;
            request_rob_q <= 3'b0;
            request_pdst_q <= 6'b0;
            request_writes_q <= 1'b0;
            request_lsu_op_q <= 3'b0;
            drop_active_q <= 1'b0;
            drop_is_write_q <= 1'b0;
            load_result_valid_q <= 1'b0;
            load_result_rob_q <= 3'b0;
            load_result_pdst_q <= 6'b0;
            load_result_writes_q <= 1'b0;
            load_result_value_q <= 32'b0;
            store_complete_valid_out <= 1'b0;
            store_complete_rob_out <= 3'b0;
        end
        else if (flush_in) begin
            for (state_i = 0; state_i < LSQ_DEPTH;
                 state_i = state_i + 1) begin
                entry_valid[state_i] <= 1'b0;
                entry_addr_valid[state_i] <= 1'b0;
                entry_issued[state_i] <= 1'b0;
            end
            request_pending_q <= 1'b0;
            memory_busy_q <= 1'b0;
            load_result_valid_q <= 1'b0;
            store_complete_valid_out <= 1'b0;
            if (drop_active_q) begin
                if (drop_response_now)
                    drop_active_q <= 1'b0;
            end
            else if (memory_busy_q && !active_response_now) begin
                drop_active_q <= 1'b1;
                drop_is_write_q <= request_write_q;
            end
            else begin
                drop_active_q <= 1'b0;
            end
        end
        else begin
            store_complete_valid_out <= 1'b0;

            if (load_result_valid_q && load_result_grant_in)
                load_result_valid_q <= 1'b0;

            if (drop_active_q && drop_response_now)
                drop_active_q <= 1'b0;

            if (dispatch0_enable_in &&
                (dispatch_count_in != 2'd0)) begin
                entry_valid[alloc_index0_out] <= 1'b1;
                entry_is_store[alloc_index0_out] <=
                    dispatch0_is_store_in;
                entry_addr_valid[alloc_index0_out] <= 1'b0;
                entry_issued[alloc_index0_out] <= 1'b0;
                entry_seq[alloc_index0_out] <= dispatch0_seq_in;
                entry_rob[alloc_index0_out] <= dispatch0_rob_in;
                entry_pdst[alloc_index0_out] <= dispatch0_pdst_in;
                entry_writes[alloc_index0_out] <= dispatch0_writes_in;
                entry_lsu_op[alloc_index0_out] <= dispatch0_lsu_op_in;
                entry_addr[alloc_index0_out] <= 32'b0;
                entry_wdata[alloc_index0_out] <= 32'b0;
                entry_wstrb[alloc_index0_out] <= 4'b0;
            end
            if (dispatch1_enable_in &&
                (dispatch_count_in == 2'd2)) begin
                entry_valid[alloc_index1_out] <= 1'b1;
                entry_is_store[alloc_index1_out] <=
                    dispatch1_is_store_in;
                entry_addr_valid[alloc_index1_out] <= 1'b0;
                entry_issued[alloc_index1_out] <= 1'b0;
                entry_seq[alloc_index1_out] <= dispatch1_seq_in;
                entry_rob[alloc_index1_out] <= dispatch1_rob_in;
                entry_pdst[alloc_index1_out] <= dispatch1_pdst_in;
                entry_writes[alloc_index1_out] <= dispatch1_writes_in;
                entry_lsu_op[alloc_index1_out] <= dispatch1_lsu_op_in;
                entry_addr[alloc_index1_out] <= 32'b0;
                entry_wdata[alloc_index1_out] <= 32'b0;
                entry_wstrb[alloc_index1_out] <= 4'b0;
            end

            if (agu_capture_valid_in &&
                entry_valid[agu_capture_index_in]) begin
                entry_addr_valid[agu_capture_index_in] <= 1'b1;
                entry_addr[agu_capture_index_in] <= agu_addr_in;
                entry_wdata[agu_capture_index_in] <= agu_wdata_in;
                entry_wstrb[agu_capture_index_in] <= agu_wstrb_in;
                entry_lsu_op[agu_capture_index_in] <= agu_lsu_op_in;
            end

            if (candidate_valid) begin
                request_pending_q <= 1'b1;
                request_write_q <= candidate_write;
                request_index_q <= candidate_index;
                request_addr_q <= entry_addr[candidate_index];
                request_wdata_q <= entry_wdata[candidate_index];
                request_wstrb_q <= entry_wstrb[candidate_index];
                request_rob_q <= entry_rob[candidate_index];
                request_pdst_q <= entry_pdst[candidate_index];
                request_writes_q <= entry_writes[candidate_index];
                request_lsu_op_q <= entry_lsu_op[candidate_index];
            end

            if (request_fire) begin
                request_pending_q <= 1'b0;
                entry_issued[request_index_q] <= 1'b1;
                if (!active_response_now)
                    memory_busy_q <= 1'b1;
            end

            if ((memory_busy_q || request_fire) &&
                active_response_now) begin
                request_pending_q <= 1'b0;
                memory_busy_q <= 1'b0;
                entry_valid[request_index_q] <= 1'b0;
                entry_addr_valid[request_index_q] <= 1'b0;
                entry_issued[request_index_q] <= 1'b0;
                if (request_write_q) begin
                    store_complete_valid_out <= 1'b1;
                    store_complete_rob_out <= request_rob_q;
                end
                else begin
                    load_result_valid_q <= 1'b1;
                    load_result_rob_q <= request_rob_q;
                    load_result_pdst_q <= request_pdst_q;
                    load_result_writes_q <= request_writes_q;
                    load_result_value_q <= extended_load_value;
                end
            end
        end
    end

endmodule
