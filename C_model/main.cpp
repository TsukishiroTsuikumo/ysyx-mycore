#include "model.hpp"
#include <iostream>

int main() {
    std::cout << "Starting simulation..." << std::endl;
    mycore core;
    for (int i = 0; i < 4000; i++) {
        core.step();
    }
    std::cout << "Simulation completed." << std::endl;
    return 0;
}
