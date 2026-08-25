`timescale 1ns/1ps

interface cache_uvm_if(input logic clk);
    logic reset;
    logic reset_request;
    logic flush_request;

    logic        ic_cpu_req_valid;
    logic [31:0] ic_cpu_req_addr;
    logic        ic_cpu_req_ready;
    logic        ic_cpu_resp_valid;
    logic [31:0] ic_cpu_resp_data;

    logic         ic_mem_req_valid;
    logic         ic_mem_req_ready;
    logic [31:0]  ic_mem_req_addr;
    logic         ic_mem_resp_valid;
    logic [127:0] ic_mem_resp_data;
    logic [1:0]   ic_mem_resp_code;
    logic         ic_fault_valid;
    logic [31:0]  ic_fault_addr;
    logic [1:0]   ic_fault_resp;

    logic [31:0] dc_cpu_req_addr;
    logic        dc_cpu_read_valid;
    logic        dc_cpu_read_ready;
    logic        dc_cpu_read_resp_valid;
    logic [31:0] dc_cpu_read_data;
    logic        dc_cpu_write_valid;
    logic        dc_cpu_write_ready;
    logic [3:0]  dc_cpu_write_strb;
    logic [31:0] dc_cpu_write_data;
    logic        dc_cpu_write_resp_valid;

    logic         dc_mem_read_valid;
    logic         dc_mem_read_ready;
    logic [31:0]  dc_mem_read_addr;
    logic         dc_mem_read_resp_valid;
    logic [127:0] dc_mem_read_resp_data;
    logic [1:0]   dc_mem_read_resp_code;
    logic         dc_mem_write_valid;
    logic         dc_mem_write_ready;
    logic [31:0]  dc_mem_write_addr;
    logic [127:0] dc_mem_write_data;
    logic         dc_mem_write_resp_valid;
    logic [1:0]   dc_mem_write_resp_code;
    logic         dc_fault_valid;
    logic         dc_fault_is_write;
    logic [31:0]  dc_fault_addr;
    logic [1:0]   dc_fault_resp;

    clocking cpu_cb @(posedge clk);
        default input #1step output #0;
        input reset;
        output reset_request, flush_request;
        output ic_cpu_req_valid, ic_cpu_req_addr;
        input ic_cpu_req_ready, ic_cpu_resp_valid, ic_cpu_resp_data;
        output dc_cpu_req_addr, dc_cpu_read_valid;
        input dc_cpu_read_ready, dc_cpu_read_resp_valid, dc_cpu_read_data;
        output dc_cpu_write_valid, dc_cpu_write_strb, dc_cpu_write_data;
        input dc_cpu_write_ready, dc_cpu_write_resp_valid;
    endclocking

    clocking mem_cb @(posedge clk);
        default input #1step output #0;
        input reset;
        input ic_mem_req_valid, ic_mem_req_addr;
        output ic_mem_req_ready, ic_mem_resp_valid;
        output ic_mem_resp_data, ic_mem_resp_code;
        input dc_mem_read_valid, dc_mem_read_addr;
        output dc_mem_read_ready, dc_mem_read_resp_valid;
        output dc_mem_read_resp_data, dc_mem_read_resp_code;
        input dc_mem_write_valid, dc_mem_write_addr, dc_mem_write_data;
        output dc_mem_write_ready, dc_mem_write_resp_valid;
        output dc_mem_write_resp_code;
    endclocking

    clocking mon_cb @(posedge clk);
        default input #1step;
        input reset, flush_request;
        input ic_cpu_req_valid, ic_cpu_req_addr, ic_cpu_req_ready;
        input ic_cpu_resp_valid, ic_cpu_resp_data;
        input ic_mem_req_valid, ic_mem_req_ready, ic_mem_req_addr;
        input ic_mem_resp_valid, ic_mem_resp_code;
        input ic_fault_valid, ic_fault_addr, ic_fault_resp;
        input dc_cpu_req_addr, dc_cpu_read_valid, dc_cpu_read_ready;
        input dc_cpu_read_resp_valid, dc_cpu_read_data;
        input dc_cpu_write_valid, dc_cpu_write_ready;
        input dc_cpu_write_strb, dc_cpu_write_data, dc_cpu_write_resp_valid;
        input dc_mem_read_valid, dc_mem_read_ready, dc_mem_read_addr;
        input dc_mem_read_resp_valid, dc_mem_read_resp_code;
        input dc_mem_write_valid, dc_mem_write_ready, dc_mem_write_addr;
        input dc_mem_write_resp_valid, dc_mem_write_resp_code;
        input dc_fault_valid, dc_fault_is_write, dc_fault_addr, dc_fault_resp;
    endclocking
endinterface
