#ifndef RUNNER_RUN_LOOP_H_
#define RUNNER_RUN_LOOP_H_

#include <chrono>
#include <set>

class RunLoop {
 public:
  RunLoop();
  ~RunLoop();

  void Run();

 private:
  using TimePoint = std::chrono::steady_clock::time_point;
};

#endif  // RUNNER_RUN_LOOP_H_
