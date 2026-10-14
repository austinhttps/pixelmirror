#include "run_loop.h"

#include <windows.h>

RunLoop::RunLoop() {}
RunLoop::~RunLoop() {}

void RunLoop::Run() {
  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
}
