"""Branch prediction: the same loop runs faster on sorted input.

The source code is identical no matter how the input is ordered. Sorting the
input first makes the loop measurably faster, because the CPU predicts the `if`
branch almost perfectly on sorted data and mispredicts roughly half the time on
random data. The two runs execute the same instructions on the same values; only
the order differs. You cannot see the difference by reading the source. You have
to measure it.

Run: uv run branch_bench.py
"""

import random
import statistics
import sys
import time


def calc_sum(values):
    lo = 0
    hi = 0
    for _ in range(200):
        for x in values:
            if x < 128:
                lo += x
            else:
                hi += x
    return lo + hi


def median_ms(values):
    calc_sum(values)  # warm up
    times = []
    for _ in range(10):
        t0 = time.perf_counter()
        calc_sum(values)
        times.append(time.perf_counter() - t0)
    return statistics.median(times) * 1000.0


def main():
    random.seed(42)
    data = [random.randint(0, 255) for _ in range(32768)]
    unsorted = list(data)
    ordered = sorted(data)

    u = median_ms(unsorted)
    s = median_ms(ordered)

    print(f"python {sys.version.split()[0]}, N={32768}, repeat={200}, trials={10}")
    print(f"unsorted input: {u:8.2f} ms (median)")
    print(f"sorted input:   {s:8.2f} ms (median)")
    print(f"sorted is {u / s:.2f}x faster")

    # let's flip the order just to see if the results are consistent
    s = median_ms(ordered)
    u = median_ms(unsorted)

    print("Run order flipped ... ")

    print(f"python {sys.version.split()[0]}, N={32768}, repeat={200}, trials={10}")
    print(f"sorted input:   {s:8.2f} ms (median)")
    print(f"unsorted input: {u:8.2f} ms (median)")
    print(f"sorted is {u / s:.2f}x faster")


if __name__ == "__main__":
    main()
