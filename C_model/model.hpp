#pragma once

#include "state.hpp"
#include <string>

class mycore {
    public:
        mycore() : state_({0, {0}}), mem_() {};
        void step();
    private:
        mycore_state state_;
        memory mem_;
};
