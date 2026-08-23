`timescale 1ns/1ps

// Two-input AXI4 read arbiter.
//
// The implementation intentionally permits only one downstream read burst at
// a time. The selected source is locked from address acceptance through the
// final RLAST handshake, so no response reordering storage is required.
module axi_read_arbiter #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 2
)(
    input                               clk,
    input                               reset,

    // Source 0 read-address channel.
    input      [ID_WIDTH-1:0]           s0_axi_arid,
    input      [ADDR_WIDTH-1:0]         s0_axi_araddr,
    input      [7:0]                    s0_axi_arlen,
    input      [2:0]                    s0_axi_arsize,
    input      [1:0]                    s0_axi_arburst,
    input                               s0_axi_arlock,
    input      [3:0]                    s0_axi_arcache,
    input      [2:0]                    s0_axi_arprot,
    input      [3:0]                    s0_axi_arqos,
    input                               s0_axi_arvalid,
    output                              s0_axi_arready,

    // Source 0 read-data channel.
    output     [ID_WIDTH-1:0]           s0_axi_rid,
    output     [DATA_WIDTH-1:0]         s0_axi_rdata,
    output     [1:0]                    s0_axi_rresp,
    output                              s0_axi_rlast,
    output                              s0_axi_rvalid,
    input                               s0_axi_rready,

    // Source 1 read-address channel.
    input      [ID_WIDTH-1:0]           s1_axi_arid,
    input      [ADDR_WIDTH-1:0]         s1_axi_araddr,
    input      [7:0]                    s1_axi_arlen,
    input      [2:0]                    s1_axi_arsize,
    input      [1:0]                    s1_axi_arburst,
    input                               s1_axi_arlock,
    input      [3:0]                    s1_axi_arcache,
    input      [2:0]                    s1_axi_arprot,
    input      [3:0]                    s1_axi_arqos,
    input                               s1_axi_arvalid,
    output                              s1_axi_arready,

    // Source 1 read-data channel.
    output     [ID_WIDTH-1:0]           s1_axi_rid,
    output     [DATA_WIDTH-1:0]         s1_axi_rdata,
    output     [1:0]                    s1_axi_rresp,
    output                              s1_axi_rlast,
    output                              s1_axi_rvalid,
    input                               s1_axi_rready,

    // Downstream read-address channel.
    output     [ID_WIDTH-1:0]           m_axi_arid,
    output     [ADDR_WIDTH-1:0]         m_axi_araddr,
    output     [7:0]                    m_axi_arlen,
    output     [2:0]                    m_axi_arsize,
    output     [1:0]                    m_axi_arburst,
    output                              m_axi_arlock,
    output     [3:0]                    m_axi_arcache,
    output     [2:0]                    m_axi_arprot,
    output     [3:0]                    m_axi_arqos,
    output                              m_axi_arvalid,
    input                               m_axi_arready,

    // Downstream read-data channel.
    input      [ID_WIDTH-1:0]           m_axi_rid,
    input      [DATA_WIDTH-1:0]         m_axi_rdata,
    input      [1:0]                    m_axi_rresp,
    input                               m_axi_rlast,
    input                               m_axi_rvalid,
    output                              m_axi_rready
);

    localparam [1:0] ST_SELECT = 2'd0;
    localparam [1:0] ST_AR     = 2'd1;
    localparam [1:0] ST_R      = 2'd2;

    reg [1:0] state_q;
    reg owner_q;
    reg next_priority_q;

    reg [ID_WIDTH-1:0]   arid_q;
    reg [ADDR_WIDTH-1:0] araddr_q;
    reg [7:0]            arlen_q;
    reg [2:0]            arsize_q;
    reg [1:0]            arburst_q;
    reg                  arlock_q;
    reg [3:0]            arcache_q;
    reg [2:0]            arprot_q;
    reg [3:0]            arqos_q;

    wire choose_s1 = s1_axi_arvalid &&
                     (!s0_axi_arvalid || next_priority_q);

    assign m_axi_arid    = arid_q;
    assign m_axi_araddr  = araddr_q;
    assign m_axi_arlen   = arlen_q;
    assign m_axi_arsize  = arsize_q;
    assign m_axi_arburst = arburst_q;
    assign m_axi_arlock  = arlock_q;
    assign m_axi_arcache = arcache_q;
    assign m_axi_arprot  = arprot_q;
    assign m_axi_arqos   = arqos_q;
    assign m_axi_arvalid = (state_q == ST_AR) &&
                           (owner_q ? s1_axi_arvalid : s0_axi_arvalid);

    assign s0_axi_arready = (state_q == ST_AR) && !owner_q &&
                            m_axi_arready;
    assign s1_axi_arready = (state_q == ST_AR) && owner_q &&
                            m_axi_arready;

    assign s0_axi_rid    = m_axi_rid;
    assign s0_axi_rdata  = m_axi_rdata;
    assign s0_axi_rresp  = m_axi_rresp;
    assign s0_axi_rlast  = m_axi_rlast;
    assign s0_axi_rvalid = (state_q == ST_R) && !owner_q && m_axi_rvalid;

    assign s1_axi_rid    = m_axi_rid;
    assign s1_axi_rdata  = m_axi_rdata;
    assign s1_axi_rresp  = m_axi_rresp;
    assign s1_axi_rlast  = m_axi_rlast;
    assign s1_axi_rvalid = (state_q == ST_R) && owner_q && m_axi_rvalid;

    assign m_axi_rready = (state_q == ST_R) &&
                          (owner_q ? s1_axi_rready : s0_axi_rready);

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_q         <= ST_SELECT;
            owner_q         <= 1'b0;
            next_priority_q <= 1'b0;
            arid_q          <= {ID_WIDTH{1'b0}};
            araddr_q        <= {ADDR_WIDTH{1'b0}};
            arlen_q         <= 8'b0;
            arsize_q        <= 3'b0;
            arburst_q       <= 2'b0;
            arlock_q        <= 1'b0;
            arcache_q       <= 4'b0;
            arprot_q        <= 3'b0;
            arqos_q         <= 4'b0;
        end
        else begin
            case (state_q)
                ST_SELECT: begin
                    if (s0_axi_arvalid || s1_axi_arvalid) begin
                        owner_q <= choose_s1;
                        if (choose_s1) begin
                            arid_q    <= s1_axi_arid;
                            araddr_q  <= s1_axi_araddr;
                            arlen_q   <= s1_axi_arlen;
                            arsize_q  <= s1_axi_arsize;
                            arburst_q <= s1_axi_arburst;
                            arlock_q  <= s1_axi_arlock;
                            arcache_q <= s1_axi_arcache;
                            arprot_q  <= s1_axi_arprot;
                            arqos_q   <= s1_axi_arqos;
                        end
                        else begin
                            arid_q    <= s0_axi_arid;
                            araddr_q  <= s0_axi_araddr;
                            arlen_q   <= s0_axi_arlen;
                            arsize_q  <= s0_axi_arsize;
                            arburst_q <= s0_axi_arburst;
                            arlock_q  <= s0_axi_arlock;
                            arcache_q <= s0_axi_arcache;
                            arprot_q  <= s0_axi_arprot;
                            arqos_q   <= s0_axi_arqos;
                        end
                        state_q <= ST_AR;
                    end
                end

                ST_AR: begin
                    if (m_axi_arvalid && m_axi_arready) begin
                        state_q <= ST_R;
                    end
                end

                ST_R: begin
                    if (m_axi_rvalid && m_axi_rready && m_axi_rlast) begin
                        // Give the other source first choice next time.
                        next_priority_q <= !owner_q;
                        state_q <= ST_SELECT;
                    end
                end

                default: begin
                    state_q <= ST_SELECT;
                end
            endcase
        end
    end

`ifndef SYNTHESIS
    always @(posedge clk) begin
        if (!reset && state_q == ST_R && m_axi_rvalid && m_axi_rready &&
            (m_axi_rid != arid_q)) begin
            $error("axi_read_arbiter: response ID mismatch expected=%0d got=%0d",
                   arid_q, m_axi_rid);
        end
    end
`endif

endmodule
