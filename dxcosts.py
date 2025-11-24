#
#    Copyright (C) 2025 by Lars Wienbrandt,
#    Institute of Clinical Molecular Biology, Kiel University
#
#    This file is part of ikmb-eagleimp.
#
#    ikmb-eagleimp is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    ikmb-eagleimp is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with ikmb-eagleimp. If not, see <https://www.gnu.org/licenses/>.
#

""" Simple script that extracts price information of jobs from DNAnexus with a common tag """

import subprocess
import re
import sys

def run_cmd(cmd):
    """Run a shell command and return output as text."""
    print(f"Run cmd: {cmd}")
    result = subprocess.run(cmd, capture_output=True, text=True, shell=True)
    return result.stdout

def chr_sort_key(job_name):
    """
    Extract chromosome number from strings like 'xyz-chr1.xyz'.
    Sorts 1–22, then X (23), then Y (24).
    """

    m = re.search(r"chr(\w+)", job_name)
    if not m:
        return float('inf')  # push non-matching names to end

    chrom = m.group(1)

    if chrom.isdigit():
        return int(chrom)
    elif chrom.upper() == "X":
        return 23
    elif chrom.upper() == "Y":
        return 24
    else:
        return float('inf')

if len(sys.argv) != 2:
    print("Usage: python dxcosts.py <tag>")
    sys.exit(1)

tag = sys.argv[1]
"""Number of jobs to fetch. Should be big enough to cover all
   jobs from the analysis.
   Ensure that the tag is unique, otherwise add extra filters
   or adjust the number."""
N = 30

# 1. Get job list
raw_list = run_cmd(f"dx find jobs --tag '{tag}' -n {N}")

job_ids = []

# 2. Extract job IDs (5th whitespace-separated column)
for line in raw_list.splitlines():
    print(line)
    parts = line.strip().split()
    if len(parts) >= 5 and parts[4].startswith("job-"):
        job_ids.append(parts[4])

jobs = []

# 3. Extract job name + price for each job
for job_id in job_ids:
    desc = run_cmd(f"dx describe {job_id}")

    # Extract Job name
    m_name = re.search(r"Job name\s+(.+)", desc)
    job_name = m_name.group(1).strip() if m_name else "UNKNOWN"

    # Extract Total Price
    m_price = re.search(r"Total Price\s+£([\d.]+)", desc)
    price = float(m_price.group(1)) if m_price else 0.0

    print(f"Job name: {job_name} Price: {price}")

    jobs.append((job_name, price))

# 4. Sort by job name using 'chr<num>' as key
jobs.sort(key=lambda x: chr_sort_key(x[0]))

# 5. Print results
total_cost = sum(price for _, price in jobs)

print("\nJob name\tPrice")
for name, price in jobs:
    print(f"{name}\t{price}")

print(f"\nTotal jobs:\t{len(jobs)}")
print(f"Total cost:\t{total_cost}")

outfile = f"{re.sub(r"\s+", "_", tag)}.tsv"
with open(outfile, "w") as f:
    f.write("Job name\tPrice\n")
    for name, price in jobs:
        f.write(f"{name}\t{price}\n")
    f.write(f"\nTotal jobs:\t{len(jobs)}\n")
    f.write(f"Total cost:\t{total_cost}\n")

print(f"\nResults written to {outfile}")