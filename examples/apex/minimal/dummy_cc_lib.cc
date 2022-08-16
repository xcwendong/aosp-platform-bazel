#include <iostream>

void shared_lib_func(const char* name) {
  std::cout << "Hello from shared_lib_func, " << name << std::endl;
}
