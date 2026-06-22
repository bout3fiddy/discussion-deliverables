"""Branch prediction: the same loop runs faster on sorted input.

Sorting the input first makes the loop measurably faster, because the CPU predicts
the `if` branch almost perfectly on sorted data and mispredicts roughly half the
time on random data.

Run: uv run branch_bench.py
"""

import random
import statistics
import sys
import time


def calc_sum(values: list[int], repeat: int) -> int:
    """Sum the values below 128 and those at or above it, scanning `values` `repeat` times.

    The split `if` is the branch whose misprediction cost this benchmark measures.
    Scanning the list many times amplifies that cost above timer noise.
    """
    lo = 0
    hi = 0

    for _ in range(repeat):
        for x in values:
            if x < 128:
                lo += x
            else:
                hi += x

    return lo + hi


def median_ms(values: list[int], repeat: int, trials: int) -> float:
    """Return the median wall-clock time of calc_sum, in milliseconds, over `trials` runs."""
    calc_sum(values, repeat)  # warm up before timing

    times = []
    for _ in range(trials):
        start = time.perf_counter()
        calc_sum(values, repeat)
        times.append(time.perf_counter() - start)

    return statistics.median(times) * 1000.0


def main():
    random.seed(42)

    n = 32768
    repeat = 200
    trials = 10

    data = [random.randint(0, 255) for _ in range(n)]
    unsorted = list(data)
    ordered = sorted(data)

    slow = median_ms(unsorted, repeat, trials)
    fast = median_ms(ordered, repeat, trials)

    print(f"python {sys.version.split()[0]}, N={n}, repeat={repeat}, trials={trials}")
    print(f"unsorted input: {slow:8.2f} ms (median)")
    print(f"sorted input:   {fast:8.2f} ms (median)")
    print(f"sorted is {slow / fast:.2f}x faster")


if __name__ == "__main__":
    main()
